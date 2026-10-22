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
    FE0000-FE7FFF  work RAM, FE8000-FEFFFF shared RAM (the DS5002FP window on protected sets) */

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
    input              dip_pause
);

wire [23:1] A;
wire [23:0] addr = { A, 1'b0 };
wire [ 2:0] FC;
wire        RnW, UDSn, LDSn, ASn, DTACKn, cpu_cen, cpu_cenb, BUSn, VPAn;
wire        IPL6n, ok_dly, int_clr;
reg  [15:0] cpu_din, vregs[2:4];
reg         vregs_cs, in0_cs, in1_cs, coin_cs;

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
    in0_cs   = !BUSn && addr[23:1]  == 23'h180000;              // 300000
    in1_cs   = !BUSn && addr[23:1]  == 23'h180001;              // 300002
    coin_cs  = !BUSn && addr[23:1]  == 23'h190000;              // 320000
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
wire [15:0] cin = { 10'h3ff, service, 1'b1, 2'b11, coin[1], coin[0] };

always @(posedge clk) begin
    cpu_din <= main_cs  ? main_data  :
               vram_cs  ? vram_dout  :
               pal_cs   ? pal_dout   :
               snd_cs   ? snd_dout   :
               wram_cs  ? wram_dout  :
               shram_cs ? shram_dout :
               vregs_cs ? vregs[addr[3:1]] :
               in0_cs   ? in0 :
               in1_cs   ? in1 :
               coin_cs  ? cin : 16'hffff;
end

always @(posedge clk) begin
    if( rst ) begin
        vregs[2] <= 0; vregs[3] <= 0; vregs[4] <= 0;
    end else if( vregs_cs && !RnW ) begin
        if( !UDSn ) vregs[addr[3:1]][15:8] <= cpu_dout[15:8];
        if( !LDSn ) vregs[addr[3:1]][ 7:0] <= cpu_dout[ 7:0];
    end
end

// IRQ 6 on vblank, held until acknowledged (MAME irq6_line_hold)
jtframe_edge #(.QSET(0)) u_irq(
    .rst    ( rst      ),
    .clk    ( clk      ),
    .edgeof ( ~lvbl    ),
    .clr    ( int_clr  ),
    .q      ( IPL6n    )
);

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
    .num        ( 5'd1      ),
    .den        ( 6'd4      ),   // 48 MHz / 4 = 12 MHz
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
    .IPLn       ( { IPL6n, IPL6n, 1'b1 } )   // level 6 = 001
);

endmodule
