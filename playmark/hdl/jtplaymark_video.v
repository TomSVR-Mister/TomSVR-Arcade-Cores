/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Playmark Big Twin / Excelsior video (MAME playmark_v.cpp screen_update_bigtwin / screen_update_excelsr).
 *   8 MHz pixel clock, 512x270 (57.9 Hz). Visible 320x240 = MAME rows 16-255.
 *   Layers: fg 16x16 tile map (opaque, palette 000), 512x512 bitmap (palette 100 | pixel, 0 transparent),
 *   tx tile map (Big Twin 8x8 64x32, Excelsior 16x16 32x32, palette 080, pen 0 transparent), sprites (palette 200).
 *   Big Twin: fg < bitmap < sprites < tx.   Excelsior: fg < bitmap < tx, sprites above all (pri 0), only over fg
 *   (pri 1) or under tx only (pri 2).
 *   Scroll registers: 0 tx x (+2), 1 tx y, 2 bitmap x, 3 bitmap y (bit 9 enable, bit 10 full size), 4 fg x (+6), 5 fg y.
 *   Half-size bitmap: every other pixel of every other row (MAME draw_bitmap, shift 1).
 *   Palette: 1024 words RRRRGGGGBBBBRGBx.
 * hm: Hot Mind (MAME screen_update_hrdtimes, video_start hotmind): visible rows 16-239, black unless scroll register 6
 *   bit 0 is set. bg 16x16 (opaque, palette 000) < fg 16x16 (pen 0 transparent, palette 080) < sprites < tx 8x8 64x64
 *   (palette 100). Sprites with priority 1 go under the fg pixels. Scroll: 0/1 tx, 2/3 fg, 4/5 bg, x - 14 (scrolldx). */

module jtplaymark_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              exc,
    input              hm,
    input              ven,
    input       [ 3:0] gfx_en,

    input       [15:0] scr0, scr1, scr2, scr3, scr4, scr5,

    // CPU writes
    input       [21:1] cpu_addr,
    input       [15:0] cpu_dout,
    input       [ 1:0] oram_we,
    input              bmp_wr,      // bitmap low byte write

    output      [11:1] fgram_video_addr,
    input       [15:0] fgram_video_dout,
    output      [12:1] txram_video_addr,
    input       [15:0] txram_video_dout,
    output      [10:1] bgram_video_addr,
    input       [15:0] bgram_video_dout,
    output reg  [10:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [20:2] fg_addr,
    output             fg_cs,
    input       [31:0] fg_data,
    input              fg_ok,
    output      [20:2] tx_addr,
    output             tx_cs,
    input       [31:0] tx_data,
    input              tx_ok,
    output      [20:2] bg_addr,
    output             bg_cs,
    input       [31:0] bg_data,
    input              bg_ok,
    output      [20:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,

    output             lvbl_irq,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd511, HS_START=9'd400, HS_END=9'd440;
localparam [8:0] VTOTAL=9'd269, VB_END=9'd16, VB_START=9'd256, VS_START=9'd262, VS_END=9'd265;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl, lvbl_i, hs_l;
reg  [ 3:0] hbl_sh, vbl_sh;

assign LHBL     = hbl_sh[2];
assign LVBL     = vbl_sh[1];
assign lvbl_irq = lvbl_i;      // Hot Mind: vblank interrupt after row 239, rows 240-255 shown black
wire   hs_start = pxl_cen && hdump==0 && !hs_l;

always @(posedge clk) if( pxl_cen ) hs_l <= hdump==0;

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
        lvbl_i  <= vrender >= VB_END && vrender < (hm ? 9'd240 : VB_START);
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
end

// ---------------- tile maps ----------------
wire [ 6:0] fg_pxl, tx_pxl, bg_pxl;
wire [12:1] fg_vaddr, bg_vaddr;

assign fgram_video_addr = fg_vaddr[11:1];
assign bgram_video_addr = bg_vaddr[10:1];

jtplaymark_tile u_fg(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .t16        ( 1'b1          ),
    .c14        ( exc           ),
    .one        ( hm            ),
    .hsel       ( 1'b1          ),
    .hdump      ( hdump         ),
    .hs_start   ( hs_start      ),
    .vrender    ( vrender       ),
    .vdump      ( vdump         ),
    .scrx       ( hm ? scr2[8:0] - 9'd14 : scr4[8:0] + 9'd6 ),
    .scry       ( hm ? scr3[8:0] : scr5[8:0] ),
    .vram_addr  ( fg_vaddr      ),
    .vram_dout  ( fgram_video_dout ),
    .rom_addr   ( fg_addr       ),
    .rom_cs     ( fg_cs         ),
    .rom_data   ( fg_data       ),
    .rom_ok     ( fg_ok         ),
    .pxl        ( fg_pxl        )
);

jtplaymark_tile u_tx(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .t16        ( exc && !hm    ),
    .c14        ( exc           ),
    .one        ( hm            ),
    .hsel       ( 1'b0          ),
    .hdump      ( hdump         ),
    .hs_start   ( hs_start      ),
    .vrender    ( vrender       ),
    .vdump      ( vdump         ),
    .scrx       ( hm ? scr0[8:0] - 9'd14 : scr0[8:0] + 9'd2 ),
    .scry       ( scr1[8:0]     ),
    .vram_addr  ( txram_video_addr ),
    .vram_dout  ( txram_video_dout ),
    .rom_addr   ( tx_addr       ),
    .rom_cs     ( tx_cs         ),
    .rom_data   ( tx_data       ),
    .rom_ok     ( tx_ok         ),
    .pxl        ( tx_pxl        )
);

jtplaymark_tile u_bg(       // Hot Mind only
    .rst        ( rst           ),
    .clk        ( clk           ),
    .t16        ( 1'b1          ),
    .c14        ( 1'b0          ),
    .one        ( 1'b1          ),
    .hsel       ( 1'b0          ),
    .hdump      ( hdump         ),
    .hs_start   ( hs_start & hm ),
    .vrender    ( vrender       ),
    .vdump      ( vdump         ),
    .scrx       ( scr4[8:0] - 9'd14 ),
    .scry       ( scr5[8:0]     ),
    .vram_addr  ( bg_vaddr      ),
    .vram_dout  ( bgram_video_dout ),
    .rom_addr   ( bg_addr       ),
    .rom_cs     ( bg_cs         ),
    .rom_data   ( bg_data       ),
    .rom_ok     ( bg_ok         ),
    .pxl        ( bg_pxl        )
);

// ---------------- sprites ----------------
wire [10:0] obj_pxl;

jtplaymark_obj u_obj(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .exc        ( exc | hm      ),
    .hm         ( hm            ),
    .hdump      ( hdump         ),
    .hs_start   ( hs_start      ),
    .vrender    ( vrender       ),
    .vdump      ( vdump         ),
    .cpu_addr   ( cpu_addr[11:1]),
    .cpu_dout   ( cpu_dout      ),
    .oram_we    ( oram_we       ),
    .rom_addr   ( obj_addr      ),
    .rom_cs     ( obj_cs        ),
    .rom_data   ( obj_data      ),
    .rom_ok     ( obj_ok        ),
    .pxl        ( obj_pxl       )
);

// ---------------- bitmap ----------------
// video copy of the pixel bytes (the CPU reads its full words from SDRAM)
wire        bm_en   = scr3[9];
wire        bm_full = scr3[10];
wire [ 8:0] bx = hdump + (exc ? scr2[8:0] : scr2[8:0] + 9'd4);
wire [ 8:0] by = vdump + (exc ? scr3[8:0] - 9'd2 : scr3[8:0]);
wire        bm_out = !bm_full && (bx[8] || by[8]);
wire [17:0] bm_rd  = bm_full ? { by, bx } : { by[7:0], 1'b0, bx[7:0], 1'b0 };
wire [ 7:0] bm_q;

jtframe_dual_ram #(.DW(8),.AW(18)) u_bitmap(
    .clk0   ( clk           ),
    .data0  ( cpu_dout[7:0] ),
    .addr0  ( cpu_addr[18:1]),
    .we0    ( bmp_wr        ),
    .q0     (               ),
    .clk1   ( clk           ),
    .data1  ( 8'd0          ),
    .addr1  ( bm_rd         ),
    .we1    ( 1'b0          ),
    .q1     ( bm_q          )
);

// ---------------- mixer ----------------
reg  [ 6:0] fg_l, tx_l, bg_l;
reg  [ 7:0] bm_l;
reg  [10:0] obj_l;
reg         bm_ok, blank;

wire        tx_op  = tx_l[3:0] != 0 && gfx_en[1];
wire        bm_op  = bm_ok && bm_l != 0 && gfx_en[2];
wire        obj_op = obj_l[3:0] != 0 && gfx_en[3];
wire        obj_vis = !exc || obj_l[10:9]==0 || (obj_l[10:9]==1 ? !bm_op && !tx_op : !tx_op);
wire        fg_op  = fg_l[3:0] != 0 && gfx_en[0];
wire        hobj   = obj_op && (obj_l[10:9]!=1 || !fg_op);
wire [ 9:0] base   = { 3'd0, gfx_en[0] ? fg_l : 7'd0 };

always @(posedge clk) if( pxl_cen ) begin
    fg_l  <= fg_pxl;
    tx_l  <= tx_pxl;
    bm_l  <= bm_q;
    bm_ok <= bm_en && !bm_out;
    obj_l <= obj_pxl;
    bg_l  <= bg_pxl;
    blank <= hm && (!ven || vdump >= 9'd240);
    if( hm )
        pal_video_addr <= tx_op  ? { 3'b010, tx_l } :
                          hobj   ? { 1'b1, obj_l[8:0] } :
                          fg_op  ? { 3'b001, fg_l } :
                          { 3'b000, gfx_en[2] ? bg_l : 7'd0 };
    else if( exc )
        pal_video_addr <= obj_op && obj_vis ? { 2'b10, obj_l[7:0] } :
                          tx_op ? { 3'b001, tx_l } :
                          bm_op ? { 2'b01, bm_l } : base;
    else
        pal_video_addr <= tx_op  ? { 3'b001, tx_l } :
                          obj_op ? { 2'b10, obj_l[7:0] } :
                          bm_op  ? { 2'b01, bm_l } : base;
    red   <= blank ? 5'd0 : { pal_video_dout[15:12], pal_video_dout[3] };
    green <= blank ? 5'd0 : { pal_video_dout[11: 8], pal_video_dout[2] };
    blue  <= blank ? 5'd0 : { pal_video_dout[ 7: 4], pal_video_dout[1] };
end

endmodule
