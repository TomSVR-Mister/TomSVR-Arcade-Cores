/*  This file is part of JTXEXEX.
    SPDX-License-Identifier: GPL-3.0-or-later
    JTXEXEX: Konami Xexex / Orius (1991), from MAME's xexex.cpp. Built on JTFRAME, jotego's 68000/Z80
    wrappers, jt51 (YM2151), jt5911 (ER5911 EEPROM) and the K053246/K054321 models of JTSIMSON/JTRIDERS. */

module jtxexex_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire [23:1] cpu_addr;
wire [ 1:0] cpu_dsn;
wire        cpu_we, ram_cs, tmap_reg_cs, tmap_ram_cs, lvc_ram_cs, lvc_reg_cs, obj_ram_cs, obj_reg_cs,
            pal_cs, k251_cs, k338_cs, objcha_n, alpha_off, dma_bsy, vb_start, snd_irq, pair_we, nv_we;
wire [15:0] tmap_dout, lvc_dout, obj_dout, pal_dout;
wire [ 7:0] lvc_reg_dout, pair_dout, nv_dout, nv_din, st_main;
wire [ 6:0] nv_addr;
wire [ 8:0] vdump;
reg         line0, lvbl_l;

assign dip_flip   = 0;
assign debug_view = st_main;
assign ram_we     = ~cpu_dsn & {2{ram_cs & cpu_we}};

always @(posedge clk) begin
    lvbl_l <= LVBL;
    line0  <= LVBL & ~lvbl_l;
end

// ER5911 contents: port 0 for the chip, port 1 loads the default (MRA rom index 2) or the saved NVRAM
jtframe_dual_ram #(.DW(8),.AW(7),.SIMFILE("nvram.bin")) u_nvram(
    .clk0   ( clk               ),
    .data0  ( nv_din            ),
    .addr0  ( nv_addr           ),
    .we0    ( nv_we             ),
    .q0     ( nv_dout           ),
    .clk1   ( clk               ),
    .data1  ( ioctl_dout        ),
    .addr1  ( ioctl_addr[6:0]   ),
    .we1    ( ioctl_ram & ioctl_wr ),
    .q1     ( ioctl_din         )
);

jtxexex_main u_main(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .LVBL       ( LVBL          ),
    .vb_start   ( vb_start      ),
    .line0      ( line0         ),
    .dma_bsy    ( dma_bsy       ),
    .vdump      ( vdump         ),
    .cpu_addr   ( cpu_addr      ),
    .cpu_dout   ( cpu_dout      ),
    .cpu_dsn    ( cpu_dsn       ),
    .cpu_we     ( cpu_we        ),
    .rom_addr   ( main_addr     ),
    .rom_cs     ( main_cs       ),
    .rom_data   ( main_data     ),
    .rom_ok     ( main_ok       ),
    .ram_cs     ( ram_cs        ),
    .ram_dout   ( ram_dout      ),
    .tmap_reg_cs( tmap_reg_cs   ),
    .tmap_ram_cs( tmap_ram_cs   ),
    .lvc_ram_cs ( lvc_ram_cs    ),
    .lvc_reg_cs ( lvc_reg_cs    ),
    .obj_ram_cs ( obj_ram_cs    ),
    .obj_reg_cs ( obj_reg_cs    ),
    .pal_cs     ( pal_cs        ),
    .k251_cs    ( k251_cs       ),
    .k338_cs    ( k338_cs       ),
    .tmap_dout  ( tmap_dout     ),
    .lvc_dout   ( lvc_dout      ),
    .lvc_reg_dout( lvc_reg_dout ),
    .obj_dout   ( obj_dout      ),
    .pal_dout   ( pal_dout      ),
    .objcha_n   ( objcha_n      ),
    .alpha_off  ( alpha_off     ),
    .snd_irq    ( snd_irq       ),
    .pair_we    ( pair_we       ),
    .pair_dout  ( pair_dout     ),
    .nv_addr    ( nv_addr       ),
    .nv_dout    ( nv_dout       ),
    .nv_din     ( nv_din        ),
    .nv_we      ( nv_we         ),
    .joystick1  ( {1'b1, joystick1[5:0]} ),
    .joystick2  ( {1'b1, joystick2[5:0]} ),
    .cab_1p     ( cab_1p[1:0]   ),
    .coin       ( coin[1:0]     ),
    .service    ( service       ),
    .dip_test   ( dip_test      ),
    .dip_pause  ( dip_pause     ),
    .st_dout    ( st_main       )
);

jtxexex_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_8      ( cen_8         ),
    .cen_fm     ( cen_fm        ),
    .cen_fm2    ( cen_fm2       ),
    .cen_pcm    ( cen_pcm       ),
    .snd_irq    ( snd_irq       ),
    .pair_we    ( pair_we       ),
    .main_addr  ( cpu_addr[4:1] ),
    .main_dout  ( cpu_dout[7:0] ),
    .pair_dout  ( pair_dout     ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .pcm_addr   ( pcm_addr      ),
    .pcm_cs     ( pcm_cs        ),
    .pcm_data   ( pcm_data      ),
    .pcm_ok     ( pcm_ok        ),
    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),
    .k539_l     ( k539_l        ),
    .k539_r     ( k539_r        )
);

jtxexex_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .pxl2_cen   ( pxl2_cen      ),
    .cpu_addr   ( cpu_addr[14:1]),
    .cpu_dout   ( cpu_dout      ),
    .cpu_dsn    ( cpu_dsn       ),
    .cpu_we     ( cpu_we        ),
    .tmap_reg_cs( tmap_reg_cs   ),
    .tmap_ram_cs( tmap_ram_cs   ),
    .lvc_ram_cs ( lvc_ram_cs    ),
    .lvc_reg_cs ( lvc_reg_cs    ),
    .obj_ram_cs ( obj_ram_cs    ),
    .obj_reg_cs ( obj_reg_cs    ),
    .pal_cs     ( pal_cs        ),
    .k251_cs    ( k251_cs       ),
    .k338_cs    ( k338_cs       ),
    .objcha_n   ( objcha_n      ),
    .alpha_off  ( alpha_off     ),
    .tmap_dout  ( tmap_dout     ),
    .lvc_dout   ( lvc_dout      ),
    .lvc_reg_dout( lvc_reg_dout ),
    .obj_dout   ( obj_dout      ),
    .pal_dout   ( pal_dout      ),
    .dma_bsy    ( dma_bsy       ),
    .vb_start   ( vb_start      ),
    .vdump      ( vdump         ),
    .tile_addr  ( tile_addr     ),
    .tile_cs    ( tile_cs       ),
    .tile_data  ( tile_data     ),
    .tile_ok    ( tile_ok       ),
    .lvc_addr   ( lvc_addr      ),
    .lvc_cs     ( lvc_cs        ),
    .lvc_data   ( lvc_data      ),
    .lvc_ok     ( lvc_ok        ),
    .obj_addr   ( obj_addr      ),
    .obj_cs     ( obj_cs        ),
    .obj_data   ( obj_data      ),
    .obj_ok     ( obj_ok        ),
    .LHBL       ( LHBL          ),
    .LVBL       ( LVBL          ),
    .HS         ( HS            ),
    .VS         ( VS            ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          ),
    // JTFRAME's 4 layer keys: A+B, C+D, K053250, sprites
    .gfx_en     ( { 2'b11, gfx_en[3], gfx_en[2], {2{gfx_en[1]}}, {2{gfx_en[0]}} } ),
    .debug_bus  ( debug_bus     )
);

endmodule
