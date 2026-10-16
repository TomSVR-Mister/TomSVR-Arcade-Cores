/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gaelco Splash! / Painted Lady / New Splash on JTFRAME (Jose Tejada, jotego). Personal build. */

module jtsplash_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] scr0, scr1;
wire [ 7:0] p1, p2;
wire        snd_wr, vbl_irq;
reg         lo_attr = 0;    // header byte 0 bit 0: Splash! 1.0 sprite attribute in the low byte

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
always @(posedge clk) if( header && prog_we && prog_addr[1:0]==0 ) lo_attr <= prog_data[0];

`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

// P1: up, down, right, left, button 2, button 1, coin 1, coin 2 (active low)
assign p1 = { coin[1], coin[0], joystick1[4], joystick1[5], joystick1[1], joystick1[0], joystick1[2], joystick1[3] };
// P2: same, with start 1 and start 2 in bits 6 and 7
assign p2 = { cab_1p[1], cab_1p[0], joystick2[4], joystick2[5], joystick2[1], joystick2[0], joystick2[2], joystick2[3] };

assign vramb_addr = vram_addr;
assign vramb_we   = vram_we;

jtsplash_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( vbl_irq      ),
    .dip_pause   ( dip_pause    ),
    .p1          ( p1           ),
    .p2          ( p2           ),
    .dipsw       ( dipsw[15:0]  ),
    .cpu_dout    ( cpu_dout     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .wram_addr   ( wram_addr    ),
    .wram_we     ( wram_we      ),
    .wram_dout   ( wram_dout    ),
    .vram_addr   ( vram_addr    ),
    .vram_we     ( vram_we      ),
    .vram_dout   ( vram_dout    ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .objram_addr ( objram_addr  ),
    .objram_we   ( objram_we    ),
    .objram_dout ( objram_dout  ),
    .pix_addr    ( pix_addr     ),
    .pix_we      ( pix_we       ),
    .pix_dout    ( pix_dout     ),
    .scr0        ( scr0         ),
    .scr1        ( scr1         ),
    .snd_wr      ( snd_wr       )
);

jtsplash_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_snd    ( cen_snd       ),
    .cen_adpcm  ( cen_adpcm     ),
    .main_dout  ( cpu_dout[7:0] ),
    .snd_wr     ( snd_wr        ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .fm         ( fm            ),
    .pcm        ( pcm           )
);

jtsplash_video u_video(
    .rst                ( rst               ),
    .clk                ( clk               ),
    .pxl_cen            ( pxl_cen           ),
    .gfx_en             ( gfx_en            ),
    .debug_bus          ( debug_bus         ),
    .lo_attr            ( lo_attr           ),
    .scr0               ( scr0              ),
    .scr1               ( scr1              ),
    .vram_video_addr    ( vram_video_addr   ),
    .vram_video_dout    ( vram_video_dout   ),
    .vramb_video_addr   ( vramb_video_addr  ),
    .vramb_video_dout   ( vramb_video_dout  ),
    .objram_video_addr  ( objram_video_addr ),
    .objram_video_dout  ( objram_video_dout ),
    .pal_video_addr     ( pal_video_addr    ),
    .pal_video_dout     ( pal_video_dout    ),
    .pix_video_addr     ( pix_video_addr    ),
    .pix_video_dout     ( pix_video_dout    ),
    .tm0_addr           ( tm0_addr          ),
    .tm0_cs             ( tm0_cs            ),
    .tm0_data           ( tm0_data          ),
    .tm0_ok             ( tm0_ok            ),
    .tm1_addr           ( tm1_addr          ),
    .tm1_cs             ( tm1_cs            ),
    .tm1_data           ( tm1_data          ),
    .tm1_ok             ( tm1_ok            ),
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
