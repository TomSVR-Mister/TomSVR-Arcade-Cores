/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 16 video: 8 MHz pixel clock, 512x260 total, 380x224 visible (MAME) */

module jtys16_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input              mb,          // Magic Bubble YS1302: visible X 32-351 (MAME)
    input       [ 7:0] debug_bus,

    input       [15:0] scr0x, scr0y, scr1x, scr1y, prio,

    output      [13:1] vram0_video_addr,
    input       [15:0] vram0_video_dout,
    output      [13:1] vram1_video_addr,
    input       [15:0] vram1_video_dout,
    output      [11:1] objram_video_addr,
    input       [15:0] objram_video_dout,
    output      [13:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [21:2] scr0_addr,
    output             scr0_cs,
    input       [31:0] scr0_data,
    input              scr0_ok,
    output      [21:2] scr1_addr,
    output             scr1_cs,
    input       [31:0] scr1_data,
    input              scr1_ok,
    output      [19:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,

    output             vbl_irq,     // low during vblank (undelayed)
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output      [ 4:0] red,
    output      [ 4:0] green,
    output      [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd511, HS_START=9'd420, HS_END=9'd452;
localparam [8:0] VTOTAL=9'd259, VB_START=9'd224, VS_START=9'd236, VS_END=9'd240;
localparam [3:0] OBJ_HOFFSET=4'd0;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl;
reg  [ 2:0] hbl_sh, vbl_sh;
wire [11:0] scr0_pxl, scr1_pxl;
wire [ 8:0] obj_pxl;

assign LHBL    = hbl_sh[1];
assign LVBL    = vbl_sh[1];
assign vbl_irq = lvbl;

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender < VB_START;
    end
    // value for the next hdump
    lhbl <= mb ? (hdump >= 9'd31 && hdump < 9'd351) : (hdump < 9'd379 || hdump==HTOTAL);
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[1:0], lhbl };
    vbl_sh <= { vbl_sh[1:0], lvbl };
end

jtys16_scr #(.DX(10'h34)) u_scr0(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scrx       ( scr0x            ),
    .scry       ( scr0y            ),
    .vram_addr  ( vram0_video_addr ),
    .vram_dout  ( vram0_video_dout ),
    .rom_addr   ( scr0_addr        ),
    .rom_cs     ( scr0_cs          ),
    .rom_data   ( scr0_data        ),
    .rom_ok     ( scr0_ok          ),
    .pxl        ( scr0_pxl         )
);

jtys16_scr #(.DX(10'h38)) u_scr1(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scrx       ( scr1x            ),
    .scry       ( scr1y            ),
    .vram_addr  ( vram1_video_addr ),
    .vram_dout  ( vram1_video_dout ),
    .rom_addr   ( scr1_addr        ),
    .rom_cs     ( scr1_cs          ),
    .rom_data   ( scr1_data        ),
    .rom_ok     ( scr1_ok          ),
    .pxl        ( scr1_pxl         )
);

jtys16_obj u_obj(
    .rst        ( rst               ),
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .hs         ( HS                ),
    .hdump      ( hdump             ),
    .vrender    ( vrender           ),
    .hoffset    ( OBJ_HOFFSET ^ debug_bus[3:0] ),
    .ram_addr   ( objram_video_addr ),
    .ram_dout   ( objram_video_dout ),
    .rom_addr   ( obj_addr          ),
    .rom_cs     ( obj_cs            ),
    .rom_data   ( obj_data          ),
    .rom_ok     ( obj_ok            ),
    .pxl        ( obj_pxl           )
);

jtys16_colmix u_colmix(
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .gfx_en     ( gfx_en            ),
    .prio       ( prio              ),
    .scr0       ( scr0_pxl          ),
    .scr1       ( scr1_pxl          ),
    .obj        ( obj_pxl           ),
    .pal_addr   ( pal_video_addr    ),
    .pal_data   ( pal_video_dout    ),
    .red        ( red               ),
    .green      ( green             ),
    .blue       ( blue              )
);

endmodule
