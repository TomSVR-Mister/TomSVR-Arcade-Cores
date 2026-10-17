/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hot Blocks video (MAME hotblock.cpp): 8 MHz pixel clock, 512x312 total (50 Hz), 320x200 visible.
 * 320x200 8-bit framebuffer at the start of the video RAM, 256-colour palette (xBGR_555, low byte first).
 * The screen is black unless port 0 bit 6 is set. */

module jthotblk_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             enable,
    output reg [15:0] vram_video_addr,
    input      [ 7:0] vram_video_dout,
    output     [ 7:0] pallo_video_addr,
    input      [ 7:0] pallo_video_dout,
    output     [ 7:0] palhi_video_addr,
    input      [ 7:0] palhi_video_dout,
    output            vbl_irq,
    output            LHBL,
    output            LVBL,
    output reg        HS,
    output reg        VS,
    output reg [ 4:0] red,
    output reg [ 4:0] green,
    output reg [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd511, HS_START=9'd400, HS_END=9'd432;
localparam [8:0] VTOTAL=9'd311, VB_START=9'd200, VS_START=9'd250, VS_END=9'd253;

reg  [8:0] hdump=0, vdump=0;
reg        lhbl, lvbl;
reg  [3:0] hbl_sh, vbl_sh;
reg  [7:0] pxl;
reg  [1:0] en_sh;

assign LHBL    = hbl_sh[2];
assign LVBL    = vbl_sh[2];
assign vbl_irq = lvbl;
assign pallo_video_addr = pxl;
assign palhi_video_addr = pxl;

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump <= vdump==VTOTAL ? 9'd0 : vdump+9'd1;
        lvbl  <= (vdump==VTOTAL ? 9'd0 : vdump+9'd1) < VB_START;
    end
    lhbl <= hdump==HTOTAL || hdump < 9'd319;
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[2:0], lhbl };
    vbl_sh <= { vbl_sh[2:0], lvbl };
    // E0: address, E1: pixel, E2: palette entry, E3: colour
    vram_video_addr <= { vdump[7:0], 8'd0 } + { 2'd0, vdump[7:0], 6'd0 } + { 7'd0, hdump };
    pxl   <= vram_video_dout;
    en_sh <= { en_sh[0], enable };
    { blue, green, red } <= en_sh[1] ? { palhi_video_dout[6:0], pallo_video_dout } : 15'd0;
end

endmodule
