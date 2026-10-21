/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Playmark Big Twin / Excelsior (MAME playmark.cpp) on JTFRAME (Jose Tejada, jotego). Personal build.
 * Header byte 0: bit 0 Excelsior board (3 MB program, 16x16 text layer and sprites, sprite priorities, 4 OKI banks),
 *   bit 1 Hot Mind (Hard Times board: three tile maps, 93C46 EEPROM, IRQ 6),
 *   bits 3-2 with bit 1: other Hard Times board games: 1 Hard Times, 2 Lucky Boom, 3 Big Twin (No Girls Conversion).
 * The PIC16C57 program is the MAME Intel HEX dump, loaded as the PROM section and decoded by jtplaymark_sound. */

module jtplaymark_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] scr0, scr1, scr2, scr3, scr4, scr5;
wire [ 7:0] snd_latch, sys, p1, p2;
wire [21:1] cpu_addr;
wire        snd_wr, lvbl_irq;
reg         exc = 0, hm = 0;
reg  [ 1:0] hv = 0;
wire        ht = hm && hv==2'd1, bb = hm && hv==2'd3;
wire        eep_cs, eep_clk, eep_di, eep_do, ven;
wire [ 7:0] disp;
reg  [13:0] hex_last;
reg         prom_l;
// prom_we stays high for several clocks per byte: take each PROM byte once
wire        hex_we = prom_we && (!prom_l || prog_addr[13:0] != hex_last);

always @(posedge clk) begin
    prom_l <= prom_we;
    if( prom_we ) hex_last <= prog_addr[13:0];
end

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
always @(posedge clk) if( header && prog_we ) begin
    if( prog_addr[1:0]==0 ) { hv, hm, exc } <= prog_data[3:0];
end

// SYSTEM: coin 1 bit 4, coin 2 bit 5   P1/P2: up, down, left, right, B1, B2, B3, start (all active low)
assign sys = { 2'b11, coin[1], coin[0], 4'hf };
// Big Twin No Girls: right, left, down, up
assign p1  = { cab_1p[0], joystick1[6:4], bb ? joystick1[3:0] : { joystick1[0], joystick1[1], joystick1[2], joystick1[3] } };
assign p2  = { cab_1p[1], joystick2[6:4], bb ? joystick2[3:0] : { joystick2[0], joystick2[1], joystick2[2], joystick2[3] } };
// jt9346 reports ready as soon as CS rises again after a write; the 93C46 (and MAME) stays busy (DO low) for the
// write cycle, and Hot Mind waits for DO to go low and then high. Hold DO low for 1.75 ms (MAME's write time).
wire        eep_wflag;
reg  [16:0] eep_bcnt;
wire        eep_busy = eep_bcnt != 0;

always @(posedge clk) begin
    if( rst ) eep_bcnt <= 0;
    else if( eep_wflag ) eep_bcnt <= 17'd84_000;   // 1.75 ms at 48 MHz
    else if( eep_busy ) eep_bcnt <= eep_bcnt - 1'd1;
end

// jt9346 only takes a start bit when DI rises between clocks, so a command that follows a word ending in 1 is missed.
// One extra clock with DI low when CS rises (ignored while the chip waits for the start bit) clears that state.
reg  [2:0] eep_inj;
reg        eep_csl;
wire       eep_sclk = eep_clk | eep_inj[1];
wire       eep_sdi  = eep_di & ~|eep_inj;

always @(posedge clk) begin
    eep_csl <= eep_cs;
    eep_inj <= eep_cs && !eep_csl ? 3'b111 : eep_inj >> 1;
end

// Hot Mind DISPENSER: bit 6 EEPROM data, ticket/token dispensers idle and not empty
assign disp = { 1'b1, eep_do & ~eep_busy, 1'b1, 1'b0, 1'b1, 1'b0, 2'b11 };

jt9346 #(.AW(6),.DW(16)) u_eeprom(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .sclk       ( eep_sclk  ),
    .sdi        ( eep_sdi   ),
    .sdo        ( eep_do    ),
    .scs        ( eep_cs    ),
    .dump_clk   ( clk       ),
    .dump_addr  ( 6'd0      ),
    .dump_we    ( 1'b0      ),
    .dump_din   ( 16'd0     ),
    .dump_dout  (           ),
    .dump_clr   ( eep_wflag ),
    .dump_flag  ( eep_wflag )
);

jtplaymark_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( lvbl_irq     ),
    .dip_pause   ( dip_pause    ),
    .exc         ( exc          ),
    .hm          ( hm           ),
    .hv          ( hv           ),
    .service     ( service      ),
    .disp        ( disp         ),
    .eep_cs      ( eep_cs       ),
    .eep_clk     ( eep_clk      ),
    .eep_di      ( eep_di       ),
    .sys         ( sys          ),
    .p1          ( p1           ),
    .p2          ( p2           ),
    .dsw1        ( dipsw[ 7:0]  ),
    .dsw2        ( dipsw[15:8]  ),
    .cpu_dout    ( cpu_dout     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .bmp_addr    ( bmp_addr     ),
    .bmp_cs      ( bmp_cs       ),
    .bmp_dsn     ( bmp_dsn      ),
    .bmp_we      ( bmp_we       ),
    .bmp_data    ( bmp_data     ),
    .bmp_ok      ( bmp_ok       ),
    .wram_addr   ( wram_addr    ),
    .wram_we     ( wram_we      ),
    .wram_dout   ( wram_dout    ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .oram_addr   ( oram_addr    ),
    .oram_we     ( oram_we      ),
    .oram_dout   ( oram_dout    ),
    .fgram_addr  ( fgram_addr   ),
    .fgram_we    ( fgram_we     ),
    .fgram_dout  ( fgram_dout   ),
    .txram_addr  ( txram_addr   ),
    .txram_we    ( txram_we     ),
    .txram_dout  ( txram_dout   ),
    .bgram_addr  ( bgram_addr   ),
    .bgram_we    ( bgram_we     ),
    .bgram_dout  ( bgram_dout   ),
    .scr0        ( scr0         ),
    .scr1        ( scr1         ),
    .scr2        ( scr2         ),
    .scr3        ( scr3         ),
    .scr4        ( scr4         ),
    .scr5        ( scr5         ),
    .ven         ( ven          ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       ),
    .cpu_addr    ( cpu_addr     )
);


jtplaymark_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_pic    ( cen_3         ),
    .cen_oki    ( cen_1         ),
    .nbank      ( exc || ht ? 2'd3 : 2'd1 ),
    .hm         ( hm & ~bb      ),
    .ht         ( ht            ),
    .hex_we     ( hex_we        ),
    .hex_data   ( prog_data     ),
    .hex_first  ( prog_addr[13:0]==0 ),
    .latch      ( snd_latch     ),
    .snd_wr     ( snd_wr        ),
    .rom_addr   ( oki_addr      ),
    .rom_data   ( oki_data      ),
    .rom_ok     ( oki_ok        ),
    .pcm        ( pcm           )
);
assign oki_cs = 1'b1;

jtplaymark_video u_video(
    .rst              ( rst              ),
    .clk              ( clk              ),
    .pxl_cen          ( pxl_cen          ),
    .exc              ( exc              ),
    .hm               ( hm               ),
    .hv               ( hv               ),
    .ven              ( ven              ),
    .gfx_en           ( gfx_en           ),
    .scr0             ( scr0             ),
    .scr1             ( scr1             ),
    .scr2             ( scr2             ),
    .scr3             ( scr3             ),
    .scr4             ( scr4             ),
    .scr5             ( scr5             ),
    .cpu_addr         ( cpu_addr         ),
    .cpu_dout         ( cpu_dout         ),
    .oram_we          ( oram_we          ),
    .bmp_wr           ( bmp_cs && bmp_we && !bmp_dsn[0] ),
    .fgram_video_addr ( fgram_video_addr ),
    .fgram_video_dout ( fgram_video_dout ),
    .txram_video_addr ( txram_video_addr ),
    .txram_video_dout ( txram_video_dout ),
    .bgram_video_addr ( bgram_video_addr ),
    .bgram_video_dout ( bgram_video_dout ),
    .pal_video_addr   ( pal_video_addr   ),
    .pal_video_dout   ( pal_video_dout   ),
    .fg_addr          ( fg_addr          ),
    .fg_cs            ( fg_cs            ),
    .fg_data          ( fg_data          ),
    .fg_ok            ( fg_ok            ),
    .tx_addr          ( tx_addr          ),
    .tx_cs            ( tx_cs            ),
    .tx_data          ( tx_data          ),
    .tx_ok            ( tx_ok            ),
    .bg_addr          ( bg_addr          ),
    .bg_cs            ( bg_cs            ),
    .bg_data          ( bg_data          ),
    .bg_ok            ( bg_ok            ),
    .obj_addr         ( obj_addr         ),
    .obj_cs           ( obj_cs           ),
    .obj_data         ( obj_data         ),
    .obj_ok           ( obj_ok           ),
    .lvbl_irq         ( lvbl_irq         ),
    .LHBL             ( LHBL             ),
    .LVBL             ( LVBL             ),
    .HS               ( HS               ),
    .VS               ( VS               ),
    .red              ( red              ),
    .green            ( green            ),
    .blue             ( blue             )
);

endmodule
