/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gals Pinball video: 512x224 visible (MAME rows 16-239), 704x262 total */

module jtgalpin_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 7:0] debug_bus,

    output      [11:1] vidram_video_addr,
    input       [15:0] vidram_video_dout,
    output      [11:1] colram_video_addr,
    input       [15:0] colram_video_dout,
    output      [11:1] objram_video_addr,
    input       [15:0] objram_video_dout,
    output      [17:1] bg_video_addr,
    input       [15:0] bg_video_dout,
    output      [10:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output             fgt_cs,
    output      [18:2] fgt_addr,
    input       [31:0] fgt_data,
    input              fgt_ok,
    output             obj_cs,
    output      [17:2] obj_addr,
    input       [31:0] obj_data,
    input              obj_ok,

    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output      [ 4:0] red,
    output      [ 4:0] green,
    output      [ 4:0] blue
);

localparam [9:0] HTOTAL=10'd703, HS_START=10'd576, HS_END=10'd640;
localparam [8:0] VTOTAL=9'd261,  VB_END=9'd16, VB_START=9'd240, VS_START=9'd244, VS_END=9'd247;
localparam [3:0] OBJ_HOFFSET=4'd0;

reg  [ 9:0] hdump=0;
reg  [ 8:0] vdump=0, vrender=1;
reg         lhbl, lvbl, frame=0, lvbl_l;
reg  [ 2:0] hbl_sh, vbl_sh;
wire [ 7:0] fg_pxl;
wire [ 8:0] obj_pxl;

assign bg_video_addr = { vdump[7:0], hdump[8:0] };
assign LHBL = hbl_sh[1];
assign LVBL = vbl_sh[1];

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 10'd0 : hdump+10'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
    end
    lhbl <= hdump < 10'd511 || hdump==HTOTAL;
    if( hdump==HTOTAL ) lvbl <= vrender >= VB_END && vrender < VB_START;
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    // two pixels of latency in the colour mixer
    hbl_sh <= { hbl_sh[1:0], lhbl };
    vbl_sh <= { vbl_sh[1:0], lvbl };
    lvbl_l <= lvbl;
    if( !lvbl && lvbl_l ) frame <= ~frame;
end

jtgalpin_fg u_fg(
    .rst        ( rst               ),
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .hs         ( HS                ),
    .vrender    ( vrender           ),
    .vdump      ( vdump             ),
    .hdump      ( hdump             ),
    .vidram_addr( vidram_video_addr ),
    .vidram_dout( vidram_video_dout ),
    .colram_addr( colram_video_addr ),
    .colram_dout( colram_video_dout ),
    .rom_addr   ( fgt_addr          ),
    .rom_cs     ( fgt_cs            ),
    .rom_data   ( fgt_data          ),
    .rom_ok     ( fgt_ok            ),
    .pxl        ( fg_pxl            )
);

jtgalpin_obj u_obj(
    .rst        ( rst               ),
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .flip       ( 1'b0              ),
    .lvbl       ( lvbl              ),
    .hs         ( HS                ),
    .frame      ( frame             ),
    .hdump      ( hdump             ),
    .vrender    ( vrender           ),
    .yoffset    ( 9'h1fe            ),   // -2 lines (measured against MAME)
    .hoffset    ( OBJ_HOFFSET ^ debug_bus[3:0] ),
    .ram_addr   ( objram_video_addr ),
    .ram_dout   ( objram_video_dout ),
    .rom_cs     ( obj_cs            ),
    .rom_addr   ( obj_addr          ),
    .rom_data   ( obj_data          ),
    .rom_ok     ( obj_ok            ),
    .pxl        ( obj_pxl           )
);

jtgalpin_colmix u_colmix(
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .gfx_en     ( gfx_en            ),
    .bg_data    ( bg_video_dout     ),
    .fg_pxl     ( fg_pxl            ),
    .obj_pxl    ( obj_pxl           ),
    .pal_addr   ( pal_video_addr    ),
    .pal_data   ( pal_video_dout    ),
    .red        ( red               ),
    .green      ( green             ),
    .blue       ( blue              )
);

endmodule
