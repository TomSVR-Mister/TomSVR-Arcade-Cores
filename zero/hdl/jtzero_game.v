/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Comad Zero Zone / Las Vegas Girl on JTFRAME (Jose Tejada, jotego). Personal build. */

module jtzero_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] inputs;
wire [ 7:0] sys;
wire [ 2:0] tilebank;
wire        snd_wr, vbl_irq;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

// inputs: P1 in the low byte, P2 in the high byte: right, left, down, up, button 1, button 2, (button 3), -
assign inputs = { 2'b11, joystick2[5:0], 2'b11, joystick1[5:0] };
// system: coin 1, coin 2, -, start 1, start 2
assign sys    = { 3'b111, cab_1p[1:0], 1'b1, coin[1:0] };

jtzero_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( vbl_irq      ),
    .dip_pause   ( dip_pause    ),
    .sys         ( sys          ),
    .inputs      ( inputs       ),
    .dipsw       ( dipsw[15:0]  ),
    .cpu_dout    ( cpu_dout     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .wram_addr   ( wram_addr    ),
    .wram_we     ( wram_we      ),
    .wram_dout   ( wram_dout    ),
    .xram_addr   ( xram_addr    ),
    .xram_we     ( xram_we      ),
    .xram_dout   ( xram_dout    ),
    .vram_addr   ( vram_addr    ),
    .vram_we     ( vram_we      ),
    .vram_dout   ( vram_dout    ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .tilebank    ( tilebank     ),
    .snd_wr      ( snd_wr       )
);

jtzero_sound u_sound(
    .rst        ( rst            ),
    .clk        ( clk            ),
    .cen4       ( cen4           ),
    .cen1       ( cen1           ),
    .main_dout  ( cpu_dout[15:8] ),
    .snd_wr     ( snd_wr         ),
    .rom_addr   ( snd_addr       ),
    .rom_cs     ( snd_cs         ),
    .rom_data   ( snd_data       ),
    .rom_ok     ( snd_ok         ),
    .oki_addr   ( oki_addr       ),
    .oki_data   ( oki_data       ),
    .oki_ok     ( oki_ok         ),
    .pcm        ( pcm            )
);
assign oki_cs = 1'b1;

jtzero_video u_video(
    .rst        ( rst             ),
    .clk        ( clk             ),
    .pxl_cen    ( pxl_cen         ),
    .gfx_en     ( gfx_en          ),
    .tilebank   ( tilebank        ),
    .vram_addr  ( vram_video_addr ),
    .vram_dout  ( vram_video_dout ),
    .pal_addr   ( pal_video_addr  ),
    .pal_dout   ( pal_video_dout  ),
    .rom_addr   ( gfx_addr        ),
    .rom_cs     ( gfx_cs          ),
    .rom_data   ( gfx_data        ),
    .rom_ok     ( gfx_ok          ),
    .vbl_irq    ( vbl_irq         ),
    .LHBL       ( LHBL            ),
    .LVBL       ( LVBL            ),
    .HS         ( HS              ),
    .VS         ( VS              ),
    .red        ( red             ),
    .green      ( green           ),
    .blue       ( blue            )
);

endmodule
