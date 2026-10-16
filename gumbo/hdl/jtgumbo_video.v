/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gumbo video: 8 MHz pixel clock, 512x260 total (60 Hz), MAME visible area X 64-383, Y 16-239.
 * bg (opaque, palette 000-0ff) under fg (palette 100-1ff, pen ff transparent). Palette: 512 words xRGB_555. */

module jtgumbo_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input              bgbig, fgbig,

    output      [11:0] bgram_video_addr,
    input       [15:0] bgram_video_dout,
    output      [13:0] fgram_video_addr,
    input       [15:0] fgram_video_dout,
    output reg  [ 8:0] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [20:2] bgt_addr,
    output             bgt_cs,
    input       [31:0] bgt_data,
    input              bgt_ok,
    output      [18:2] fgt_addr,
    output             fgt_cs,
    input       [31:0] fgt_data,
    input              fgt_ok,

    output             vbl_irq,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd511, HS_START=9'd420, HS_END=9'd452;
localparam [8:0] VTOTAL=9'd259, VB_END=9'd16, VB_START=9'd240, VS_START=9'd244, VS_END=9'd247;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl;
reg  [ 2:0] hbl_sh, vbl_sh;
wire [ 7:0] bg, fg;
wire [12:0] bg_vaddr, fg_vaddr;

assign LHBL     = hbl_sh[1];
assign LVBL     = vbl_sh[1];
assign vbl_irq  = lvbl;
assign bgram_video_addr = bg_vaddr[11:0];
assign fgram_video_addr = { 1'b0, fg_vaddr };

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    lhbl <= hdump >= 9'd63 && hdump < 9'd383;   // value for the next hdump
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[1:0], lhbl };
    vbl_sh <= { vbl_sh[1:0], lvbl };
end

jtgumbo_tile #(.SMALL(0),.AW(21)) u_bg(
    .rst(rst), .clk(clk), .big(bgbig), .hdump(hdump), .vrender(vrender), .vdump(vdump),
    .vram_addr(bg_vaddr), .vram_dout(bgram_video_dout),
    .rom_addr(bgt_addr), .rom_cs(bgt_cs), .rom_data(bgt_data), .rom_ok(bgt_ok), .pxl(bg) );

jtgumbo_tile #(.SMALL(1),.AW(19)) u_fg(
    .rst(rst), .clk(clk), .big(fgbig), .hdump(hdump), .vrender(vrender), .vdump(vdump),
    .vram_addr(fg_vaddr), .vram_dout(fgram_video_dout),
    .rom_addr(fgt_addr), .rom_cs(fgt_cs), .rom_data(fgt_data), .rom_ok(fgt_ok), .pxl(fg) );

always @(posedge clk) if( pxl_cen ) begin
    pal_video_addr <= (gfx_en[1] && fg != 8'hff) ? { 1'b1, fg } : { 1'b0, gfx_en[0] ? bg : 8'd0 };
    red   <= pal_video_dout[14:10];
    green <= pal_video_dout[ 9: 5];
    blue  <= pal_video_dout[ 4: 0];
end

endmodule
