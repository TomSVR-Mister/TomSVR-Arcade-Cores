/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 16 sprites (MAME yunsun16.cpp): 512 entries of 4 words
 *   0: X, 1: Y, 2: code, 3: attr (colour 4:0, flip X bit 5, flip Y bit 6). 16x16x4, pen 15 transparent.
 *   Screen position = (X - 0x40, Y - 0x0f). Lower entries are drawn on top.
 * Sprite ROM in SDRAM: 32-bit words { u23, u22, u21, u20 } (one byte per bit plane). */

module jtys16_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              hs,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 3:0] hoffset,

    output reg  [11:1] ram_addr,
    input       [15:0] ram_dout,

    output      [19:2] rom_addr,
    output             rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 8:0] pxl          // {colour, pen}; pen 15 = transparent
);

localparam [3:0] IDLE=0, Y0=1, Y1=2, Y2=3, X1=4, X2=5, C1=6, C2=7, T1=8, T2=9, DRAW=10;

reg  [ 3:0] st;
reg  [ 8:0] idx, line;
reg         hs_l;
reg  [15:0] ydiff, xs;
reg  [12:0] code;
reg  [ 6:0] attr;
reg         draw;
wire        busy;
wire [19:2] raw_addr;
wire [31:0] sorted;
wire [ 8:0] pre_pxl;
reg  [ 8:0] dly[0:15];
integer     i;

function [7:0] rev( input [7:0] x );
    rev = { x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7] };
endfunction

// jtframe_draw wants { plane3, plane2, plane1, plane0 } with the leftmost pixel in each byte's LSB.
// MAME plane order (MSB first): u23, u21, u22, u20
assign sorted   = { rev(rom_data[31:24]), rev(rom_data[15:8]), rev(rom_data[23:16]), rev(rom_data[7:0]) };
// raw_addr = { code, H, Y }  ->  SDRAM word { code, Y, H }
assign rom_addr = { raw_addr[19:7], raw_addr[5:2], raw_addr[6] };
assign pxl      = dly[hoffset];

always @(posedge clk) begin
    if( rst ) begin
        st   <= IDLE;
        draw <= 0;
        hs_l <= 0;
    end else begin
        hs_l <= hs;
        draw <= 0;
        case( st )
            IDLE: ;
            Y0: begin ram_addr <= { idx, 2'd1 }; st <= Y1; end
            Y1: st <= Y2;
            Y2: begin
                ydiff <= { 7'd0, line } + 16'd15 - ram_dout;
                ram_addr <= { idx, 2'd0 };
                st <= X1;
            end
            X1: begin
                if( ydiff[15:4]!=0 ) begin  // not on this line
                    idx <= idx + 1'd1;
                    st  <= idx==511 ? IDLE : Y0;
                end else st <= X2;
            end
            X2: begin
                xs <= ram_dout - 16'h40;
                ram_addr <= { idx, 2'd2 };
                st <= C1;
            end
            C1: st <= C2;
            C2: begin
                code <= ram_dout[12:0];
                ram_addr <= { idx, 2'd3 };
                st <= T1;
            end
            T1: st <= T2;
            T2: begin
                attr <= ram_dout[6:0];
                st   <= DRAW;
            end
            DRAW: if( !busy && !draw ) begin
                // draw only when X is in -15..379
                if( xs + 16'd15 < 16'd395 ) draw <= 1;
                idx <= idx + 1'd1;
                st  <= idx==511 ? IDLE : Y0;
            end
            default: st <= IDLE;
        endcase
        if( hs && !hs_l ) begin
            line <= vrender + 9'd1;   // shown after the next buffer swap (HS)
            idx  <= 0;
            st   <= Y0;
        end
    end
end

jtframe_objdraw #(.AW(9),.CW(13),.PW(9),.LATCH(1),.KEEP_OLD(1),.ALPHA(15)) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( hdump         ),

    .draw       ( draw          ),
    .busy       ( busy          ),
    .code       ( code          ),
    .xpos       ( xs[8:0]       ),
    .ysub       ( ydiff[3:0]    ),
    .hzoom      ( 6'd0          ),
    .hz_keep    ( 1'b0          ),

    .hflip      ( attr[5]       ),
    .vflip      ( attr[6]       ),
    .pal        ( attr[4:0]     ),

    .rom_addr   ( raw_addr      ),
    .rom_cs     ( rom_cs        ),
    .rom_ok     ( rom_ok        ),
    .rom_data   ( sorted        ),

    .pxl        ( pre_pxl       )
);

always @(posedge clk) if(pxl_cen) begin
    dly[0] <= pre_pxl;
    for(i=1;i<16;i=i+1) dly[i] <= dly[i-1];
end

endmodule
