/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * VISYS video: 6 MHz pixel clock, 400x268 total (56 Hz), MAME visible area 320x240 at (0,0).
 * Palette: 1024 words xBGR_555. Colours: bg 0, sprites 1, mid 2, fg 3 (256 pens each), pen 0 transparent.
 * Layer order (bottom to top) over black: Mad Donna mid, fg, bg, sprites; Komo Como (order=1) bg, mid, fg, sprites. */

module jtmadd_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input              order,
    input       [15:0] scroll1,

    output      [11:1] vbg_video_addr,
    input       [15:0] vbg_video_dout,
    output      [11:1] vmid_video_addr,
    input       [15:0] vmid_video_dout,
    output      [11:1] vfg_video_addr,
    input       [15:0] vfg_video_dout,
    output      [11:1] objram_video_addr,
    input       [15:0] objram_video_dout,
    output      [10:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [21:2] bgt_addr,
    output             bgt_cs,
    input       [31:0] bgt_data,
    input              bgt_ok,
    output      [21:2] mgt_addr,
    output             mgt_cs,
    input       [31:0] mgt_data,
    input              mgt_ok,
    output      [21:2] fgt_addr,
    output             fgt_cs,
    input       [31:0] fgt_data,
    input              fgt_ok,
    output      [21:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,

    output             vbl_irq,     // low during vblank (undelayed)
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd399, HS_START=9'd340, HS_END=9'd372;
localparam [8:0] VTOTAL=9'd267, VB_START=9'd240, VS_START=9'd248, VS_END=9'd251;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl;
reg  [ 3:0] hbl_sh, vbl_sh;
wire [ 7:0] bg_q, mid_q, fg_q, obj_pxl;
reg  [ 7:0] bg, mid, fg;
reg  [ 9:0] idx;
reg         blank, black;
reg  [10:1] pal_addr;

assign LHBL    = hbl_sh[2];
assign LVBL    = vbl_sh[2];
assign vbl_irq = lvbl;
assign pal_video_addr = pal_addr;

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender < VB_START;
    end
    lhbl <= hdump==HTOTAL || hdump < 9'd319;   // value for the next hdump
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[2:0], lhbl };
    vbl_sh <= { vbl_sh[2:0], lvbl };
end

jtmadd_tile u_bg(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scr        ( 9'd0 ),
    .vram_addr  ( vbg_video_addr ),
    .vram_dout  ( vbg_video_dout ),
    .rom_addr   ( bgt_addr        ),
    .rom_cs     ( bgt_cs          ),
    .rom_data   ( bgt_data        ),
    .rom_ok     ( bgt_ok          ),
    .pxl        ( bg_q            )
);

jtmadd_tile u_mid(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scr        ( scroll1[8:0] ),
    .vram_addr  ( vmid_video_addr ),
    .vram_dout  ( vmid_video_dout ),
    .rom_addr   ( mgt_addr        ),
    .rom_cs     ( mgt_cs          ),
    .rom_data   ( mgt_data        ),
    .rom_ok     ( mgt_ok          ),
    .pxl        ( mid_q            )
);

jtmadd_tile u_fg(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scr        ( 9'd0 ),
    .vram_addr  ( vfg_video_addr ),
    .vram_dout  ( vfg_video_dout ),
    .rom_addr   ( fgt_addr        ),
    .rom_cs     ( fgt_cs          ),
    .rom_data   ( fgt_data        ),
    .rom_ok     ( fgt_ok          ),
    .pxl        ( fg_q            )
);

jtmadd_obj u_obj(
    .rst        ( rst               ),
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .hdump      ( hdump             ),
    .vrender    ( vrender           ),
    .vdump      ( vdump             ),
    .ram_addr   ( objram_video_addr ),
    .ram_dout   ( objram_video_dout ),
    .rom_addr   ( obj_addr          ),
    .rom_cs     ( obj_cs            ),
    .rom_data   ( obj_data          ),
    .rom_ok     ( obj_ok            ),
    .pxl        ( obj_pxl           )
);

always @* begin
    idx   = 0;
    blank = 1;
    if( !order ) begin
        if( gfx_en[1] && mid!=0 ) begin idx = { 2'd2, mid }; blank = 0; end
        if( gfx_en[2] && fg !=0 ) begin idx = { 2'd3, fg  }; blank = 0; end
        if( gfx_en[0] && bg !=0 ) begin idx = { 2'd0, bg  }; blank = 0; end
    end else begin
        if( gfx_en[0] && bg !=0 ) begin idx = { 2'd0, bg  }; blank = 0; end
        if( gfx_en[1] && mid!=0 ) begin idx = { 2'd2, mid }; blank = 0; end
        if( gfx_en[2] && fg !=0 ) begin idx = { 2'd3, fg  }; blank = 0; end
    end
    if( gfx_en[3] && obj_pxl!=0 ) begin idx = { 2'd1, obj_pxl }; blank = 0; end
end

always @(posedge clk) if( pxl_cen ) begin
    bg       <= bg_q;
    mid      <= mid_q;
    fg       <= fg_q;
    pal_addr <= idx;
    black    <= blank;
    red      <= black ? 5'd0 : pal_video_dout[ 4: 0];
    green    <= black ? 5'd0 : pal_video_dout[ 9: 5];
    blue     <= black ? 5'd0 : pal_video_dout[14:10];
end

endmodule
