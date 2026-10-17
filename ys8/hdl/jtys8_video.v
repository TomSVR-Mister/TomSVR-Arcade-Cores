/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 8-bit video: 8 MHz pixel clock, 512x262 total, MAME visible area X 64-447, Y 8-247.
 * Background (opaque; pen 0 when disabled) under the text layer (pen 0 transparent). Palette: 2048 entries xBBBBBGGGGGRRRRR. */

module jtys8_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input              flip,
    input       [ 1:0] layers,
    input              bgbig,

    output      [10:0] t0lo_video_addr, t0hi_video_addr, c0_video_addr,
    input       [ 7:0] t0lo_video_dout, t0hi_video_dout, c0_video_dout,
    output      [10:0] t1lo_video_addr, t1hi_video_addr, c1_video_addr,
    input       [ 7:0] t1lo_video_dout, t1hi_video_dout, c1_video_dout,
    output reg  [10:0] plo_video_addr,
    output      [10:0] phi_video_addr,
    input       [ 7:0] plo_video_dout, phi_video_dout,

    output      [20:2] bgt_addr,
    output             bgt_cs,
    input       [31:0] bgt_data,
    input              bgt_ok,
    output      [17:2] fgt_addr,
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

localparam [8:0] HTOTAL=9'd511, HS_START=9'd470, HS_END=9'd502;
localparam [8:0] VTOTAL=9'd261, VB_END=9'd8, VB_START=9'd248, VS_START=9'd252, VS_END=9'd255;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl;
reg  [ 2:0] hbl_sh, vbl_sh;
wire [10:0] bg, fg, bg_va, fg_va;
wire [15:0] pal = { phi_video_dout, plo_video_dout };

assign LHBL    = hbl_sh[1];
assign LVBL    = vbl_sh[1];
assign vbl_irq = lvbl;
assign t0lo_video_addr = bg_va, t0hi_video_addr = bg_va, c0_video_addr = bg_va;
assign t1lo_video_addr = fg_va, t1hi_video_addr = fg_va, c1_video_addr = fg_va;
assign phi_video_addr  = plo_video_addr;

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    lhbl <= hdump >= 9'd63 && hdump < 9'd447;   // value for the next hdump
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[1:0], lhbl };
    vbl_sh <= { vbl_sh[1:0], lvbl };
end

jtys8_tile #(.BG8(1),.AW(21)) u_bg(
    .rst(rst), .clk(clk), .flip(flip), .big(bgbig), .hdump(hdump), .vrender(vrender), .vdump(vdump),
    .vram_addr(bg_va), .lo_dout(t0lo_video_dout), .hi_dout(t0hi_video_dout), .col_dout(c0_video_dout),
    .rom_addr(bgt_addr), .rom_cs(bgt_cs), .rom_data(bgt_data), .rom_ok(bgt_ok), .pxl(bg) );

jtys8_tile #(.BG8(0),.AW(18)) u_fg(
    .rst(rst), .clk(clk), .flip(flip), .big(1'b0), .hdump(hdump), .vrender(vrender), .vdump(vdump),
    .vram_addr(fg_va), .lo_dout(t1lo_video_dout), .hi_dout(t1hi_video_dout), .col_dout(c1_video_dout),
    .rom_addr(fgt_addr), .rom_cs(fgt_cs), .rom_data(fgt_data), .rom_ok(fgt_ok), .pxl(fg) );

always @(posedge clk) if( pxl_cen ) begin
    plo_video_addr <= (layers[1] && gfx_en[1] && fg[3:0]!=0) ? fg :
                      (layers[0] && gfx_en[0]) ? bg : 11'd0;
    red   <= pal[ 4: 0];
    green <= pal[ 9: 5];
    blue  <= pal[14:10];
end

endmodule
