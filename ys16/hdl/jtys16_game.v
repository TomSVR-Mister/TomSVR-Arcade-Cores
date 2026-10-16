/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 16-bit (YS-0211: Paparazzi, Shocking, Bomb Kick) on JTFRAME (Jose Tejada, jotego). Personal build. */

module jtys16_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] scr0x, scr0y, scr1x, scr1y, prio, inputs;
wire [ 7:0] sys, oki_dout;
wire [ 1:0] oki_bank;
wire        snd_wr, vbl_irq;
reg         mb = 0;     // header byte 0 bit 0: Magic Bubble YS1302 board (Z80 sound, 320-pixel window)

assign dip_flip   = 1'b0;
assign debug_view = prio[7:0];
always @(posedge clk) if( header && prog_we && prog_addr[1:0]==0 ) mb <= prog_data[0];

`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

// 800000: P1 in bits 7:0, P2 in bits 15:8 (right, left, down, up, buttons 1-3), active low
assign inputs = { 1'b1, joystick2[6:0], 1'b1, joystick1[6:0] };
// 800019: coin 1 (bit 0), coin 2 (bit 1), start 1 (bit 4), start 2 (bit 5), active low
assign sys    = { 2'b11, cab_1p[1:0], 2'b11, coin[1:0] };

jtys16_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( vbl_irq      ),
    .dip_pause   ( dip_pause    ),
    .inputs      ( inputs       ),
    .sys         ( sys          ),
    .dipsw       ( dipsw[15:0]  ),
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
    .vram0_addr  ( vram0_addr   ),
    .vram0_we    ( vram0_we     ),
    .vram0_dout  ( vram0_dout   ),
    .vram1_addr  ( vram1_addr   ),
    .vram1_we    ( vram1_we     ),
    .vram1_dout  ( vram1_dout   ),
    .objram_addr ( objram_addr  ),
    .objram_we   ( objram_we    ),
    .objram_dout ( objram_dout  ),
    .scr0x       ( scr0x        ),
    .scr0y       ( scr0y        ),
    .scr1x       ( scr1x        ),
    .scr1y       ( scr1y        ),
    .prio        ( prio         ),
    .snd_wr      ( snd_wr       ),
    .oki_dout    ( oki_dout     ),
    .oki_bank    ( oki_bank     )
);

jtys16_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen4       ( cen4          ),
    .cen_oki    ( cen_oki       ),
    .mb         ( mb            ),
    .cpu_dout   ( cpu_dout[7:0] ),
    .snd_wr     ( snd_wr        ),
    .bank       ( oki_bank      ),
    .oki_dout   ( oki_dout      ),
    .oki_cs     ( oki_cs        ),
    .oki_addr   ( oki_addr      ),
    .oki_data   ( oki_data      ),
    .oki_ok     ( oki_ok        ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .pcm        ( pcm           ),
    .fm         ( fm            )
);

jtys16_video u_video(
    .rst                ( rst               ),
    .clk                ( clk               ),
    .pxl_cen            ( pxl_cen           ),
    .gfx_en             ( gfx_en            ),
    .mb                 ( mb                ),
    .debug_bus          ( debug_bus         ),
    .scr0x              ( scr0x             ),
    .scr0y              ( scr0y             ),
    .scr1x              ( scr1x             ),
    .scr1y              ( scr1y             ),
    .prio               ( prio              ),
    .vram0_video_addr   ( vram0_video_addr  ),
    .vram0_video_dout   ( vram0_video_dout  ),
    .vram1_video_addr   ( vram1_video_addr  ),
    .vram1_video_dout   ( vram1_video_dout  ),
    .objram_video_addr  ( objram_video_addr ),
    .objram_video_dout  ( objram_video_dout ),
    .pal_video_addr     ( pal_video_addr    ),
    .pal_video_dout     ( pal_video_dout    ),
    .scr0_addr          ( scr0_addr         ),
    .scr0_cs            ( scr0_cs           ),
    .scr0_data          ( scr0_data         ),
    .scr0_ok            ( scr0_ok           ),
    .scr1_addr          ( scr1_addr         ),
    .scr1_cs            ( scr1_cs           ),
    .scr1_data          ( scr1_data         ),
    .scr1_ok            ( scr1_ok           ),
    .obj_addr           ( obj_addr          ),
    .obj_cs             ( obj_cs            ),
    .obj_data           ( obj_data          ),
    .obj_ok             ( obj_ok            ),
    .vbl_irq            ( vbl_irq           ),
    .LHBL               ( LHBL              ),
    .LVBL               ( LVBL              ),
    .HS                 ( HS                ),
    .VS                 ( VS                ),
    .red                ( red               ),
    .green              ( green             ),
    .blue               ( blue              )
);

endmodule
