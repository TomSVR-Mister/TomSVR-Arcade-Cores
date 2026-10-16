/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Min Corp. Gumbo / Miss Puzzle / Miss Bingo / Double Point on JTFRAME (Jose Tejada, jotego). Personal build. */

module jtgumbo_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] inputs;
wire [ 7:0] oki_dout;
wire        vbl_irq, oki_wrn;
// header byte 0 = memory map (0 Gumbo, 1 Miss Puzzle/Bingo, 2 Double Point), byte 1 = { fg big, bg big }
reg  [ 1:0] mapsel = 0;
reg         bgbig = 0, fgbig = 0;
wire        dbl = mapsel==2;
wire [ 7:0] p1, p2;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

always @(posedge clk) if( header && prog_we ) begin
    if( prog_addr[1:0]==0 ) mapsel <= prog_data[1:0];
    if( prog_addr[1:0]==1 ) { fgbig, bgbig } <= prog_data[1:0];
end

// Gumbo: coin, -, button 1 (also start), button 2, up, down, left, right
// Double Point: coin, button 1, button 2 (also start), button 3, up, down, left, right
assign p1 = dbl ? { joystick1[0], joystick1[1], joystick1[2], joystick1[3], joystick1[6], joystick1[5] & cab_1p[0], joystick1[4], coin[0] }
                : { joystick1[0], joystick1[1], joystick1[2], joystick1[3], joystick1[5], joystick1[4] & cab_1p[0], 1'b1, coin[0] };
assign p2 = dbl ? { joystick2[0], joystick2[1], joystick2[2], joystick2[3], joystick2[6], joystick2[5] & cab_1p[1], joystick2[4], 1'b1 }
                : { joystick2[0], joystick2[1], joystick2[2], joystick2[3], joystick2[5], joystick2[4] & cab_1p[1], 1'b1, 1'b1 };
assign inputs = { p2, p1 };

jtgumbo_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( vbl_irq      ),
    .dip_pause   ( dip_pause    ),
    .mapsel      ( mapsel       ),
    .inputs      ( inputs       ),
    .dsw         ( dipsw[7:0]   ),
    .cpu_dout    ( cpu_dout     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .wram_addr   ( wram_addr    ),
    .wram_we     ( wram_we      ),
    .wram_dout   ( wram_dout    ),
    .bgram_addr  ( bgram_addr   ),
    .bgram_we    ( bgram_we     ),
    .bgram_dout  ( bgram_dout   ),
    .fgram_addr  ( fgram_addr   ),
    .fgram_we    ( fgram_we     ),
    .fgram_dout  ( fgram_dout   ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .oki_wrn     ( oki_wrn      ),
    .oki_dout    ( oki_dout     )
);

assign oki_cs = 1'b1;
jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst           ),
    .clk      ( clk           ),
    .cen      ( cen_oki       ),
    .ss       ( 1'b1          ),
    .wrn      ( oki_wrn       ),
    .din      ( cpu_dout[7:0] ),
    .dout     ( oki_dout      ),
    .rom_addr ( oki_addr      ),
    .rom_data ( oki_data      ),
    .rom_ok   ( oki_ok        ),
    .sound    ( pcm           ),
    .sample   (               )
);

jtgumbo_video u_video(
    .rst              ( rst              ),
    .clk              ( clk              ),
    .pxl_cen          ( pxl_cen          ),
    .gfx_en           ( gfx_en           ),
    .bgbig            ( bgbig            ),
    .fgbig            ( fgbig            ),
    .bgram_video_addr ( bgram_video_addr ),
    .bgram_video_dout ( bgram_video_dout ),
    .fgram_video_addr ( fgram_video_addr ),
    .fgram_video_dout ( fgram_video_dout ),
    .pal_video_addr   ( pal_video_addr   ),
    .pal_video_dout   ( pal_video_dout   ),
    .bgt_addr         ( bgt_addr         ),
    .bgt_cs           ( bgt_cs           ),
    .bgt_data         ( bgt_data         ),
    .bgt_ok           ( bgt_ok           ),
    .fgt_addr         ( fgt_addr         ),
    .fgt_cs           ( fgt_cs           ),
    .fgt_data         ( fgt_data         ),
    .fgt_ok           ( fgt_ok           ),
    .vbl_irq          ( vbl_irq          ),
    .LHBL             ( LHBL             ),
    .LVBL             ( LVBL             ),
    .HS               ( HS               ),
    .VS               ( VS               ),
    .red              ( red              ),
    .green            ( green            ),
    .blue             ( blue             )
);

endmodule
