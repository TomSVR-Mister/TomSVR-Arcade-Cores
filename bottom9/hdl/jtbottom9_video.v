/* SPDX-License-Identifier: GPL-3.0-or-later
   Bottom of the Ninth video: K052109/K051962 tilemaps (layers A and B, the fix layer is unused) and
   K051960/K051937 sprites from jotego's jtaliens, one K051316 (4 bpp) zoom layer, 1024-colour xBGR_555 palette
   with shadows. Mixing follows MAME bottom9.cpp screen_update (see jtbottom9_colmix) */

module jtbottom9_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,
    input             cen24,

    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    // CPU interface
    input      [15:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_we,
    input             tilesys_cs, objsys_cs, pal_cs, roz_vr, roz_io,
    input             rmrd, video_en,
    input             roz_romrd,    // 1f90 bit 4: CPU reads the K051316 ROM
    output            rst8,
    output     [ 7:0] tilesys_dout, objsys_dout, pal_dout, roz_dout,
    output            tile_dtack,
    output            roz_cok,
    output            irq_n,
    output reg        nmi_tick,     // sound NMI: MAME scanlines 16, 48, ... 240

    // ROMs
    output     [18:2] lyrf_addr, lyra_addr, lyrb_addr,
    output     [19:2] lyro_addr,
    output            lyrf_cs, lyra_cs, lyrb_cs, lyro_cs,
    input             lyra_ok, lyro_ok,
    input      [31:0] lyrf_data, lyra_data, lyrb_data, lyro_data,

    output     [16:0] roz_addr,
    output            roz_cs,
    input             roz_rok,
    input      [ 7:0] roz_data,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus
);

wire [ 8:0] hdump, vdump, vrender, vrender1, rpx;
wire [12:0] pre_f, pre_a, pre_b, ocode;
wire [ 7:0] lyrf_col, lyra_col, lyrb_col, opal, lyrf_pxl, roz_ram;
wire [11:0] lyra_pxl, lyrb_pxl, opxl;
wire [ 6:0] nc;
wire        nco;
wire        lyrf_blnk_n, lyra_blnk_n, lyrb_blnk_n, oblnk_n, oshadow, rblk_n;
reg  [ 7:0] roz_rom;
reg  [ 8:0] vdump_l;
reg  [ 1:0] map52;   // K052109 register 1c00 bits 1:0 (memory mapper)
wire [15:0] tile_addr;

// jt052109 decodes the CPU address with its 1c00 mapper (RAM at 6000-7fff after reset, 0000-3fff once the game
// writes 1c00=13). MAME maps the chip at 0000-3fff whatever the mapper says, so shift the address to match
assign tile_addr = cpu_addr + { 1'b0, ~map52, 13'd0 };

// K052109 tile callback: code |= (color & 0x3f) << 8, so the ROM word address is {color[5:0], code[7:0], row}
assign lyrf_addr = { lyrf_col[5:0], pre_f[10:0] };
assign lyra_addr = { lyra_col[5:0], pre_a[10:0] };
assign lyrb_addr = { lyrb_col[5:0], pre_b[10:0] };
assign roz_dout  = roz_romrd ? roz_rom : roz_ram;

always @(posedge clk) begin
    roz_rom <= roz_data;
    if( rst ) map52 <= 0;
    else if( tilesys_cs && cpu_we && cpu_addr[13:7]==7'b01_1100_0 ) map52 <= cpu_dout[1:0];
    vdump_l <= vdump;
    nmi_tick <= vdump != vdump_l && vdump[8] && vdump[4:0]==5'h10;
end

// MAME shows 288 of the 320 pixels jt051962 outputs: 16 fewer on each side. HB_START = 0x29-HB_EXTRAR wraps to 0x199
jtaliens_scroll #(.HB_EXTRAL(9'd16),.HB_EXTRAR(9'h090)) u_scroll(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),
    .q          (           ),
    .e          (           ),
    .mmr_dump   (           ),
    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),
    .vs         ( vs        ),
    .cpu_addr   ( tile_addr ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .gfx_cs     ( tilesys_cs),
    .rst8       ( rst8      ),
    .tile_dout  ( tilesys_dout ),
    .cpu_rom_dtack ( tile_dtack ),
    .rmrd       ( rmrd      ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),
    .irq_n      ( irq_n     ),
    .firq_n     (           ),
    .nmi_n      (           ),
    .flip       (           ),
    .lyrf_extra (           ),
    .lyra_extra (           ),
    .lyrb_extra (           ),
    .lyrf_col   ( lyrf_col  ),
    .lyra_col   ( lyra_col  ),
    .lyrb_col   ( lyrb_col  ),
    .lyrf_cg    ( { lyrf_col[7:6], 6'd0 } ),
    .lyra_cg    ( { lyra_col[7:6], 6'd0 } ),
    .lyrb_cg    ( { lyrb_col[7:6], 6'd0 } ),
    .lyrf_addr  ( pre_f     ),
    .lyra_addr  ( pre_a     ),
    .lyrb_addr  ( pre_b     ),
    .lyrf_cs    ( lyrf_cs   ),
    .lyra_cs    ( lyra_cs   ),
    .lyrb_cs    ( lyrb_cs   ),
    .lyrf_data  ( lyrf_data ),
    .lyra_data  ( lyra_data ),
    .lyrb_data  ( lyrb_data ),
    .lyra_ok    ( lyra_ok   ),
    .lyrf_blnk_n(lyrf_blnk_n),
    .lyra_blnk_n(lyra_blnk_n),
    .lyrb_blnk_n(lyrb_blnk_n),
    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .ioctl_addr ( 15'd0     ),
    .ioctl_ram  ( 1'b0      ),
    .ioctl_din  (           ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus ),
    .st_dout    (           )
);

jtbottom9_roz #(.BPP(4),.RD_DLY(9'h011),.WR_STRT(9'h058),.RST_CT(9'h058),
    .MMRFILE("roz_mmr.bin"),.RAM0FILE("roz0.bin"),.RAM1FILE("roz1.bin")) u_roz(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .cen24      ( cen24     ),
    .vs         ( vs        ),
    .hs         ( hs        ),
    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .cpu_addr   ( cpu_addr[10:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .cpu_din    ( roz_ram   ),
    .cpu_ok     ( roz_cok   ),
    .io_cs      ( roz_io    ),
    .vr_cs      ( roz_vr    ),
    .ext_rd     ( roz_romrd ),
    .pxl        ( rpx       ),
    .blnk_n     ( rblk_n    ),
    .rvo        ( 1'b0      ),
    .wrap       ( 1'b0      ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .rom_addr   ({nc,roz_addr}),
    .rom_cs     ( roz_cs    ),
    .rom_ok     ( roz_rok   ),
    .rom_data   ( roz_data  ),
    .rom2_addr  (           ),
    .rom2_cs    (           ),
    .rom2_ok    ( 1'b0      ),
    .rom2_data  ( 8'd0      ),
    .ioctl_addr ( 11'd0     ),
    .ioctl_ram  ( 1'b0      ),
    .ioctl_din  (           ),
    .mmr_dump   (           )
);

jtaliens_obj u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .hs         ( hs        ),
    .vs         ( vs        ),
    .lvbl       ( lvbl      ),
    .lhbl       ( lhbl      ),
    .hdump      ( hdump     ),
    .vdump      ( vrender   ),
    .cs         ( objsys_cs ),
    .cpu_addr   ( cpu_addr[10:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we    ),
    .cpu_din    ( objsys_dout ),
    .irq_n      (           ),
    .nmi_n      (           ),
    .romrd      (           ),
    .pal        ( opal      ),
    .code       ( ocode     ),
    .code_eff   ( { 1'b0, ocode } ),
    .pal_eff    ( opal      ),
    .rom_addr   ({nco,lyro_addr}),
    .rom_data   ( lyro_data ),
    .rom_ok     ( lyro_ok   ),
    .rom_cs     ( lyro_cs   ),
    .pxl        ( opxl      ),
    .blank_n    ( oblnk_n   ),
    .shadow     ( oshadow   ),
    .ioctl_addr ( 11'd0     ),
    .ioctl_ram  ( 1'b0      ),
    .ioctl_din  (           ),
    .dump_reg   (           ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus ),
    .st_dout    (           )
);

jtbottom9_colmix u_colmix(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .video_en   ( video_en  ),
    .cpu_addr   ( cpu_addr[10:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we & pal_cs ),
    .cpu_din    ( pal_dout  ),
    .apxl       ( lyra_pxl[7:0] ),
    .ablnk_n    ( lyra_blnk_n ),
    .bpxl       ( lyrb_pxl[7:0] ),
    .bblnk_n    ( lyrb_blnk_n ),
    .rpx        ( rpx[7:0]  ),
    .rblk_n     ( rblk_n & gfx_en[0] ),
    .opxl       ( opxl      ),
    .oblnk_n    ( oblnk_n   ),
    .oshadow    ( oshadow   ),
    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      )
);

`ifdef SIMULATION
integer tw=0, nzd=0, nzc=0; reg vsl;
always @(posedge clk) begin
    vsl <= vs;
    if( tilesys_cs && cpu_we ) tw <= tw+1;
    if( lyra_cs && lyra_ok && lyra_data!=0 ) nzd <= nzd+1;
    if( lyra_col!=0 || pre_a[10:3]!=0 ) nzc <= nzc+1;
    if( vs && !vsl ) begin $display("TS tw=%0d nzdata=%0d nzcode=%0d", tw, nzd, nzc); tw<=0; nzd<=0; nzc<=0; end
end
`endif

endmodule
