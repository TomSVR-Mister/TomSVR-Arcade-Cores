/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gals Pinball / Hot Pinball (Comad) on JTFRAME (Jose Tejada, jotego). Personal build. */

module jtgalpin_game(
    `include "jtframe_game_ports.inc"
);

wire [ 7:0] snd_cmd, in0, in1, sys;
wire        snd_nmi;
wire [ 1:0] pcen;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

// 22.1184 MHz / 2 = 11.0592 MHz pixel clock from 48 MHz (288/625 = 22.1184/48)
jtframe_frac_cen #(.W(2),.WC(10)) u_pxlcen(
    .clk    ( clk           ),
    .n      ( 10'd288       ),
    .m      ( 10'd625       ),
    .cen    ( pcen          ),
    .cenb   (               )
);
assign pxl2_cen = pcen[0];
assign pxl_cen  = pcen[1];

// Inputs (active low unless noted). Button 1 = left flippers, 2 = right flippers,
// 3 = launch/shake left, 4 = launch/shake right
assign in0 = { 2'b11, joystick1[6], joystick1[4], 4'hf };
assign in1 = { 2'b11, joystick1[5], joystick1[7], 4'hf };
assign sys = { 4'hf, 1'b1, cab_1p[0], ~coin[1], ~coin[0] };   // coins active high

jtgalpin_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( LVBL         ),
    .dip_pause   ( dip_pause    ),
    .in0         ( in0          ),
    .in1         ( in1          ),
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
    .objram_addr ( objram_addr  ),
    .objram_we   ( objram_we    ),
    .objram_dout ( objram_dout  ),
    .colram_addr ( colram_addr  ),
    .colram_we   ( colram_we    ),
    .colram_dout ( colram_dout  ),
    .vidram_addr ( vidram_addr  ),
    .vidram_we   ( vidram_we    ),
    .vidram_dout ( vidram_dout  ),
    .bg_addr     ( bg_addr      ),
    .bg_we       ( bg_we        ),
    .bg_dout     ( bg_dout      ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .snd_cmd     ( snd_cmd      ),
    .snd_nmi     ( snd_nmi      )
);

jtgalpin_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen4       ( cen4          ),
    .cen1       ( cen1          ),
    .cmd        ( snd_cmd       ),
    .nmirq      ( snd_nmi       ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .pcm_addr   ( pcm_addr      ),
    .pcm_cs     ( pcm_cs        ),
    .pcm_data   ( pcm_data      ),
    .pcm_ok     ( pcm_ok        ),
    .fm         ( fm            ),
    .pcm        ( pcm           )
);

jtgalpin_video u_video(
    .rst                ( rst               ),
    .clk                ( clk               ),
    .pxl_cen            ( pxl_cen           ),
    .gfx_en             ( gfx_en            ),
    .debug_bus          ( debug_bus         ),
    .vidram_video_addr  ( vidram_video_addr ),
    .vidram_video_dout  ( vidram_video_dout ),
    .colram_video_addr  ( colram_video_addr ),
    .colram_video_dout  ( colram_video_dout ),
    .objram_video_addr  ( objram_video_addr ),
    .objram_video_dout  ( objram_video_dout ),
    .bg_video_addr      ( bg_video_addr     ),
    .bg_video_dout      ( bg_video_dout     ),
    .pal_video_addr     ( pal_video_addr    ),
    .pal_video_dout     ( pal_video_dout    ),
    .fgt_cs             ( fgt_cs            ),
    .fgt_addr           ( fgt_addr          ),
    .fgt_data           ( fgt_data          ),
    .fgt_ok             ( fgt_ok            ),
    .obj_cs             ( obj_cs            ),
    .obj_addr           ( obj_addr          ),
    .obj_data           ( obj_data          ),
    .obj_ok             ( obj_ok            ),
    .LHBL               ( LHBL              ),
    .LVBL               ( LVBL              ),
    .HS                 ( HS                ),
    .VS                 ( VS                ),
    .red                ( red               ),
    .green              ( green             ),
    .blue               ( blue              )
);

endmodule
