/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Splash! sprites (MAME splash_v.cpp): 256 entries of 4 words plus one attribute word at +0x400:
 *   0: code low, 1: Y, 2: X low, 3: { flipy, flipx, -, -, code[11:8] },
 *   +0x400: { X bit 8, -, -, -, colour } in the high byte (the low byte on Splash! 1.0).
 *   Screen position (X - 8, (240 - Y) & 0xff), 16x16x4, pen 0 transparent, colour 0x10 + colour.
 *   MAME draws entry 255 first and entry 0 last, so lower entries are on top: the list is scanned 255..0
 *   and later sprites overwrite earlier ones.
 * Sprite ROM in SDRAM: 32-bit words { code, right half, row }, byte k = bit plane k (byte 0 = pen bit 3). */

module jtsplash_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              hs,
    input              lo_attr,     // Splash! 1.0: colour/X bit 8 in the low byte of the attribute word
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 3:0] hoffset,

    output reg  [11:1] ram_addr,
    input       [15:0] ram_dout,

    output      [18:2] rom_addr,
    output             rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl          // { colour, pen }; pen 0 = transparent
);

localparam [2:0] IDLE=0, SCAN=1, RD1=2, RD2=3, RD3=4, RD4=5, RD5=6, DRAW=7;

reg  [ 2:0] st;
reg  [ 8:0] line;
reg  [ 7:0] hit, p1_idx, p2_idx;
reg  [ 8:0] aidx;             // next entry to address, counts down (bit 8 set = done)
reg         p1_v, p2_v;
wire [ 7:0] sy_nx    = 8'd240 - ram_dout[7:0];
wire [ 8:0] ydiff_nx = line - { 1'b0, sy_nx };
reg         hs_l;
reg  [ 3:0] ydiff;
reg  [ 7:0] xlo;
reg  [11:0] code;
reg  [ 1:0] flip;
reg  [ 7:0] attr2;
reg         draw;
wire        busy;
wire [31:0] sorted;
wire [ 7:0] pre_pxl;
reg  [ 7:0] dly[0:15];
integer     i;

function [7:0] rev( input [7:0] x );
    rev = { x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7] };
endfunction

// jtframe_draw wants { plane3, plane2, plane1, plane0 } with the leftmost pixel in each byte's LSB
assign sorted = { rev(rom_data[7:0]), rev(rom_data[15:8]), rev(rom_data[23:16]), rev(rom_data[31:24]) };
assign pxl    = dly[hoffset];

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
            // Y words are requested every clock and checked two clocks later (BRAM latency)
            SCAN: begin
                ram_addr <= { 1'b0, aidx[7:0], 2'd1 };
                p1_idx   <= aidx[7:0];
                p1_v     <= !aidx[8];
                p2_idx   <= p1_idx;
                p2_v     <= p1_v;
                if( !aidx[8] ) aidx <= aidx - 1'd1;
                if( p2_v && ydiff_nx[8:4]==0 ) begin
                    ydiff    <= ydiff_nx[3:0];
                    hit      <= p2_idx;
                    ram_addr <= { 1'b0, p2_idx, 2'd0 };
                    st       <= RD1;
                end else if( !p2_v && !p1_v && aidx[8] ) begin
                    st <= IDLE;
                end
            end
            RD1: begin ram_addr <= { 1'b0, hit, 2'd2 }; st <= RD2; end
            RD2: begin ram_addr <= { 1'b0, hit, 2'd3 }; code[7:0] <= ram_dout[7:0]; st <= RD3; end
            RD3: begin ram_addr <= { 1'b1, hit, 2'd0 }; xlo <= ram_dout[7:0]; st <= RD4; end
            RD4: begin code[11:8] <= ram_dout[3:0]; flip <= ram_dout[7:6]; st <= RD5; end
            RD5: begin attr2 <= lo_attr ? ram_dout[7:0] : ram_dout[15:8]; st <= DRAW; end
            DRAW: if( !busy && !draw ) begin
                draw <= 1;
                aidx <= { 1'b0, hit } - 9'd1;
                p1_v <= 0;
                p2_v <= 0;
                st   <= SCAN;
            end
            default: st <= IDLE;
        endcase
        if( hs && !hs_l ) begin
            line <= vrender + 9'd1;   // shown after the next buffer swap (HS)
            aidx <= 9'd255;
            p1_v <= 0;
            p2_v <= 0;
            st   <= SCAN;
        end
    end
end

jtframe_objdraw #(.AW(9),.CW(12),.PW(8),.LATCH(1),.KEEP_OLD(0),.ALPHA(0)) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( hdump         ),

    .draw       ( draw          ),
    .busy       ( busy          ),
    .code       ( code          ),
    .xpos       ( { attr2[7], xlo } - 9'd9 ),   // MAME: X - 8; one more for the line buffer delay (measured)
    .ysub       ( ydiff         ),
    .hzoom      ( 6'd0          ),
    .hz_keep    ( 1'b0          ),

    .hflip      ( flip[0]       ),
    .vflip      ( flip[1]       ),
    .pal        ( attr2[3:0]    ),

    .rom_addr   ( rom_addr      ),
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
