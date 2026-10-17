/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung YS-1300 / YS-2111 (Multi 5, Puzzle Club, Wonder Stick) on JTFRAME (Jose Tejada, jotego). Personal build.
 * Header byte 0: bit 0 Puzzle Club memory map, bit 1 16 MB tile ROM (bank select), bit 2 16384 sprite tiles,
 *   bit 3 Multi 5: SYSTEM bits 4 and 6 read 0 (MAME IPT_CUSTOM, the boot code waits for them),
 *   bit 4 4096 sprite tiles (Search Eye), bit 5 55 Hz (Search Eye Plus), bit 6 Puzzle Club sound map with the Multi 5 main map (7 Ordi),
 *   bit 7 7 Ordi inputs (six buttons, no joystick).
 * Header byte 1: protection value. */

module jtnmg5_game(
    `include "jtframe_game_ports.inc"
);

wire [ 8:0] scr0x, scr0y, scr1x, scr1y;
wire [ 7:0] snd_latch;
wire [ 1:0] gfx_bank;
wire [ 2:0] prio;
wire [15:0] inputs, system;
wire        snd_wr, vbl_irq;
reg         pc = 0, tbig = 0, obig = 0, cust = 0, osmall = 0, hz55 = 0, psnd = 0, ordi = 0;
reg  [ 7:0] prot_val = 0;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
always @(posedge clk) if( header && prog_we ) begin
    if( prog_addr[1:0]==0 ) { ordi, psnd, hz55, osmall, cust, obig, tbig, pc } <= prog_data;
    if( prog_addr[1:0]==1 ) prot_val <= prog_data;
end

`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

// active low: up, down, left, right, button 1-3, start (P1 low byte, P2 high byte)
// 7 Ordi: 0 button 5, 1 button 4, 2 button 1, 3 button 2, 4 button 3, 7 start, 9 reset credits (service), 10 button 6, 15 service 1
assign inputs = ordi ?
                { service, 4'hf, joystick1[9], 1'b1, 1'b1, cab_1p[0], 2'b11, joystick1[6], joystick1[5], joystick1[4], joystick1[7], joystick1[8] } :
                { cab_1p[1], joystick2[6:4], joystick2[0], joystick2[1], joystick2[2], joystick2[3],
                  cab_1p[0], joystick1[6:4], joystick1[0], joystick1[1], joystick1[2], joystick1[3] };
assign system = { 9'h1ff, ~cust, 1'b1, ~cust, 2'b11, coin[1], coin[0] };

jtnmg5_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( vbl_irq      ),
    .dip_pause   ( dip_pause    ),
    .pc          ( pc           ),
    .prot_val    ( prot_val     ),
    .inputs      ( inputs       ),
    .system      ( system       ),
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
    .objram_addr ( objram_addr  ),
    .objram_we   ( objram_we    ),
    .objram_dout ( objram_dout  ),
    .vram0_addr  ( vram0_addr   ),
    .vram0_we    ( vram0_we     ),
    .vram0_dout  ( vram0_dout   ),
    .vram1_addr  ( vram1_addr   ),
    .vram1_we    ( vram1_we     ),
    .vram1_dout  ( vram1_dout   ),
    .pix_addr    ( pix_addr     ),
    .pix_we      ( pix_we       ),
    .pix_dout    ( pix_dout     ),
    .scr0x       ( scr0x        ),
    .scr0y       ( scr0y        ),
    .scr1x       ( scr1x        ),
    .scr1y       ( scr1y        ),
    .gfx_bank    ( gfx_bank     ),
    .prio        ( prio         ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       )
);

jtnmg5_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_snd    ( cen_snd       ),
    .cen_oki    ( cen_oki       ),
    .pc         ( pc            ),
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

jtnmg5_video u_video(
    .rst                ( rst               ),
    .clk                ( clk               ),
    .pxl_cen            ( pxl_cen           ),
    .gfx_en             ( gfx_en            ),
    .tbig               ( tbig              ),
    .obig               ( obig              ),
    .osmall             ( osmall            ),
    .hz55               ( hz55              ),
    .gfx_bank           ( gfx_bank          ),
    .prio               ( prio              ),
    .scr0x              ( scr0x             ),
    .scr0y              ( scr0y             ),
    .scr1x              ( scr1x             ),
    .scr1y              ( scr1y             ),
    .vram0_video_addr   ( vram0_video_addr  ),
    .vram0_video_dout   ( vram0_video_dout  ),
    .vram1_video_addr   ( vram1_video_addr  ),
    .vram1_video_dout   ( vram1_video_dout  ),
    .objram_video_addr  ( objram_video_addr ),
    .objram_video_dout  ( objram_video_dout ),
    .pix_video_addr     ( pix_video_addr    ),
    .pix_video_dout     ( pix_video_dout    ),
    .pal_video_addr     ( pal_video_addr    ),
    .pal_video_dout     ( pal_video_dout    ),
    .t0l_addr ( t0l_addr ),
    .t0l_cs   ( t0l_cs   ),
    .t0l_data ( t0l_data ),
    .t0l_ok   ( t0l_ok   ),
    .t1l_addr ( t1l_addr ),
    .t1l_cs   ( t1l_cs   ),
    .t1l_data ( t1l_data ),
    .t1l_ok   ( t1l_ok   ),
    .t0h_addr ( t0h_addr ),
    .t0h_cs   ( t0h_cs   ),
    .t0h_data ( t0h_data ),
    .t0h_ok   ( t0h_ok   ),
    .t1h_addr ( t1h_addr ),
    .t1h_cs   ( t1h_cs   ),
    .t1h_data ( t1h_data ),
    .t1h_ok   ( t1h_ok   ),
    .obj_addr ( obj_addr ),
    .obj_cs   ( obj_cs   ),
    .obj_data ( obj_data ),
    .obj_ok   ( obj_ok   ),
    .ob5_addr ( ob5_addr ),
    .ob5_cs   ( ob5_cs   ),
    .ob5_data ( ob5_data ),
    .ob5_ok   ( ob5_ok   ),
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
