/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Pipe Dream / Hatris video (MAME vsystem/pipedrm.cpp, fromance_v.cpp, vsystem_spr2.cpp):
 *   C7-01 GGA timing (jtpipedrm_gga, from Andrea Bogazzi's jtpspike), 14.318181/2 MHz pixel clock: the games
 *   program 352x240 visible on 456x256, 61.31 Hz.
 *   Two fromance tile layers (jtpipedrm_scr): layer 0 (gfx1) opaque, layer 1 (gfx2) transparent on pen 15.
 *   pipedrm only: VS8904/8905 sprites (jtpipedrm_obj/objscan, from jtpspike), no tile lookup RAM, drawn above both
 *   layers, pri 0 pass first then pri 1 (vsystem_spr2 pritype 3, set_offsets -13,-6), never flipped.
 *   Palette: xRGB-555, 2048 entries, tiles at 0 (colour * 16), sprites at 1024. On pipedrm entries 600-7ff are the
 *   sprite RAM and stay black. Scroll: pipedrm uses Y only (bg = scroll register 1, fg = 0), hatris X and Y
 *   (bg = 0, fg = 1). */
module jtpipedrm_video(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               hatris,

    input               gga_we,
    input               gga_addr,
    input      [ 7:0]   gga_din,
    output              crtc_irq_en,

    input               flip,
    input      [ 8:0]   scrx0, scry0, scrx1, scry1,

    output     [13:0]   v0_addr,
    input      [ 7:0]   v0_dout,
    output     [13:0]   v1_addr,
    input      [ 7:0]   v1_dout,
    output     [10:0]   pl_addr,
    input      [ 7:0]   pl_dout,
    output     [10:0]   ph_addr,
    input      [ 7:0]   ph_dout,
    output     [ 8:0]   ol_addr,
    input      [ 7:0]   ol_dout,
    output     [ 8:0]   oh_addr,
    input      [ 7:0]   oh_dout,

    output     [19:2]   scr0_addr,
    output              scr0_cs,
    input      [31:0]   scr0_data,
    input               scr0_ok,
    output     [19:2]   scr1_addr,
    output              scr1_cs,
    input      [31:0]   scr1_data,
    input               scr1_ok,
    output     [18:2]   obj_addr,
    output              obj_cs,
    input      [31:0]   obj_data,
    input               obj_ok,

    input      [ 3:0]   gfx_en,
    output reg          LHBL, LVBL, HS, VS,
    output reg [ 4:0]   red, green, blue
);

wire [ 8:0] h_last, hsize, vsize, vdump, vrender, H;
wire        lhbl, lvbl, hs, vs;
wire [10:0] s0_pxl, s1_pxl, obj_pxl;
wire [ 9:1] objr_addr;
wire [14:0] objl_addr;
reg  [14:0] objl_q;
wire [21:2] obj_raw;
wire [ 8:0] hdump_obj;
reg  [10:0] pxl;
wire [15:0] cm0 = hatris ? 16'h7fff : 16'hffff,    // gfx1 0x80000 / 0x100000 bytes, 16 per tile
            cm1 = hatris ? 16'h3fff : 16'hffff;    // gfx2 0x40000 / 0x100000
wire        s1_op  = ~&s1_pxl[3:0] & gfx_en[1];
wire        obj_op = ~&obj_pxl[3:0] & gfx_en[2] & ~hatris;
// sprite gfx (splayout): in each 32-bit word, pixels 0-3 come from bytes 1 and 3, pixels 4-7 from bytes 0 and 2,
// low nibble first. jtframe_draw wants the leftmost pixel in the lowest nibble
wire [31:0] obj_sorted = { obj_data[23:16], obj_data[7:0], obj_data[31:24], obj_data[15:8] };

localparam [8:0] P_OBJ = 9'd1;     // sprite line buffer readout

assign ol_addr   = objr_addr;
assign oh_addr   = objr_addr;
assign obj_addr  = obj_raw[18:2];
assign hdump_obj = H >= (h_last-P_OBJ+9'd1) ? H+P_OBJ-(h_last+9'd1) : H+P_OBJ;
assign pl_addr   = pxl;
assign ph_addr   = pxl;

// MAME pipedrm: "there seems to be no logical mapping for the X scroll register", so X scroll stays 0
wire [8:0] bg_sx = hatris ? scrx0 : 9'd0,
           bg_sy = hatris ? scry0 : scry1,
           fg_sx = hatris ? scrx1 : 9'd0,
           fg_sy = hatris ? scry1 : scry0;

// no lookup RAM on pipedrm: the map word is the tile code. Registered like a BRAM read, which objscan expects
always @(posedge clk) objl_q <= objl_addr;

always @* begin
    pxl = !gfx_en[0] ? 11'd0 : s0_pxl;
    if( s1_op  ) pxl = s1_pxl;
    if( obj_op ) pxl = { 3'b100, obj_pxl[7:0] };
end

jtpipedrm_gga u_gga(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .cs         ( gga_we    ),
    .we         ( gga_we    ),
    .addr       ( gga_addr  ),
    .din        ( gga_din   ),
    .h_last     ( h_last    ),
    .hsize      ( hsize     ),
    .vsize      ( vsize     ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   (           ),
    .H          ( H         ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( lhbl      ),
    .LVBL       ( lvbl      ),
    .HS         ( hs        ),
    .VS         ( vs        ),
    .reg0b_wr   ( crtc_irq_en )
);

jtpipedrm_scr u_bg(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .hs         ( hs        ),
    .flip       ( flip      ),
    .vrender    ( vrender   ),
    .hdump      ( H         ),
    .scrx       ( bg_sx     ),
    .scry       ( bg_sy     ),
    .cmask      ( cm0       ),
    .vram_addr  ( v0_addr   ),
    .vram_dout  ( v0_dout   ),
    .rom_addr   ( scr0_addr ),
    .rom_cs     ( scr0_cs   ),
    .rom_data   ( scr0_data ),
    .rom_ok     ( scr0_ok   ),
    .pxl        ( s0_pxl    )
);

jtpipedrm_scr u_fg(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .hs         ( hs        ),
    .flip       ( flip      ),
    .vrender    ( vrender   ),
    .hdump      ( H         ),
    .scrx       ( fg_sx     ),
    .scry       ( fg_sy     ),
    .cmask      ( cm1       ),
    .vram_addr  ( v1_addr   ),
    .vram_dout  ( v1_dout   ),
    .rom_addr   ( scr1_addr ),
    .rom_cs     ( scr1_cs   ),
    .rom_data   ( scr1_data ),
    .rom_ok     ( scr1_ok   ),
    .pxl        ( s1_pxl    )
);

jtpipedrm_obj u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .hs         ( hs        ),
    .en         ( ~hatris   ),
    .flip       ( 1'b0      ),
    .hdump      ( hdump_obj ),
    .vrender    ( vrender   ),
    .hsize      ( hsize     ),
    .vsize      ( vsize     ),
    .xorg       ( 9'd0      ),
    .xflip      ( 9'd0      ),
    .yflip      ( 9'd0      ),
    .xoffs      ( -9'd13    ),
    .yoffs      ( -9'd6     ),
    .objbank    ( 2'd0      ),
    .objr_addr  ( objr_addr ),
    .objr_dout  ( { oh_dout, ol_dout } ),
    .wide_lut   ( 1'b0      ),
    .cmask      ( 15'h0fff  ),   // gfx3 0x80000 / 128
    .objl_addr  ( objl_addr ),
    .objl_dout  ( { 1'b0, objl_q } ),
    .rom_addr   ( obj_raw   ),
    .rom_cs     ( obj_cs    ),
    .rom_data   ( obj_sorted),
    .rom_ok     ( obj_ok    ),
    .pxl        ( obj_pxl   )
);

// colour lookup: the palette BRAM answers one clock after pxl; output and blanking are both delayed one pixel
// so they stay in step with H. Sync keeps running in reset (ROM download) with a black picture, so the MiSTer
// scaler does not show stale frame buffer contents
always @(posedge clk) begin
    if( pxl_cen ) begin
        { LHBL, LVBL, HS, VS } <= { lhbl, lvbl, hs, vs };
        { red, green, blue }   <= rst || !lhbl || !lvbl || (!hatris && pxl[10:9]==2'b11) ? 15'd0 :
                                  { ph_dout[6:0], pl_dout };
    end
end

endmodule
