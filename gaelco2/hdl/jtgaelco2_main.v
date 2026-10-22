/*  This file is part of JTGAELCO2.
    SPDX-License-Identifier: GPL-3.0-or-later
    Gaelco 2 (GAE1 chip) 68000 side, MAME gaelco2.cpp maniacsq_map / alighunt_map.
    The bus logic follows jotego's JTGAE1 (jtgae1_main.v) via our JTWRALLY: jtframe_m68k,
    jtframe_68kdtack_cen, jtframe_edge for the IRQ.

    000000-0FFFFF  program ROM (SDRAM)
    200000-20FFFF  video RAM (sound registers at 202890-2028FF instead)
    210000-211FFF  palette
    218004-218009  video registers (index 2-4)
    300000/300002  IN0 / IN1 (DSW in the high byte), 320000 COIN
    500000         coin lockout + counters (ignored)
    FE0000-FE7FFF  work RAM, FE8000-FEFFFF shared RAM (the DS5002FP window on protected sets)
    Snow Board board (snow=1, MAME snowboar_map): 15 MHz CPU, 212000-213FFF extra RAM, P1 300000, P2 300010,
    COIN 300020 (bit 6 = EEPROM data out), LS259 latch on writes to 300000-30000F (D0, A3-A1 = bit:
    0-1 coin counters, 4 EEPROM DI, 5 CLK, 6 CS), protection 310000-31FFFF (MAME snowboar_protection_r/w).
    Bang! (bang=1, MAME bang_map): Snow Board board without protection; light guns at 310000 (X 1P/2P, then
    Y 1P/2P), a write to 310000 enables the gun interrupt (level 4); the vblank interrupt is level 2. */

module jtgaelco2_main(
    input              clk,
    input              rst,
    input              lvbl,

    output     [19:1]  main_addr,
    output reg         main_cs,
    input      [15:0]  main_data,
    input              main_ok,

    output     [15:0]  cpu_dout,
    output     [15:1]  cpu_addr,
    output     [ 1:0]  cpu_dsn,     // active high byte enables: {upper, lower}
    output             cpu_we,
    // video memories
    output reg         vram_cs, pal_cs, snd_cs,
    input      [15:0]  vram_dout, pal_dout, snd_dout,
    output     [15:0]  vreg0, vreg1, vreg2,
    // work RAM / shared RAM (BRAM in game)
    output reg         wram_cs, shram_cs,
    input      [15:0]  wram_dout, shram_dout,

    input      [15:0]  dipsw,
    input      [ 6:0]  joystick1,
    input      [ 6:0]  joystick2,
    input      [ 1:0]  coin,
    input      [ 1:0]  start,
    input              service,
    input              dip_test,
    input              dip_pause,
    // Snow Board board
    input              snow,
    input              fast,       // 15 MHz CPU (Snow Board), else 12 MHz
    input              bang,       // Bang! light gun board
    input              irq4,       // gun interrupt timing pulse (Bang!)
    output reg         gun_ien,    // gun interrupt enabled by the game (Bang!)
    input      [ 8:0]  gun1_x, gun1_y, gun2_x, gun2_y,   // screen coordinates (JTFRAME light gun)
    output reg         xram_cs,
    input      [15:0]  xram_dout,
    output reg         eep_di, eep_clk, eep_cs,
    input              eep_do
);

wire [23:1] A;
wire [23:0] addr = { A, 1'b0 };
wire [ 2:0] FC;
wire        RnW, UDSn, LDSn, ASn, DTACKn, cpu_cen, cpu_cenb, BUSn, VPAn;
wire        IPL6n, ok_dly, int_clr;
reg  [15:0] cpu_din, vregs[2:4];
reg         prot_l;
reg         vregs_cs, in0_cs, in1_cs, coin_cs, latch_cs, prot_cs, p2_cs, gun_cs;
reg  [31:0] latch;

assign main_addr = A[19:1];
assign cpu_addr  = A[15:1];
assign cpu_dsn   = { ~UDSn, ~LDSn };
assign cpu_we    = ~RnW;
assign BUSn      = ASn | (UDSn & LDSn);
assign VPAn      = ~(~ASn && FC == 3'd7);   // autovector
assign int_clr   = ~ASn && FC == 3'd7;
assign vreg0 = vregs[2], vreg1 = vregs[3], vreg2 = vregs[4];

always @* begin
    main_cs  = !BUSn && addr[23:20] == 4'h0 && RnW;
    snd_cs   = !BUSn && addr[23:16] == 8'h20 && addr[15:8] == 8'h28 && addr[7:1] >= 7'h48; // 202890-2028FF
    vram_cs  = !BUSn && addr[23:16] == 8'h20 && !snd_cs;
    pal_cs   = !BUSn && addr[23:13] == 11'h108;                 // 210000-211FFF
    vregs_cs = !BUSn && addr[23:4]  == 20'h21800 && addr[3:1] >= 3'd2 && addr[3:1] <= 3'd4;
    in0_cs   = !BUSn && addr[23:1]  == 23'h180000;              // 300000 (Snow Board: P1)
    in1_cs   = !BUSn && addr[23:1]  == (snow ? 23'h180008 : 23'h180001); // 300002 (Snow Board: P2 at 300010)
    coin_cs  = !BUSn && addr[23:1]  == (snow ? 23'h180010 : 23'h190000); // 320000 (Snow Board: 300020)
    latch_cs = !BUSn && snow && addr[23:4] == 20'h30000;        // 300000-30000F writes
    prot_cs  = !BUSn && snow && !bang && addr[23:16] == 8'h31;  // 310000-31FFFF
    gun_cs   = !BUSn && bang && addr[23:4] == 20'h31000;        // 310000-31000F
    xram_cs  = !BUSn && snow && addr[23:13] == 11'h109;         // 212000-213FFF
    wram_cs  = !BUSn && addr[23:15] == 9'h1fc;                  // FE0000-FE7FFF
    shram_cs = !BUSn && addr[23:15] == 9'h1fd;                  // FE8000-FEFFFF
end

// MAME ports, all active low (JTFRAME inputs are active low too).
// IN0/IN1 low byte: up, down, right, left, button 1-3, start; high byte DSW1/DSW2
wire [7:0] p1 = { start[0], joystick1[6:4], joystick1[1], joystick1[0], joystick1[2], joystick1[3] };
wire [7:0] p2 = { start[1], joystick2[6:4], joystick2[1], joystick2[0], joystick2[2], joystick2[3] };
wire [15:0] in0 = { dipsw[ 7:0], p1 };
wire [15:0] in1 = { dipsw[15] & dip_test, dipsw[14:8], p2 };   // SW2:8 = service mode
// COIN: coin 1, coin 2, -, -, service 2 (go to test), service 1
wire [15:0] cin = snow ? { 8'hff, 1'b1, eep_do, start[1], start[0], service, dip_test, coin[1], coin[0] } :
                         { 10'h3ff, service, 1'b1, 2'b11, coin[1], coin[0] };
// Snow Board players: no DIPs (EEPROM), start buttons in COIN
wire [15:0] sp1 = { 9'h1ff, joystick1[6:4], joystick1[1], joystick1[0], joystick1[2], joystick1[3] };
wire [15:0] sp2 = { 9'h1ff, joystick2[6:4], joystick2[1], joystick2[0], joystick2[2], joystick2[3] };
// Bang!: trigger = button 1 on bit 7; guns as MAME bang_state::gun_x/gun_y (screen x + 1, screen y - 4)
wire [15:0] bp1 = { 8'h00, joystick1[4], 7'h00 };
wire [15:0] bp2 = { 8'h00, joystick2[4], 7'h00 };
reg  [15:0] gun_q;
always @* case( addr[2:1] )
    2'd0: gun_q = { 7'd0, gun1_x + 9'd1 };
    2'd1: gun_q = { 7'd0, gun2_x + 9'd1 };
    2'd2: gun_q = { {7{gun1_y < 9'd4}}, gun1_y - 9'd4 };
    2'd3: gun_q = { {7{gun2_y < 9'd4}}, gun2_y - 9'd4 };
endcase
// pr_o = MAME mangle(latch) (gaelco2_m.cpp get_lo/get_hi/get_out), generated from MAME's code and checked
// against it on 200 random values
wire [15:0] pr_lo = { latch[6], latch[11], latch[18], latch[20], latch[3], latch[26], latch[14], latch[2], latch[17], latch[0], latch[4], latch[5], latch[30], latch[13], latch[15], latch[23] };
wire [15:0] pr_hi = { latch[31], latch[22], latch[1], latch[12], latch[29], latch[10], latch[19], latch[21], latch[8], latch[27], latch[24], latch[16], latch[7], latch[28], latch[25], latch[9] };
wire [15:0] pr_d  = (pr_lo ^ 16'h0010) - (pr_hi ^ 16'h0024) ^ 16'h5496;
wire [15:0] pr_o = { pr_d[15], pr_d[14], pr_d[0], pr_d[4], pr_d[11], pr_d[1], pr_d[7], pr_d[3], pr_d[13], pr_d[6], pr_d[2], pr_d[12], pr_d[5], pr_d[10], pr_d[8], pr_d[9] };

always @(posedge clk) begin
    cpu_din <= main_cs  ? main_data  :
               vram_cs  ? vram_dout  :
               pal_cs   ? pal_dout   :
               snd_cs   ? snd_dout   :
               wram_cs  ? wram_dout  :
               shram_cs ? shram_dout :
               vregs_cs ? vregs[addr[3:1]] :
               xram_cs  ? xram_dout :
               prot_cs  ? { pr_o[7:0], pr_o[15:8] } :
               gun_cs   ? gun_q :
               in0_cs   ? (bang ? bp1 : snow ? sp1 : in0) :
               in1_cs   ? (bang ? bp2 : snow ? sp2 : in1) :
               coin_cs  ? cin : 16'hffff;
end

always @(posedge clk) begin
    if( rst ) begin
        vregs[2] <= 0; vregs[3] <= 0; vregs[4] <= 0;
        eep_di <= 0; eep_clk <= 0; eep_cs <= 0; latch <= 0; prot_l <= 0; gun_ien <= 0;
    end else begin
        prot_l <= prot_cs & ~RnW;
        if( vregs_cs && !RnW ) begin
            if( !UDSn ) vregs[addr[3:1]][15:8] <= cpu_dout[15:8];
            if( !LDSn ) vregs[addr[3:1]][ 7:0] <= cpu_dout[ 7:0];
        end
        if( latch_cs && !RnW && !LDSn ) case( addr[3:1] )
            3'd4: eep_di  <= cpu_dout[0];
            3'd5: eep_clk <= cpu_dout[0];
            3'd6: eep_cs  <= cpu_dout[0];
            default:;
        endcase
        // MAME: m_snowboard_latch = (latch << 16) | data, once per write
        if( prot_cs && !RnW && !prot_l ) latch <= { latch[15:0], cpu_dout };
        // MAME: a write to 310000 sets m_clr_gun_int, cleared at the vblank interrupt
        if( gun_cs && !RnW && addr[3:1]==0 ) gun_ien <= 1;
        if( vbl_pulse ) gun_ien <= 0;
    end
end

// IRQ 6 on vblank, held until acknowledged (MAME irq6_line_hold). Bang!: vblank on level 2 and the gun
// interrupt on level 4 (MAME bang_irq, HOLD_LINE), each cleared by its own acknowledge cycle.
reg  lvbl_l;
wire vbl_pulse = lvbl_l & ~lvbl;
wire IPL4n;
always @(posedge clk) lvbl_l <= lvbl;

jtframe_edge #(.QSET(0)) u_irq(
    .rst    ( rst      ),
    .clk    ( clk      ),
    .edgeof ( ~lvbl    ),
    .clr    ( int_clr && (bang ? A[3:1]==3'd2 : 1'b1) ),
    .q      ( IPL6n    )
);

jtframe_edge #(.QSET(0)) u_irq4(
    .rst    ( rst      ),
    .clk    ( clk      ),
    .edgeof ( irq4 & gun_ien & bang ),
    .clr    ( int_clr && A[3:1]==3'd4 ),
    .q      ( IPL4n    )
);

// 68000 IPL (active low): level 6 = 001; Bang! level 4 = 011 has priority over level 2 = 101
wire [2:0] ipln = !bang      ? { IPL6n, IPL6n, 1'b1 } :
                  !IPL4n     ? 3'b011 :
                  !IPL6n     ? 3'b101 : 3'b111;

jtframe_okdly #(.W(1)) u_okdly(
    .rst    ( rst      ),
    .clk    ( clk      ),
    .cs     ( main_cs  ),
    .ok     ( main_ok  ),
    .ok_dly ( ok_dly   )
);

jtframe_68kdtack_cen #(.W(6),.RECOVERY(1)) u_dtack(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( main_cs   ),
    .bus_busy   ( main_cs & ~ok_dly ),
    .bus_legit  ( 1'b0      ),
    .bus_ack    ( 1'b0      ),
    .ASn        ( ASn       ),
    .DSn        ( {UDSn,LDSn} ),
    .num        ( fast ? 5'd5 : 5'd1 ),
    .den        ( fast ? 6'd16 : 6'd4 ),   // 48 MHz * 1/4 = 12 MHz; Snow Board 48 * 5/16 = 15 MHz
    .DTACKn     ( DTACKn    ),
    .wait2      ( 1'b0      ),
    .wait3      ( 1'b0      ),
    .fave       (           ),
    .fworst     (           )
);

jtframe_m68k u_cpu(
    .clk        ( clk         ),
    .rst        ( rst         ),
    .RESETn     (             ),
    .cpu_cen    ( cpu_cen     ),
    .cpu_cenb   ( cpu_cenb    ),
    .eab        ( A           ),
    .iEdb       ( cpu_din     ),
    .oEdb       ( cpu_dout    ),
    .eRWn       ( RnW         ),
    .LDSn       ( LDSn        ),
    .UDSn       ( UDSn        ),
    .ASn        ( ASn         ),
    .VPAn       ( VPAn        ),
    .FC         ( FC          ),
    .BERRn      ( 1'b1        ),
    .HALTn      ( dip_pause   ),
    .BRn        ( 1'b1        ),
    .BGACKn     ( 1'b1        ),
    .BGn        (             ),
    .DTACKn     ( DTACKn      ),
    .IPLn       ( ipln        )
);

endmodule
