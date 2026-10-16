/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Splash! video: 8 MHz pixel clock, 512x269 total (58 Hz), MAME visible area X 16-383, Y 16-255.
 * hdump/vdump are MAME screen coordinates. Pixel layer: 512x256, screen X = layer X - 9. */

module jtsplash_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 7:0] debug_bus,
    input              lo_attr,
    input       [15:0] scr0, scr1,

    output      [12:1] vram_video_addr,
    input       [15:0] vram_video_dout,
    output      [12:1] vramb_video_addr,
    input       [15:0] vramb_video_dout,
    output      [11:1] objram_video_addr,
    input       [15:0] objram_video_dout,
    output      [11:1] pal_video_addr,
    input       [15:0] pal_video_dout,
    output      [17:1] pix_video_addr,
    input       [ 7:0] pix_video_dout,

    output      [18:2] tm0_addr,
    output             tm0_cs,
    input       [31:0] tm0_data,
    input              tm0_ok,
    output      [18:2] tm1_addr,
    output             tm1_cs,
    input       [31:0] tm1_data,
    input              tm1_ok,
    output      [18:2] obj_addr,
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
localparam [8:0] VTOTAL=9'd268, VB_END=9'd16, VB_START=9'd256, VS_START=9'd260, VS_END=9'd263;
localparam [3:0] OBJ_HOFFSET=4'd0;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl;
reg  [ 2:0] hbl_sh, vbl_sh;
wire [ 7:0] tm0_pxl, tm1_pxl, obj_pxl;
wire [ 8:0] pix_x = hdump + 9'd9;

assign LHBL    = hbl_sh[1];
assign LVBL    = vbl_sh[1];
assign vbl_irq = lvbl;
assign pix_video_addr = { vdump[7:0], pix_x };

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    // value for the next hdump
    lhbl <= hdump >= 9'd15 && hdump < 9'd383;
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[1:0], lhbl };
    vbl_sh <= { vbl_sh[1:0], lvbl };
end

jtsplash_tile #(.B16(0)) u_tm0(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scr        ( scr0             ),
    .vram_addr  ( vram_video_addr  ),
    .vram_dout  ( vram_video_dout  ),
    .rom_addr   ( tm0_addr         ),
    .rom_cs     ( tm0_cs           ),
    .rom_data   ( tm0_data         ),
    .rom_ok     ( tm0_ok           ),
    .pxl        ( tm0_pxl          )
);

jtsplash_tile #(.B16(1)) u_tm1(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scr        ( scr1             ),
    .vram_addr  ( vramb_video_addr ),
    .vram_dout  ( vramb_video_dout ),
    .rom_addr   ( tm1_addr         ),
    .rom_cs     ( tm1_cs           ),
    .rom_data   ( tm1_data         ),
    .rom_ok     ( tm1_ok           ),
    .pxl        ( tm1_pxl          )
);

jtsplash_obj u_obj(
    .rst        ( rst               ),
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .hs         ( HS                ),
    .lo_attr    ( lo_attr           ),
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

jtsplash_colmix u_colmix(
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .gfx_en     ( gfx_en            ),
    .tm0        ( tm0_pxl           ),
    .tm1        ( tm1_pxl           ),
    .obj        ( obj_pxl           ),
    .pix        ( pix_video_dout    ),
    .pal_addr   ( pal_video_addr    ),
    .pal_data   ( pal_video_dout    ),
    .red        ( red               ),
    .green      ( green             ),
    .blue       ( blue              )
);

endmodule
