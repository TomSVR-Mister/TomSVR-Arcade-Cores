/* SPDX-License-Identifier: GPL-3.0-or-later
   Bottom of the Ninth colour mixer, following MAME bottom9.cpp screen_update:
   pen 0 background, then K051316 (pen 0 transparent), layer B, layer A, each above the previous one.
   Sprites are always behind layer A, behind the K051316 when colour bit 4 is set and behind layer B when
   colour bit 5 is clear. Pen 15 of a shadow sprite darkens what is below it (MAME's 0.6 shadow factor).
   Palette: 0-63 layer A, 256-319 layer B, 512-767 sprites, 768-1023 K051316. xBGR_555, big endian bytes */

module jtbottom9_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             lhbl,
    input             lvbl,
    input             video_en,

    input      [10:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_we,
    output     [ 7:0] cpu_din,

    input      [ 7:0] apxl, bpxl, rpx,   // {colour, pen}
    input             ablnk_n, bblnk_n, rblk_n,
    input      [11:0] opxl,
    input             oblnk_n, oshadow,

    output reg [ 7:0] red,
    output reg [ 7:0] green,
    output reg [ 7:0] blue
);

wire [ 7:0] hi_cpu, lo_cpu, hi, lo;
reg  [ 9:0] idx;
reg         shade, obj_vis;
wire [ 8:0] f = shade ? 9'd154 : 9'd256;

assign cpu_din = cpu_addr[0] ? lo_cpu : hi_cpu;

always @* begin
    obj_vis = oblnk_n && !ablnk_n && !(rblk_n && opxl[8]) && !(bblnk_n && !opxl[9]);
    shade   = 0;
    if( !video_en )
        idx = 0;
    else if( obj_vis && !oshadow )
        idx = { 2'b10, opxl[7:0] };
    else begin
        shade = obj_vis;
        idx   = ablnk_n ? { 4'b0000, apxl[7:6], apxl[3:0] } :
                bblnk_n ? { 4'b0100, bpxl[7:6], bpxl[3:0] } :
                rblk_n  ? { 2'b11,   rpx } : 10'd0;
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
        red   <= (lhbl & lvbl) ? scale( lo[4:0], f ) : 8'd0;
        green <= (lhbl & lvbl) ? scale( {hi[1:0],lo[7:5]}, f ) : 8'd0;
        blue  <= (lhbl & lvbl) ? scale( hi[6:2], f ) : 8'd0;
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

`ifdef SIMULATION
integer ca=0, cb=0, cr=0, co=0, cf=0;
reg lvbl_l;
always @(posedge clk) if( pxl_cen ) begin
    lvbl_l <= lvbl;
    if( lhbl & lvbl ) begin
        ca <= ca + ablnk_n; cb <= cb + bblnk_n; cr <= cr + rblk_n; co <= co + oblnk_n;
        cf <= cf + (hi!=0 || lo!=0);
    end
    if( !lvbl && lvbl_l ) begin
        $display("PX a=%0d b=%0d r=%0d o=%0d colored=%0d en=%b", ca, cb, cr, co, cf, video_en);
        ca<=0; cb<=0; cr<=0; co<=0; cf<=0;
    end
end
`endif

endmodule
