/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Afega video: 6 MHz pixel clock, 384x278 total (56.2 Hz). Visible 256x224 = MAME rows 16-239 (line numbers as in MAME).
 * Palette: 768 words RRRRGGGGBBBBRGBx. bg 0x000 + pen, sprites 0x100 + colour * 16, text 0x200 + colour * 16.
 * Order: bg, sprites, text (sprites are under the text layer). */

module jtafega_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 1:0] tmod,
    input              omask,
    input              oen,
    input       [15:0] bg_scrx, bg_scry, tx_scrx, tx_scry,

    output      [13:1] bgram_video_addr,
    input       [15:0] bgram_video_dout,
    output      [10:1] txram_video_addr,
    input       [15:0] txram_video_dout,
    output      [15:1] wram_video_addr,
    input       [15:0] wram_video_dout,
    output reg  [10:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [21:2] bg_addr,
    output             bg_cs,
    input       [31:0] bg_data,
    input              bg_ok,
    output      [15:2] tx_addr,
    output             tx_cs,
    input       [31:0] tx_data,
    input              tx_ok,
    output      [19:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,

    output reg  [ 8:0] vdump,
    output             hs_start,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd383, HS_START=9'd300, HS_END=9'd332;
localparam [8:0] VTOTAL=9'd277, VB_END=9'd16, VB_START=9'd240, VS_START=9'd250, VS_END=9'd253;

reg  [ 8:0] hdump=0, vrender=1;
reg         lhbl, lvbl, hs_l;
reg  [ 3:0] hbl_sh, vbl_sh;
wire [ 7:0] bg_q, tx_q, obj_q;
reg  [ 7:0] bgp, txp, objp;
reg  [ 9:0] idx;
wire [11:0] bgx = bg_scrx[11:0] - 12'h100;

assign LHBL     = hbl_sh[2];
assign LVBL     = vbl_sh[2];
assign hs_start = pxl_cen && hdump==0 && !hs_l;

always @(posedge clk) if( pxl_cen ) hs_l <= hdump==0;

initial vdump = 0;
always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    lhbl <= hdump==HTOTAL || hdump < 9'd255;   // value for the next hdump
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[2:0], lhbl };
    vbl_sh <= { vbl_sh[2:0], lvbl };
end

jtafega_bg u_bg(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .tmod       ( tmod             ),
    .hdump      ( hdump            ),
    .hs_start   ( hs_start         ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scrx       ( bgx              ),
    .scry       ( bg_scry[8:0]     ),
    .vram_addr  ( bgram_video_addr ),
    .vram_dout  ( bgram_video_dout ),
    .rom_addr   ( bg_addr          ),
    .rom_cs     ( bg_cs            ),
    .rom_data   ( bg_data          ),
    .rom_ok     ( bg_ok            ),
    .pxl        ( bg_q             )
);

jtafega_tx u_tx(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .hdump      ( hdump            ),
    .hs_start   ( hs_start         ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scrx       ( tx_scrx[7:0]     ),
    .scry       ( tx_scry[7:0]     ),
    .vram_addr  ( txram_video_addr ),
    .vram_dout  ( txram_video_dout ),
    .rom_addr   ( tx_addr          ),
    .rom_cs     ( tx_cs            ),
    .rom_data   ( tx_data          ),
    .rom_ok     ( tx_ok            ),
    .pxl        ( tx_q             )
);

jtafega_obj u_obj(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .pxl_cen    ( pxl_cen          ),
    .omask      ( omask            ),
    .oen        ( oen              ),
    .hdump      ( hdump            ),
    .hs_start   ( hs_start         ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .wram_addr  ( wram_video_addr  ),
    .wram_dout  ( wram_video_dout  ),
    .rom_addr   ( obj_addr         ),
    .rom_cs     ( obj_cs           ),
    .rom_data   ( obj_data         ),
    .rom_ok     ( obj_ok           ),
    .pxl        ( obj_q            )
);

wire tx_on  = gfx_en[1] && txp[3:0] != 4'hf;
wire obj_on = gfx_en[3] && objp[3:0] != 4'hf;

always @* begin
    idx = gfx_en[0] ? { 2'b00, bgp } : 10'd0;
    if( obj_on ) idx = { 2'b01, objp };
    if( tx_on  ) idx = { 2'b10, txp  };
end

always @(posedge clk) if( pxl_cen ) begin
    bgp  <= bg_q;
    txp  <= tx_q;
    objp <= obj_q;
    pal_video_addr <= idx;
    red   <= { pal_video_dout[15:12], pal_video_dout[3] };
    green <= { pal_video_dout[11: 8], pal_video_dout[2] };
    blue  <= { pal_video_dout[ 7: 4], pal_video_dout[1] };
end

endmodule
