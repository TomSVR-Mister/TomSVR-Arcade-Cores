/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SemiCom games on the Snow Bros-style board (MAME snowbros.cpp "semiprot"/"semicom" machines) on JTFRAME
 * (Jose Tejada, jotego). Personal build.
 * Header (4 bytes): byte 0 bits 1-0 = 0x200000 read (0 none, 1 = 000a, 2 = 2a2a), bit 2 = protection data at
 *   102000 (Final Tetris), bit 3 = active-low inputs (Final Tetris), bit 4 = MCU writes at 10e000 (Hyper Pacman); byte 1 = background pen (f0, Puzzle Break c0).
 * PROM: 0000 protection data (MAME user1/protdata.bin, big-endian words), 0x200 bytes;
 *       2000 AT89C52 program, 8 kB (Hyper Pacman, Cookie & Bibi 2; zeros for the other sets). */

module jtsemicom_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] in1, in2, sys, prot_data;
wire [ 7:0] snd_latch, prot_addr;
wire [ 8:0] vdump;
wire        snd_wr, hs_start, ocopy;
wire [15:0] mcu_data;
wire [ 7:0] mcu_off;
wire        mcu_req;
reg  [ 1:0] r200, mcu_cnt;
reg         pbase, mbase, alow;
reg  [ 7:0] bg_pen = 8'hf0;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;

always @(posedge clk) if( header && prog_we ) begin
    if( prog_addr[1:0]==0 ) { mbase, alow, pbase, r200 } <= prog_data[4:0];
    if( prog_addr[1:0]==1 ) bg_pen <= prog_data;
end

// DSW in the low byte. High byte, active high (Final Tetris: active low): up, down, left, right, B1, B2, B3
wire [6:0] j1 = { joystick1[6:4], joystick1[0], joystick1[1], joystick1[2], joystick1[3] },
           j2 = { joystick2[6:4], joystick2[0], joystick2[1], joystick2[2], joystick2[3] };
wire [3:0] cs = { coin[1], coin[0], cab_1p[1], cab_1p[0] };
assign in1 = { 1'b0, alow ? j1 : ~j1, dipsw[ 7:0] };
assign in2 = { 1'b0, alow ? j2 : ~j2, dipsw[15:8] };
// SYSTEM high byte: start 1, start 2, coin 1, coin 2, bits 15-12 unused (high)
assign sys = { 4'hf, alow ? cs : ~cs, 8'h00 };

// protection data: even bytes = high byte of each word
jtframe_prom #(.DW(8),.AW(8),.SIMFILE("prot_hi.bin")) u_prot_hi(
    .clk    ( clk               ),
    .cen    ( 1'b1              ),
    .data   ( prog_data         ),
    .rd_addr( prot_addr         ),
    .wr_addr( prog_addr[8:1]    ),
    .we     ( prom_we && !prog_addr[13] && !prog_addr[0] ),
    .q      ( prot_data[15:8]   )
);

jtframe_prom #(.DW(8),.AW(8),.SIMFILE("prot_lo.bin")) u_prot_lo(
    .clk    ( clk               ),
    .cen    ( 1'b1              ),
    .data   ( prog_data         ),
    .rd_addr( prot_addr         ),
    .wr_addr( prog_addr[8:1]    ),
    .we     ( prom_we && !prog_addr[13] && prog_addr[0] ),
    .q      ( prot_data[7:0]    )
);

always @(posedge clk) mcu_cnt <= mcu_cnt + 2'd1;    // 12 MHz

jtsemicom_mcu u_mcu(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( mcu_cnt==0    ),
    .wr_offset  ( mcu_off       ),
    .wr_data    ( mcu_data      ),
    .wr_req     ( mcu_req       ),
    .prog_addr  ( prog_addr[12:0] ),
    .prog_data  ( prog_data     ),
    .prom_we    ( prom_we && prog_addr[13] )
);

jtsemicom_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .vdump       ( vdump        ),
    .hs_start    ( hs_start     ),
    .dip_pause   ( dip_pause    ),
    .r200        ( r200         ),
    .pbase       ( pbase        ),
    .ocopy       ( ocopy        ),
    .mbase       ( mbase        ),
    .mcu_req     ( mcu_req      ),
    .mcu_off     ( mcu_off      ),
    .mcu_data    ( mcu_data     ),
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
    .wram_din    ( wram_din     ),
    .wram_dout   ( wram_dout    ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .oram_addr   ( oram_addr    ),
    .oram_we     ( oram_we      ),
    .oram_din    ( oram_din     ),
    .oram_dout   ( oram_dout    ),
    .prot_addr   ( prot_addr    ),
    .prot_data   ( prot_data    ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       )
);

jtsemicom_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_4      ( cen_4         ),
    .cen_2      ( cen_2         ),
    .cen_1      ( cen_1         ),
    .latch      ( snd_latch     ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .oki_addr   ( oki_addr      ),
    .oki_data   ( oki_data      ),
    .oki_ok     ( oki_ok        ),
    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),
    .pcm        ( pcm           )
);
assign oki_cs = 1'b1;

jtsemicom_video u_video(
    .rst             ( rst             ),
    .clk             ( clk             ),
    .pxl_cen         ( pxl_cen         ),
    .gfx_en          ( gfx_en          ),
    .bg_pen          ( bg_pen          ),
    .ovid_addr       ( ovid_addr       ),
    .ovid_dout       ( ovid_dout       ),
    .ocopy           ( ocopy           ),
    .pal_video_addr  ( pal_video_addr  ),
    .pal_video_dout  ( pal_video_dout  ),
    .gfx_addr        ( gfx_addr        ),
    .gfx_cs          ( gfx_cs          ),
    .gfx_data        ( gfx_data        ),
    .gfx_ok          ( gfx_ok          ),
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
