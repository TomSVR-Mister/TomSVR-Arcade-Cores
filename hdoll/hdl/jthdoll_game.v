/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Honey Doll (Barko, 1995; MAME snowbros.cpp "honeydol") on JTFRAME (Jose Tejada, jotego). Personal build. */

module jthdoll_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] in1, in2, sys;
wire [ 7:0] snd_latch;
wire [ 8:0] vdump;
wire        snd_wr, hs_start;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;

// DSW in the low byte. High byte, active low: up, down, left, right, B1, B2, B3; DSW1 bit 15 = vblank (active high)
assign in1 = { ~LVBL, joystick1[6:4], joystick1[0], joystick1[1], joystick1[2], joystick1[3], dipsw[ 7:0] };
assign in2 = { 1'b1,  joystick2[6:4], joystick2[0], joystick2[1], joystick2[2], joystick2[3], dipsw[15:8] };
// SYSTEM high byte: start 1, start 2, coin 1, coin 2, -, tilt, coin 3, -
assign sys = { 2'b11, tilt, 1'b1, coin[1], coin[0], cab_1p[1], cab_1p[0], 8'hff };

jthdoll_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .vdump       ( vdump        ),
    .hs_start    ( hs_start     ),
    .lvbl        ( LVBL         ),
    .dip_pause   ( dip_pause    ),
    .in1         ( in1          ),
    .in2         ( in2          ),
    .sys         ( sys          ),
    .cpu_dout    ( cpu_dout     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .wram_addr   ( wram_addr    ),
    .wram_we     ( wram_we      ),
    .wram_dout   ( wram_dout    ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .oram_addr   ( oram_addr    ),
    .oram_we     ( oram_we      ),
    .oram_dout   ( oram_dout    ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       )
);

jthdoll_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_4      ( cen_4         ),
    .cen_3      ( cen_3         ),
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
    .fm         ( fm            ),
    .pcm        ( pcm           )
);
assign oki_cs = 1'b1;

jthdoll_video u_video(
    .rst             ( rst             ),
    .clk             ( clk             ),
    .pxl_cen         ( pxl_cen         ),
    .gfx_en          ( gfx_en          ),
    .cpu_addr        ( oram_addr       ),
    .cpu_dout        ( cpu_dout        ),
    .oram_we         ( oram_we         ),
    .pal_video_addr  ( pal_video_addr  ),
    .pal_video_dout  ( pal_video_dout  ),
    .o8_addr         ( o8_addr         ),
    .o8_cs           ( o8_cs           ),
    .o8_data         ( o8_data         ),
    .o8_ok           ( o8_ok           ),
    .o4_addr         ( o4_addr         ),
    .o4_cs           ( o4_cs           ),
    .o4_data         ( o4_data         ),
    .o4_ok           ( o4_ok           ),
    .vdump           ( vdump           ),
    .hs_start        ( hs_start        ),
    .LHBL            ( LHBL            ),
    .LVBL            ( LVBL            ),
    .HS              ( HS              ),
    .VS              ( VS              ),
    .red             ( red             ),
    .green           ( green           ),
    .blue            ( blue            )
);

endmodule
