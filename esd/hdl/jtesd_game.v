/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * ESD 16-bit boards (MAME esd16.cpp: Head Panic, Multi Champ, Multi Champ Deluxe, Deluxe 5, Tang Tang, Jumping Pop)
 * on JTFRAME (Jose Tejada, jotego). Personal build.
 * Header byte 0: bits 2-0 memory map (0 Head Panic, 1 Multi Champ Deluxe, 2 Tang Tang / Deluxe 5, 3 Multi Champ, 4 Jumping Pop),
 *   bit 3 sprite offsets of the ESD 08-26-1999 PCB (x - 0x18, y - 0x100),
 *   bits 5-4 sprite tiles (0: 32768, 1: 8192, 2: 16384), bit 6 EEPROM default stored big-endian (.nv file),
 *   bit 7 2 MB tile ROM. */

module jtesd_game(
    `include "jtframe_game_ports.inc"
);

wire [ 9:0] scr0x, scr0y, scr1x, scr1y;
wire [ 1:0] lsize;
wire [ 1:0] col0;
wire [ 7:0] snd_latch;
wire [15:0] inputs, system;
wire        snd_wr, vbl_irq, nv_dout;
reg  [ 2:0] gmap = 0;
reg  [ 1:0] osize = 0;
reg         soff = 0, nvbe = 0, t2m = 0;
wire        jp = gmap==3'd4;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
always @(posedge clk) if( header && prog_we && !ioctl_ram ) begin
    if( prog_addr[1:0]==0 ) { t2m, nvbe, osize, soff, gmap } <= prog_data;
end

// active low: up, down, left, right, button 1, button 2 (P1 low byte, P2 high byte)
assign inputs = { 2'b11, joystick2[5:4], joystick2[0], joystick2[1], joystick2[2], joystick2[3],
                  2'b11, joystick1[5:4], joystick1[0], joystick1[1], joystick1[2], joystick1[3] };
// 0 coin 1, 1 coin 2, 2 start 1, 3 start 2, 4 service coin, 6 test (EEPROM boards)
assign system = { 9'h1ff, jp || gmap==3 ? 1'b1 : dip_test, 1'b1, service, cab_1p[1], cab_1p[0], coin[1], coin[0] };

jtesd_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( vbl_irq      ),
    .dip_pause   ( dip_pause    ),
    .gmap        ( gmap         ),
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
    .vram1_din   ( vram1_din    ),
    .vram1_dout  ( vram1_dout   ),
    .scr0x       ( scr0x        ),
    .scr0y       ( scr0y        ),
    .scr1x       ( scr1x        ),
    .scr1y       ( scr1y        ),
    .lsize       ( lsize        ),
    .col0        ( col0         ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       ),
    // EEPROM default / save
    .nvbe        ( nvbe         ),
    .prog_addr   ( prog_addr[7:0] ),
    .prog_data   ( prog_data    ),
    .prog_we     ( prog_we && ioctl_ram ),
    .prog_din    ( ioctl_din    )
);

jtesd_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_snd    ( jp ? cen_35  : cen_4 ),
    .cen_oki    ( jp ? cen_875 : cen_1 ),
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

jtesd_video u_video(
    .rst                ( rst               ),
    .clk                ( clk               ),
    .pxl_cen            ( pxl_cen           ),
    .gfx_en             ( gfx_en            ),
    .jp                 ( jp                ),
    .soff               ( soff              ),
    .osize              ( osize             ),
    .t2m                ( t2m               ),
    .lsize              ( lsize             ),
    .col0               ( col0              ),
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
    .pal_video_addr     ( pal_video_addr    ),
    .pal_video_dout     ( pal_video_dout    ),
    .t0_addr  ( t0_addr  ),
    .t0_cs    ( t0_cs    ),
    .t0_data  ( t0_data  ),
    .t0_ok    ( t0_ok    ),
    .t1_addr  ( t1_addr  ),
    .t1_cs    ( t1_cs    ),
    .t1_data  ( t1_data  ),
    .t1_ok    ( t1_ok    ),
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
