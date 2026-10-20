/* SPDX-License-Identifier: GPL-3.0-or-later
   Chequered Flag video: K051960/K051937 sprites (jotego's jtaliens_obj), two K051316 (4 bpp text/HUD layer
   and 8 bpp road/background layer), 1024-colour xBGR_555 palette with shadows and highlights */

module jtchqflag_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             cen24,

    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    // CPU interface
    input      [15:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_we,
    input             objsys_cs, pal_cs, roza_vr, roza_io, rozb_vr, rozb_io,
    input      [ 7:0] vreg,
    output     [ 7:0] objsys_dout, pal_dout, roza_dout, rozb_dout,
    output reg [ 7:0] roz_rom,
    output            roza_ok, rozb_ok,
    output            irq_n, nmi_n,

    // ROMs
    output     [19:2] lyro_addr,
    output            lyro_cs,
    input             lyro_ok,
    input      [31:0] lyro_data,

    output     [16:0] roza_addr,
    output            roza_cs,
    input             roza_rok,
    input      [ 7:0] roza_data,

    output     [19:0] rozb_addr,
    output            rozb_cs,
    input             rozb_rok,
    input      [ 7:0] rozb_data,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus
);

wire [ 8:0] hdump, vdump, vrender, vrender1, rpxa, rpxb;
wire [11:0] opxl;
wire [12:0] ocode;
wire [ 7:0] opal;
wire [ 6:0] nca;
wire [ 3:0] ncb;
wire        nco;
wire        oblnk_n, oshadow, rblka_n, rblkb_n;
reg         hl_mode;

always @(posedge clk) begin
    roz_rom <= roza_vr ? roza_data : rozb_data;
    // K051937 register 1 bit 0: shadows become highlights
    if( objsys_cs && cpu_we && cpu_addr[10:0]==11'h001 ) hl_mode <= cpu_dout[0];
end

jtframe_vtimer #(
    .HCNT_START ( 9'h020    ),
    .HCNT_END   ( 9'h19F    ),
    .HB_START   ( 9'h199    ),   // 304 visible pixels, the same left edge as 88 Games
    .HB_END     ( 9'h069    ),
    .HS_START   ( 9'h034    ),
    .V_START    ( 9'h0F8    ),
    .VB_START   ( 9'h1EF    ),
    .VB_END     ( 9'h10F    ),
    .VS_START   ( 9'h1FF    ),
    .VS_END     ( 9'h0FF    ),
    .VCNT_END   ( 9'h1FF    )
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),
    .H          ( hdump     ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( lhbl      ),
    .LVBL       ( lvbl      ),
    .HS         ( hs        ),
    .VS         ( vs        )
);

// MAME offsets (7,0): 7 pixels later than 88 Games. The buffer is written from 0x58 with no
// skipped counter steps, so the first visible pixels are valid
jtchqflag_roz #(.BPP(4),.RD_DLY(9'h011),.WR_STRT(9'h058),.RST_CT(9'h058),
    .MMRFILE("roza_mmr.bin"),.RAM0FILE("roza0.bin"),.RAM1FILE("roza1.bin")) u_roza(
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
    .cpu_din    ( roza_dout ),
    .cpu_ok     ( roza_ok   ),
    .io_cs      ( roza_io   ),
    .vr_cs      ( roza_vr   ),
    .pxl        ( rpxa      ),
    .blnk_n     ( rblka_n   ),
    .rvo        ( 1'b0      ),
    .wrap       ( 1'b0      ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .rom_addr   ({nca,roza_addr}),
    .rom_cs     ( roza_cs   ),
    .rom_ok     ( roza_rok  ),
    .rom_data   ( roza_data ),
    .ioctl_addr ( 11'd0     ),
    .ioctl_ram  ( 1'b0      ),
    .ioctl_din  (           ),
    .mmr_dump   (           )
);

jtchqflag_roz #(.BPP(8),.RD_DLY(9'h011),.WR_STRT(9'h058),.RST_CT(9'h058),
    .MMRFILE("rozb_mmr.bin"),.RAM0FILE("rozb0.bin"),.RAM1FILE("rozb1.bin")) u_rozb(
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
    .cpu_din    ( rozb_dout ),
    .cpu_ok     ( rozb_ok   ),
    .io_cs      ( rozb_io   ),
    .vr_cs      ( rozb_vr   ),
    .pxl        ( rpxb      ),
    .blnk_n     ( rblkb_n   ),
    .rvo        ( 1'b0      ),
    .wrap       ( 1'b1      ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .rom_addr   ({ncb,rozb_addr}),
    .rom_cs     ( rozb_cs   ),
    .rom_ok     ( rozb_rok  ),
    .rom_data   ( rozb_data ),
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
    .irq_n      ( irq_n     ),
    .nmi_n      ( nmi_n     ),
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

jtchqflag_colmix u_colmix(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .cpu_addr   ( cpu_addr[10:0] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_we     ( cpu_we & pal_cs ),
    .cpu_din    ( pal_dout  ),
    .vreg       ( vreg      ),
    .hl_mode    ( hl_mode   ),
    .rpxa       ( rpxa      ),
    .rblka_n    ( rblka_n & gfx_en[0] ),
    .rpxb       ( rpxb      ),
    .rblkb_n    ( gfx_en[1] ),
    .opxl       ( opxl      ),
    .oblnk_n    ( oblnk_n   ),
    .oshadow    ( oshadow & gfx_en[3] ),
    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      )
);

endmodule
