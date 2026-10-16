/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 16 sprites (MAME yunsun16.cpp): 512 entries of 4 words
 *   0: X, 1: Y, 2: code, 3: attr (colour 4:0, flip X bit 5, flip Y bit 6). 16x16x4, pen 15 transparent.
 *   Screen position = (X - 0x40, Y - 0x0f). Higher entries are on top: MAME draws 511 down to 0 but
 *   prio_transpen never overwrites a sprite pixel, so here the list is drawn 0..511 and later entries overwrite.
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

localparam [2:0] IDLE=0, SCAN=1, RD0=2, RD1=3, RD2=4, RD3=5, RD4=6, DRAW=7;

reg  [ 2:0] st;
reg  [ 8:0] line, hit;
reg  [ 9:0] aidx;             // next entry to address (>511 = done)
reg  [ 8:0] p1_idx, p2_idx;
reg         p1_v, p2_v;
wire [15:0] ydiff_nx = { 7'd0, line } + 16'd15 - ram_dout;   // valid for p2_idx
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
            // The BRAM returns data two clocks after ram_addr is set: Y words are requested every clock
            // and checked two clocks later, so entries that are not on this line cost one clock each.
            SCAN: begin
                ram_addr <= { aidx[8:0], 2'd1 };
                p1_idx   <= aidx[8:0];
                p1_v     <= !aidx[9];
                p2_idx   <= p1_idx;
                p2_v     <= p1_v;
                if( !aidx[9] ) aidx <= aidx + 1'd1;
                if( p2_v && ydiff_nx[15:4]==0 ) begin
                    ydiff    <= ydiff_nx;
                    hit      <= p2_idx;
                    ram_addr <= { p2_idx, 2'd0 };
                    st       <= RD1;
                end else if( !p2_v && !p1_v && aidx[9] ) begin
                    st <= IDLE;
                end
            end
            RD1: begin ram_addr <= { hit, 2'd2 }; st <= RD2; end
            RD2: begin ram_addr <= { hit, 2'd3 }; xs <= ram_dout - 16'h40; st <= RD3; end
            RD3: begin code <= ram_dout[12:0]; st <= RD4; end
            RD4: begin attr <= ram_dout[6:0];  st <= DRAW; end
            DRAW: if( !busy && !draw ) begin
                // draw only when X is in -15..379
                if( xs + 16'd15 < 16'd395 ) draw <= 1;
                aidx <= { 1'b0, hit } + 10'd1;
                p1_v <= 0;
                p2_v <= 0;
                st   <= SCAN;
            end
            default: st <= IDLE;
        endcase
        if( hs && !hs_l ) begin
            line <= vrender + 9'd1;   // shown after the next buffer swap (HS)
            aidx     <= 10'd0;
            p1_v     <= 0;
            p2_v     <= 0;
            st       <= SCAN;
        end
    end
end

jtframe_objdraw #(.AW(9),.CW(13),.PW(9),.LATCH(1),.KEEP_OLD(0),.ALPHA(15)) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( hdump         ),

    .draw       ( draw          ),
    .busy       ( busy          ),
    .code       ( code          ),
    .xpos       ( xs[8:0]-9'd1  ),   // -1: measured against MAME
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
