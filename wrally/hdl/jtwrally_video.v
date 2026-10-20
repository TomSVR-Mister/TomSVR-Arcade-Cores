/*  This file is part of JTWRALLY.
    SPDX-License-Identifier: GPL-3.0-or-later
    World Rally video: two 64x32 maps of 16x16 tiles and 511 16x16 sprites with
    shadow/highlight pens (MAME wrally.cpp + gaelco_wrally_sprites.cpp).
    H and V counters use MAME's screen coordinates: visible x 8-375, y 16-247. */

module jtwrally_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input      [ 3:0] gfx_en,

    input      [15:0] scr0_y, scr0_x, scr1_y, scr1_x,

    output     [10:0] vram0_addr,
    input      [31:0] vram0_dout,
    output     [10:0] vram1_addr,
    input      [31:0] vram1_dout,

    output     [20:2] scr0_addr,
    input      [31:0] scr0_data,
    output            scr0_cs,
    input             scr0_ok,
    output     [20:2] scr1_addr,
    input      [31:0] scr1_data,
    output            scr1_cs,
    input             scr1_ok,

    output     [10:0] spr_addr,
    input      [15:0] spr_dout,
    output     [20:2] obj_addr,
    input      [31:0] obj_data,
    output            obj_cs,
    input             obj_ok,

    output     [12:0] pal_addr,
    input      [15:0] pal_dout,

    output     [ 3:0] red, green, blue,
    output            LHBL, LVBL, HS, VS
);

// pixels from the H counter to the screen (tile map = 8, colour mixer = 2)
parameter [8:0] HOFS  = 9'd2,
                OBJ_X = 9'd0,
                SCR_X = 9'd8;

wire [ 8:0] hdump, vdump;
wire [ 9:0] scr0_pxl, scr1_pxl;
wire [12:0] obj_pxl;
wire [ 9:0] sx0 = scr0_x[9:0] + 10'd4, sx1 = scr1_x[9:0];

jtframe_vtimer #(
    .HCNT_END ( 9'd511       ),
    .HB_START ( 9'd376+HOFS  ),
    .HB_END   ( 9'd8+HOFS    ),
    .HS_START ( 9'd424       ),
    .HS_END   ( 9'd460       ),
    .V_START  ( 9'd0         ),
    .VB_START ( 9'd247       ),
    .VB_END   ( 9'd15        ),
    .VS_START ( 9'd251       ),
    .VS_END   ( 9'd254       ),
    .VCNT_END ( 9'd259       )
) u_vtimer (
    .clk      ( clk     ),
    .pxl_cen  ( pxl_cen ),
    .vdump    ( vdump   ),
    .vrender  (         ),
    .vrender1 (         ),
    .H        ( hdump   ),
    .Hinit    (         ),
    .Vinit    (         ),
    .LHBL     ( LHBL    ),
    .LVBL     ( LVBL    ),
    .HS       ( HS      ),
    .VS       ( VS      )
);

// jtframe_scroll assumes a jumping H counter, so the offsets are added here
wire [9:0] heff0 = {1'b0, hdump + SCR_X} + sx0;
wire [8:0] veff0 = vdump + scr0_y[8:0];
jtframe_tilemap #(
    .SIZE       ( 16 ),
    .VA         ( 11 ),
    .CW         ( 14 ),
    .PW         ( 10 ),
    .MAP_HW     ( 10 ),
    .MAP_VW     (  9 ),
    .HDUMPW     ( 10 ),
    .VDUMPW     (  9 ),
    .FLIP_HDUMP (  0 ),
    .FLIP_VDUMP (  0 ),
    .FLIP_MSB   (  0 ),
    .HJUMP      (  1 )
) u_scr0 (
    .rst       ( rst                  ),
    .clk       ( clk                  ),
    .pxl_cen   ( pxl_cen              ),
    .vdump     ( veff0              ),
    .hdump     ( heff0              ),
    .blankn    ( 1'b1                 ),
    .flip      ( 1'b0                 ),
    .vram_addr ( vram0_addr           ),
    .code      ( vram0_dout[29:16]    ),
    .pal       ( vram0_dout[5:0]      ),
    .hflip     ( vram0_dout[7]        ),
    .vflip     ( vram0_dout[6]        ),
    .rom_addr  ( scr0_addr            ),
    .rom_data  ( scr0_data            ),
    .rom_cs    ( scr0_cs              ),
    .rom_ok    ( scr0_ok              ),
    .pxl       ( scr0_pxl             )
);

// jtframe_scroll assumes a jumping H counter, so the offsets are added here
wire [9:0] heff1 = {1'b0, hdump + SCR_X} + sx1;
wire [8:0] veff1 = vdump + scr1_y[8:0];
jtframe_tilemap #(
    .SIZE       ( 16 ),
    .VA         ( 11 ),
    .CW         ( 14 ),
    .PW         ( 10 ),
    .MAP_HW     ( 10 ),
    .MAP_VW     (  9 ),
    .HDUMPW     ( 10 ),
    .VDUMPW     (  9 ),
    .FLIP_HDUMP (  0 ),
    .FLIP_VDUMP (  0 ),
    .FLIP_MSB   (  0 ),
    .HJUMP      (  1 )
) u_scr1 (
    .rst       ( rst                  ),
    .clk       ( clk                  ),
    .pxl_cen   ( pxl_cen              ),
    .vdump     ( veff1              ),
    .hdump     ( heff1              ),
    .blankn    ( 1'b1                 ),
    .flip      ( 1'b0                 ),
    .vram_addr ( vram1_addr           ),
    .code      ( vram1_dout[29:16]    ),
    .pal       ( vram1_dout[5:0]      ),
    .hflip     ( vram1_dout[7]        ),
    .vflip     ( vram1_dout[6]        ),
    .rom_addr  ( scr1_addr            ),
    .rom_data  ( scr1_data            ),
    .rom_cs    ( scr1_cs              ),
    .rom_ok    ( scr1_ok              ),
    .pxl       ( scr1_pxl             )
);

jtwrally_obj u_obj(
    .rst      ( rst            ),
    .clk      ( clk            ),
    .pxl_cen  ( pxl_cen        ),
    .hs       ( HS             ),
    .vdump    ( vdump          ),
    .hdump    ( hdump + OBJ_X  ),
    .spr_addr ( spr_addr       ),
    .spr_dout ( spr_dout       ),
    .rom_addr ( obj_addr       ),
    .rom_data ( obj_data       ),
    .rom_cs   ( obj_cs         ),
    .rom_ok   ( obj_ok         ),
    .pxl      ( obj_pxl        )
);

jtwrally_colmix u_colmix(
    .clk      ( clk            ),
    .pxl_cen  ( pxl_cen        ),
    .gfx_en   ( gfx_en         ),
    .scr0     ( scr0_pxl       ),
    .scr1     ( scr1_pxl       ),
    .obj      ( obj_pxl        ),
    .pal_addr ( pal_addr       ),
    .pal_dout ( pal_dout       ),
    .red      ( red            ),
    .green    ( green          ),
    .blue     ( blue           )
);

endmodule
