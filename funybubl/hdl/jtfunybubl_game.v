/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Funny Bubble (In Chang Electronic / Comad, 1999; MAME funybubl.cpp) on JTFRAME (Jose Tejada, jotego). Personal build. */

module jtfunybubl_game(
    `include "jtframe_game_ports.inc"
);

wire [ 7:0] snd_latch, sys, p1, p2;
wire [11:0] cpu_addr;
wire        snd_wr;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;

// SYSTEM: coin 1, coin 2, start 1, start 2   P1/P2: up, down, left, right, B1 (all active low)
assign sys = { 4'hf, cab_1p[1], cab_1p[0], coin[1], coin[0] };
assign p1  = { 3'b111, joystick1[4], joystick1[0], joystick1[1], joystick1[2], joystick1[3] };
assign p2  = { 3'b111, joystick2[4], joystick2[0], joystick2[1], joystick2[2], joystick2[3] };

assign pal_addr  = cpu_addr;
assign vram_addr = cpu_addr;
assign sram_addr = cpu_addr;

jtfunybubl_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .cen         ( cen_6        ),
    .lvbl        ( LVBL         ),
    .dip_pause   ( dip_pause    ),
    .sys         ( sys          ),
    .p1          ( p1           ),
    .p2          ( p2           ),
    .dsw         ( dipsw[7:0]   ),
    .cpu_dout    ( cpu_dout     ),
    .cpu_addr    ( cpu_addr     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .vram_we     ( vram_we      ),
    .vram_dout   ( vram_dout    ),
    .sram_we     ( sram_we      ),
    .sram_dout   ( sram_dout    ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       )
);

jtfunybubl_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_4      ( cen_4         ),
    .cen_1      ( cen_1         ),
    .latch      ( snd_latch     ),
    .snd_wr     ( snd_wr        ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .oki_addr   ( oki_addr      ),
    .oki_data   ( oki_data      ),
    .oki_ok     ( oki_ok        ),
    .pcm        ( pcm           )
);
assign oki_cs = 1'b1;

jtfunybubl_video u_video(
    .rst             ( rst             ),
    .clk             ( clk             ),
    .pxl_cen         ( pxl_cen         ),
    .gfx_en          ( gfx_en          ),
    .cpu_addr        ( cpu_addr        ),
    .cpu_dout        ( cpu_dout        ),
    .sram_we         ( sram_we         ),
    .vram_video_addr ( vram_video_addr ),
    .vram_video_dout ( vram_video_dout ),
    .pal_video_addr  ( pal_video_addr  ),
    .pal_video_dout  ( pal_video_dout  ),
    .tile_addr       ( tile_addr       ),
    .tile_cs         ( tile_cs         ),
    .tile_data       ( tile_data       ),
    .tile_ok         ( tile_ok         ),
    .spr_addr        ( spr_addr        ),
    .spr_cs          ( spr_cs          ),
    .spr_data        ( spr_data        ),
    .spr_ok          ( spr_ok          ),
    .LHBL            ( LHBL            ),
    .LVBL            ( LVBL            ),
    .HS              ( HS              ),
    .VS              ( VS              ),
    .red             ( red             ),
    .green           ( green           ),
    .blue            ( blue            )
);

endmodule
