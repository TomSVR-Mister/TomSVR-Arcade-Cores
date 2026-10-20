/* SPDX-License-Identifier: GPL-3.0-or-later
   JTCHQFLAG: Konami Chequered Flag (GX717), from MAME chqflag.cpp. Built on JTFRAME and jotego's
   Konami chip models (jtkcpu, K051960, K051316, K051733, K007232, jt51) */

module jtchqflag_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire        cpu_cen, cpu_we, objsys_cs, pal_cs, roza_vr, roza_io, rozb_vr, rozb_io,
            roza_cok, rozb_cok, irq_n, nmi_n, snd_irq;
wire [ 7:0] main_dout, objsys_dout, pal_dout, roza_dout, rozb_dout, roz_rom, vreg,
            snd_latch, snd_latch2, st_main, st_snd;
wire [15:0] cpu_addr;

assign ram_din    = main_dout;
assign debug_view = debug_bus[7] ? st_snd : st_main;
assign dip_flip   = 0;

jtchqflag_main u_main(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_ref    ( cen24         ),
    .cpu_cen    ( cpu_cen       ),
    .cpu_addr   ( cpu_addr      ),
    .cpu_dout   ( main_dout     ),
    .cpu_we     ( cpu_we        ),
    .rom_addr   ( main_addr     ),
    .rom_data   ( main_data     ),
    .rom_cs     ( main_cs       ),
    .rom_ok     ( main_ok       ),
    .ram_we     ( ram_we        ),
    .ram_dout   ( ram_dout      ),
    .cab_1p     ( cab_1p[1:0]   ),
    .coin       ( coin[1:0]     ),
    .joystick1  ( joystick1     ),
    .joyana     ( joyana_l1     ),
    .service    ( service       ),
    .lvbl       ( LVBL          ),
    .dip_test   ( dip_test      ),
    .dip_pause  ( dip_pause     ),
    .dipsw      ( dipsw[23:0]   ),
    .irq_n      ( irq_n         ),
    .nmi_n      ( nmi_n         ),
    .objsys_cs  ( objsys_cs     ),
    .pal_cs     ( pal_cs        ),
    .roza_vr    ( roza_vr       ),
    .roza_io    ( roza_io       ),
    .rozb_vr    ( rozb_vr       ),
    .rozb_io    ( rozb_io       ),
    .vreg       ( vreg          ),
    .objsys_dout( objsys_dout   ),
    .pal_dout   ( pal_dout      ),
    .roza_dout  ( roza_dout     ),
    .rozb_dout  ( rozb_dout     ),
    .roz_rom    ( roz_rom       ),
    .roza_ok    ( roza_cok      ),
    .rozb_ok    ( rozb_cok      ),
    .snd_latch  ( snd_latch     ),
    .snd_latch2 ( snd_latch2    ),
    .snd_irq    ( snd_irq       ),
    .debug_bus  ( debug_bus     ),
    .st_dout    ( st_main       )
);

jtchqflag_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .cen24      ( cen24         ),
    .lhbl       ( LHBL          ),
    .lvbl       ( LVBL          ),
    .hs         ( HS            ),
    .vs         ( VS            ),
    .cpu_addr   ( cpu_addr      ),
    .cpu_dout   ( main_dout     ),
    .cpu_we     ( cpu_we        ),
    .objsys_cs  ( objsys_cs     ),
    .pal_cs     ( pal_cs        ),
    .roza_vr    ( roza_vr       ),
    .roza_io    ( roza_io       ),
    .rozb_vr    ( rozb_vr       ),
    .rozb_io    ( rozb_io       ),
    .vreg       ( vreg          ),
    .objsys_dout( objsys_dout   ),
    .pal_dout   ( pal_dout      ),
    .roza_dout  ( roza_dout     ),
    .rozb_dout  ( rozb_dout     ),
    .roz_rom    ( roz_rom       ),
    .roza_ok    ( roza_cok      ),
    .rozb_ok    ( rozb_cok      ),
    .irq_n      ( irq_n         ),
    .nmi_n      ( nmi_n         ),
    .lyro_addr  ( lyro_addr     ),
    .lyro_cs    ( lyro_cs       ),
    .lyro_ok    ( lyro_ok       ),
    .lyro_data  ( lyro_data     ),
    .roza_addr  ( roza_addr     ),
    .roza_cs    ( roza_cs       ),
    .roza_rok   ( roza_ok       ),
    .roza_data  ( roza_data     ),
    .rozb_addr  ( rozb_addr     ),
    .rozb_cs    ( rozb_cs       ),
    .rozb_rok   ( rozb_ok       ),
    .rozb_data  ( rozb_data     ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          ),
    .gfx_en     ( gfx_en        ),
    .debug_bus  ( debug_bus     )
);

jtchqflag_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_fm     ( cen_fm        ),
    .cen_fm2    ( cen_fm2       ),
    .snd_latch  ( snd_latch     ),
    .snd_latch2 ( snd_latch2    ),
    .snd_irq    ( snd_irq       ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .pcm1a_addr ( pcm1a_addr    ),
    .pcm1a_dout ( pcm1a_data    ),
    .pcm1a_cs   ( pcm1a_cs      ),
    .pcm1a_ok   ( pcm1a_ok      ),
    .pcm1b_addr ( pcm1b_addr    ),
    .pcm1b_dout ( pcm1b_data    ),
    .pcm1b_cs   ( pcm1b_cs      ),
    .pcm1b_ok   ( pcm1b_ok      ),
    .pcm2a_addr ( pcm2a_addr    ),
    .pcm2a_dout ( pcm2a_data    ),
    .pcm2a_cs   ( pcm2a_cs      ),
    .pcm2a_ok   ( pcm2a_ok      ),
    .pcm2b_addr ( pcm2b_addr    ),
    .pcm2b_dout ( pcm2b_data    ),
    .pcm2b_cs   ( pcm2b_cs      ),
    .pcm2b_ok   ( pcm2b_ok      ),
    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),
    .pcm1_l     ( pcm1_l        ),
    .pcm1_r     ( pcm1_r        ),
    .pcm2       ( pcm2          ),
    .debug_bus  ( debug_bus     ),
    .st_dout    ( st_snd        )
);

endmodule
