/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * ESD 16-bit video: 8 MHz pixel clock, 512x260 total (60 Hz). Visible 320x240 = MAME's (0, 8) - (319, 247).
 * Palette: 2048 words xRGB_555.
 *   Tilemap 0 (opaque): (colour register & 1) * 256 + pen.   Tilemap 1: pen, 0 transparent.
 *   Sprites: 0x200 + (colour & 7) * 32 + pen (5 bpp), pen 0 transparent.
 *   Jumping Pop: tilemap 0 at 0x200, tilemap 1 at 0x100, sprites colour * 16 + pen (4 bpp).
 * Map pixel = screen pixel + scroll + (0x5e, 8) for tilemap 0 and (0x60, 8) for tilemap 1 (MAME's scrolldx, y from line 8).
 * Order: tilemap 0, sprites with the priority bit, tilemap 1, other sprites. */

module jtesd_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input              jp,
    input              soff,
    input       [ 1:0] osize,
    input              t2m,
    input       [ 1:0] lsize,
    input       [ 1:0] col0,
    input       [ 9:0] scr0x, scr0y, scr1x, scr1y,

    output      [13:1] vram0_video_addr,
    input       [15:0] vram0_video_dout,
    output      [13:1] vram1_video_addr,
    input       [15:0] vram1_video_dout,
    output      [10:1] objram_video_addr,
    input       [15:0] objram_video_dout,
    output reg  [11:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [21:2] t0_addr,
    output             t0_cs,
    input       [31:0] t0_data,
    input              t0_ok,
    output      [21:2] t1_addr,
    output             t1_cs,
    input       [31:0] t1_data,
    input              t1_ok,
    output      [21:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,
    output      [19:0] ob5_addr,
    output             ob5_cs,
    input       [ 7:0] ob5_data,
    input              ob5_ok,

    output             vbl_irq,     // low during vblank (undelayed)
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd511, HS_START=9'd400, HS_END=9'd432;
localparam [8:0] VTOTAL=9'd259, VB_START=9'd240, VS_START=9'd246, VS_END=9'd249;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl, odd;
reg  [ 3:0] hbl_sh, vbl_sh;
wire [ 7:0] tm0_q, tm1_q;
wire [10:0] obj_pxl;
reg  [ 7:0] tm0, tm1;
reg  [10:0] idx;
wire [ 9:0] sx0 = scr0x + 10'h5e, sy0 = scr0y + 10'd8, sx1 = scr1x + 10'h60, sy1 = scr1y + 10'd8;

assign LHBL    = hbl_sh[2];
assign LVBL    = vbl_sh[2];
assign vbl_irq = lvbl;

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender < VB_START;
        if( vrender==VTOTAL ) odd <= ~odd;
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

jtesd_tile u_tm0(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .big        ( lsize[0]         ),
    .t2m        ( t2m              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scrx       ( sx0              ),
    .scry       ( sy0              ),
    .vram_addr  ( vram0_video_addr ),
    .vram_dout  ( vram0_video_dout ),
    .rom_addr   ( t0_addr          ),
    .rom_cs     ( t0_cs            ),
    .rom_data   ( t0_data          ),
    .rom_ok     ( t0_ok            ),
    .pxl        ( tm0_q            )
);

jtesd_tile u_tm1(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .big        ( lsize[1]         ),
    .t2m        ( t2m              ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scrx       ( sx1              ),
    .scry       ( sy1              ),
    .vram_addr  ( vram1_video_addr ),
    .vram_dout  ( vram1_video_dout ),
    .rom_addr   ( t1_addr          ),
    .rom_cs     ( t1_cs            ),
    .rom_data   ( t1_data          ),
    .rom_ok     ( t1_ok            ),
    .pxl        ( tm1_q            )
);

jtesd_obj u_obj(
    .rst        ( rst               ),
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .jp         ( jp                ),
    .soff       ( soff              ),
    .osize      ( osize             ),
    .odd        ( odd               ),
    .hdump      ( hdump             ),
    .vrender    ( vrender           ),
    .vdump      ( vdump             ),
    .ram_addr   ( objram_video_addr ),
    .ram_dout   ( objram_video_dout ),
    .rom_addr   ( obj_addr          ),
    .rom_cs     ( obj_cs            ),
    .rom_data   ( obj_data          ),
    .rom_ok     ( obj_ok            ),
    .p5_addr    ( ob5_addr          ),
    .p5_cs      ( ob5_cs            ),
    .p5_data    ( ob5_data          ),
    .p5_ok      ( ob5_ok            ),
    .pxl        ( obj_pxl           )
);

// obj_pxl = { priority, colour[4:0], pen[4:0] }
wire        t1_on = gfx_en[1] && tm1!=0;
wire        s_on  = gfx_en[3] && obj_pxl[4:0]!=0;
wire [10:0] t0_i  = jp ? { 3'b010, tm0 } : { 2'b00, col0[0], tm0 };
wire [10:0] t1_i  = jp ? { 3'b001, tm1 } : { 3'b000, tm1 };
wire [10:0] s_i   = jp ? { 2'b00, obj_pxl[9:5], obj_pxl[3:0] } : { 3'b010, obj_pxl[7:5], obj_pxl[4:0] };

always @* begin
    idx = gfx_en[0] ? t0_i : 11'd0;
    if( s_on && obj_pxl[10] ) idx = s_i;
    if( t1_on ) idx = t1_i;
    if( s_on && !obj_pxl[10] ) idx = s_i;
end

always @(posedge clk) if( pxl_cen ) begin
    tm0  <= tm0_q;
    tm1  <= tm1_q;
    pal_video_addr <= idx;
    red      <= pal_video_dout[14:10];
    green    <= pal_video_dout[ 9: 5];
    blue     <= pal_video_dout[ 4: 0];
end

endmodule
