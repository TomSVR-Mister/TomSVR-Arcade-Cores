/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Afega boards with an 8 bpp background (MAME nmk16.cpp "popspops" machine: Bubble 2000, Hot Bubble, Pop's Pop's, Mang-Chi)
 * on JTFRAME (Jose Tejada, jotego). Personal build.
 * Header byte 0: bits 1-0 program ROM address scramble (1 Bubble 2000 / Hot Bubble / Mang-Chi, 2 Pop's Pop's),
 *   bits 3-2 background tiles (0: 12288, 1: 16384, 2: 4096), bit 4 8192 sprite tiles (else 4096), bit 5 no sprite ROM. */

module jtafega_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] bg_scrx, bg_scry, tx_scrx, tx_scry;
wire [ 7:0] snd_latch;
wire [15:0] in0, in1;
wire [ 8:0] vdump;
wire        snd_wr, hs_start;
reg  [ 1:0] scr = 0, tmod = 0;
reg         omask = 0, nospr = 0;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
always @(posedge clk) if( header && prog_we ) begin
    if( prog_addr[1:0]==0 ) { nospr, omask, tmod, scr } <= prog_data[5:0];
end

// IN0: coin 1, coin 2, service, start 1, start 2   IN1: P1 right, left, down, up, B1, B2 (low byte), P2 (high byte)
assign in0 = { 8'hff, 3'b111, cab_1p[1], cab_1p[0], service, coin[1], coin[0] };
assign in1 = { 2'b11, joystick2[5:0], 2'b11, joystick1[5:0] };

jtafega_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .vdump       ( vdump        ),
    .hs_start    ( hs_start     ),
    .dip_pause   ( dip_pause    ),
    .scr         ( scr          ),
    .in0         ( in0          ),
    .in1         ( in1          ),
    .dsw         ( dipsw[15:0]  ),
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
    .bgram_addr  ( bgram_addr   ),
    .bgram_we    ( bgram_we     ),
    .bgram_dout  ( bgram_dout   ),
    .txram_addr  ( txram_addr   ),
    .txram_we    ( txram_we     ),
    .txram_dout  ( txram_dout   ),
    .bg_scrx     ( bg_scrx      ),
    .bg_scry     ( bg_scry      ),
    .tx_scrx     ( tx_scrx      ),
    .tx_scry     ( tx_scry      ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       )
);

jtafega_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_4      ( cen_4         ),
    .cen_2      ( cen_2         ),
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
    .opm_l      ( opm_l         ),
    .opm_r      ( opm_r         ),
    .pcm        ( pcm           )
);
assign oki_cs = 1'b1;

jtafega_video u_video(
    .rst                ( rst               ),
    .clk                ( clk               ),
    .pxl_cen            ( pxl_cen           ),
    .gfx_en             ( gfx_en            ),
    .tmod               ( tmod              ),
    .omask              ( omask             ),
    .oen                ( ~nospr            ),
    .bg_scrx            ( bg_scrx           ),
    .bg_scry            ( bg_scry           ),
    .tx_scrx            ( tx_scrx           ),
    .tx_scry            ( tx_scry           ),
    .bgram_video_addr   ( bgram_video_addr  ),
    .bgram_video_dout   ( bgram_video_dout  ),
    .txram_video_addr   ( txram_video_addr  ),
    .txram_video_dout   ( txram_video_dout  ),
    .wram_video_addr    ( wram_video_addr   ),
    .wram_video_dout    ( wram_video_dout   ),
    .pal_video_addr     ( pal_video_addr    ),
    .pal_video_dout     ( pal_video_dout    ),
    .bg_addr  ( bg_addr  ),
    .bg_cs    ( bg_cs    ),
    .bg_data  ( bg_data  ),
    .bg_ok    ( bg_ok    ),
    .tx_addr  ( tx_addr  ),
    .tx_cs    ( tx_cs    ),
    .tx_data  ( tx_data  ),
    .tx_ok    ( tx_ok    ),
    .obj_addr ( obj_addr ),
    .obj_cs   ( obj_cs   ),
    .obj_data ( obj_data ),
    .obj_ok   ( obj_ok   ),
    .vdump              ( vdump             ),
    .hs_start           ( hs_start          ),
    .LHBL               ( LHBL              ),
    .LVBL               ( LVBL              ),
    .HS                 ( HS                ),
    .VS                 ( VS                ),
    .red                ( red               ),
    .green              ( green             ),
    .blue               ( blue              )
);

endmodule
