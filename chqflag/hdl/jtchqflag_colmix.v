/* SPDX-License-Identifier: GPL-3.0-or-later
   Chequered Flag colour mixer, following MAME chqflag.cpp screen_update:
   051316 #2 (8 bpp, opaque) at the back, its pens C0-FF in front of sprites without the priority bit,
   then sprites, then 051316 #1 (4 bpp, pen 0 transparent) on top.
   Palette: 0-255 sprites, 256-511 051316 #1, 512-1023 051316 #2. xBGR_555, big endian bytes.
   vreg bits 7 and 3 dim the background (pens 512-1023) and set the highlight strength. */

module jtchqflag_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             lhbl,
    input             lvbl,

    input      [10:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_we,
    output     [ 7:0] cpu_din,
    input      [ 7:0] vreg,
    input             hl_mode,

    input      [ 8:0] rpxa, rpxb,
    input             rblka_n, rblkb_n,
    input      [11:0] opxl,
    input             oblnk_n, oshadow,

    output reg [ 7:0] red,
    output reg [ 7:0] green,
    output reg [ 7:0] blue
);

wire [ 7:0] hi_cpu, lo_cpu, hi, lo;
wire [ 1:0] dim_lvl = { vreg[7], vreg[3] };
reg  [ 9:0] idx;
reg         bg, shade;
reg  [10:0] f;
wire        b_front = rpxb[7:6]==2'b11;
wire        oprio   = opxl[8];          // sprite colour bit 4: in front of everything

assign cpu_din = cpu_addr[0] ? lo_cpu : hi_cpu;

always @* begin
    bg    = 0;
    shade = 0;
    if( rblka_n )
        idx = { 2'b01, rpxa[7:0] };
    else if( oblnk_n && (oprio || !b_front) )
        idx = { 2'b00, opxl[7:0] };
    else begin
        idx   = { 1'b1, rpxb };
        bg    = 1;
        shade = oshadow && (oprio || !b_front);
    end
end

function [7:0] scale( input [4:0] c, input [8:0] k );
    reg [16:0] m;
    begin
        m = {c, c[4:2]} * k;
        scale = m[16] ? 8'hff : m[15:8];
    end
endfunction

always @(posedge clk) begin
    if( rst ) begin
        red <= 0; green <= 0; blue <= 0;
    end else if( pxl_cen ) begin
        // idx has been stable since the last pxl_cen, so hi/lo hold its colour
        case( {shade, hl_mode} )
            2'b10:   f = 11'd192;                 // shadow 0.75
            2'b11:   case( dim_lvl )             // highlight 1.1, 1.15, 1.25, 1.45
                        0: f = 11'd282;
                        1: f = 11'd294;
                        2: f = 11'd320;
                        default: f = 11'd371;
                     endcase
            default: f = 11'd256;
        endcase
        if( bg && dim_lvl[1] ) f = (f*11'd3)>>2;  // background contrast 0.75
        red   <= (lhbl & lvbl) ? scale( lo[4:0], f[8:0] ) : 8'd0;
        green <= (lhbl & lvbl) ? scale( {hi[1:0],lo[7:5]}, f[8:0] ) : 8'd0;
        blue  <= (lhbl & lvbl) ? scale( hi[6:2], f[8:0] ) : 8'd0;
    end
end

jtframe_dual_ram #(.AW(10)) u_hi(
    .clk0   ( clk           ),
    .data0  ( cpu_dout      ),
    .addr0  ( cpu_addr[10:1]),
    .we0    ( cpu_we & ~cpu_addr[0] ),
    .q0     ( hi_cpu        ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( idx           ),
    .we1    ( 1'b0          ),
    .q1     ( hi            )
);

jtframe_dual_ram #(.AW(10)) u_lo(
    .clk0   ( clk           ),
    .data0  ( cpu_dout      ),
    .addr0  ( cpu_addr[10:1]),
    .we0    ( cpu_we & cpu_addr[0] ),
    .q0     ( lo_cpu        ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( idx           ),
    .we1    ( 1'b0          ),
    .q1     ( lo            )
);

endmodule
