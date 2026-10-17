/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 02-05-2020
 * Miss Bubble II / Bubble Pong Pong (MAME missb2.cpp), based on JTBUBL. Changes 2026 Tom Sveen.
 * Header byte 0 bit 0: Bubble Pong Pong background layout. */

module jtmissb_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire        snd_rst, black_n, flip;
wire [ 7:0] snd_latch, main_latch;
reg         alt = 0;
wire [ 7:0] dipsw_a, dipsw_b, bgvram, bgpal_dout, sub_cpu_dout;
wire [ 8:0] sub_pal_addr;
wire        main_flag, main_stb, snd_stb, bgpal_we;
wire [12:0] cpu_addr;
wire        vram_cs,  pal_cs;
wire        cpu_rnw;
wire [ 7:0] vram_dout, pal_dout, cpu_dout;
wire        snd_flag;

assign debug_view           = 8'd0;
assign { dipsw_b, dipsw_a } = dipsw[15:0];
assign dip_flip             = flip;

always @(posedge clk) begin
    if( prog_we && header && ioctl_addr[1:0]==0 ) alt <= prog_data[0];
end

jtmissb_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .cen6           ( cen6          ),
    .main_rom_addr  ( main_addr     ),
    .main_rom_cs    ( main_cs       ),
    .main_rom_ok    ( main_ok       ),
    .main_rom_data  ( main_data     ),
    .sub_rom_addr   ( sub_addr      ),
    .sub_rom_cs     ( sub_cs        ),
    .sub_rom_ok     ( sub_ok        ),
    .sub_rom_data   ( sub_data      ),
    .snd_latch      ( snd_latch     ),
    .snd_stb        ( snd_stb       ),
    .snd_flag       ( snd_flag      ),
    .main_stb       ( main_stb      ),
    .main_flag      ( main_flag     ),
    .main_latch     ( main_latch    ),
    .snd_rst        ( snd_rst       ),
    .cab_1p         ( cab_1p[1:0]   ),
    .coin           ( coin[1:0]     ),
    .joystick1      ( joystick1[5:0]),
    .joystick2      ( joystick2[5:0]),
    .service        ( service       ),
    .tilt           ( tilt          ),
    .LVBL           ( LVBL          ),
    .flip           ( flip          ),
    .black_n        ( black_n       ),
    .cpu_addr       ( cpu_addr      ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_rnw        ( cpu_rnw       ),
    .vram_cs        ( vram_cs       ),
    .vram_dout      ( vram_dout     ),
    .pal_cs         ( pal_cs        ),
    .pal_dout       ( pal_dout      ),
    .bgvram         ( bgvram        ),
    .bgpal_we       ( bgpal_we      ),
    .sub_pal_addr   ( sub_pal_addr  ),
    .sub_cpu_dout   ( sub_cpu_dout  ),
    .bgpal_dout     ( bgpal_dout    ),
    .dip_pause      ( dip_pause     ),
    .dipsw_a        ( dipsw_a       ),
    .dipsw_b        ( dipsw_b       )
);

jtmissb_video u_video(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .clk_cpu        ( clk           ),
    .pxl2_cen       ( pxl2_cen      ),
    .pxl_cen        ( pxl_cen       ),
    .LHBL           ( LHBL          ),
    .LVBL           ( LVBL          ),
    .HS             ( HS            ),
    .VS             ( VS            ),
    .flip           ( flip          ),
    .dip_pause      ( dip_pause     ),
    .cab_1p         ( &cab_1p       ),
    .prom_we        ( prom_we       ),
    .prog_addr      ( prog_addr[7:0]),
    .prog_data      ( prog_data[3:0]),
    .vram_cs        ( vram_cs       ),
    .pal_cs         ( pal_cs        ),
    .cpu_rnw        ( cpu_rnw       ),
    .cpu_addr       ( cpu_addr      ),
    .cpu_dout       ( cpu_dout      ),
    .vram_dout      ( vram_dout     ),
    .pal_dout       ( pal_dout      ),
    .black_n        ( black_n       ),
    .rom_addr       ( gfx_addr      ),
    .rom_data       ( gfx_data      ),
    .rom_ok         ( gfx_ok        ),
    .rom_cs         ( gfx_cs        ),
    .rom2_data      ( gfx2_data     ),
    .rom2_ok        ( gfx2_ok       ),
    .alt            ( alt           ),
    .bgvram         ( bgvram        ),
    .bg_addr        ( bg_addr       ),
    .bg_cs          ( bg_cs         ),
    .bg_data        ( bg_data       ),
    .bg_ok          ( bg_ok         ),
    .bgpal_we       ( bgpal_we      ),
    .sub_addr       ( sub_pal_addr  ),
    .sub_dout       ( sub_cpu_dout  ),
    .bgpal_dout     ( bgpal_dout    ),
    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          ),
    .gfx_en         ( gfx_en        )
);
assign gfx2_addr = gfx_addr;
assign gfx2_cs   = gfx_cs;

jtmissb_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .rstn       ( ~snd_rst      ),
    .cen3       ( cen3          ),
    .LVBL       ( LVBL          ),
    .cen_oki    ( cen_oki       ),
    .snd_latch  ( snd_latch     ),
    .main_latch ( main_latch    ),
    .snd_stb    ( snd_stb       ),
    .main_stb   ( main_stb      ),
    .snd_flag   ( snd_flag      ),
    .main_flag  ( main_flag     ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .oki_addr   ( oki_addr      ),
    .oki_data   ( oki_data      ),
    .oki_ok     ( oki_ok        ),
    .fm         ( fm            ),
    .pcm        ( pcm           )
);
assign oki_cs = 1'b1;

endmodule
