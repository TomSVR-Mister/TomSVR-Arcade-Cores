/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Playmark Big Twin / Excelsior main board (MAME playmark.cpp bigtwin_main_map / excelsr_main_map): 68000 at 12 MHz,
 * IRQ 2 at vblank (held until acknowledged).
 *   000000-0fffff (Excelsior 2fffff) ROM   440000 sprites   500000 fg tile map (2 words per tile)
 *   Big Twin: 502000-503fff text map (8x8, 64x32)   Excelsior: 501000-501fff text map (16x16, 32x32)
 *   510000-51000b scroll registers   600000-67ffff bitmap (512x512, low byte = pixel)
 *   700010 SYSTEM  700012 P1  700014 P2  700016 coin counters  70001a DSW2  70001c DSW1  70001f sound latch
 *   780000-7807ff palette   ff0000-ffffff RAM
 * hm: Hot Mind (MAME hotmind_main_map), IRQ 6 at vblank:
 *   000000-03ffff ROM   100000 bg map   104000 fg map   108000 text map   110000-11000d scroll / video enable
 *   200000-200fff sprites   280000-2807ff palette   300010 COINS  300012 P1  300014 DISPENSER (bit 6 EEPROM out)
 *   300015 coin counters / EEPROM (bit 0 CS, bit 1 clock, bit 2 data)   30001a DSW2  30001c DSW1  30001f sound latch
 *   ff0000-ffffff RAM. The bg/fg maps only use their first 2 kB (32x32 tiles) and are mirrored.
 * hv (with hm): 1 Hard Times (hrdtimes_main_map): ROM 000000-07ffff and 0c0000-0fffff, RAM 080000-0bffff (the game only
 *   uses its first 64 kB: mirrored), fg map 8 kB, 300014 P2, no EEPROM.
 *   2 Lucky Boom (luckboomh_main_map): 30001c SERVICE (bit 0), no DIP switches or EEPROM.
 *   3 Big Twin No Girls (bigtwinb_main_map): sprites 201000-2013ff, 300014 P2, IRQ 2. */

module jtplaymark_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,
    input              exc,
    input              hm,
    input       [ 1:0] hv,
    input              service,
    input       [ 7:0] disp,        // Hot Mind DISPENSER port
    output reg         eep_cs, eep_clk, eep_di,

    input       [ 7:0] sys, p1, p2, dsw1, dsw2,

    output      [15:0] cpu_dout,
    output      [21:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    // bitmap in SDRAM (CPU copy)
    output      [18:1] bmp_addr,
    output reg         bmp_cs,
    output      [ 1:0] bmp_dsn,
    output             bmp_we,
    input       [15:0] bmp_data,
    input              bmp_ok,
    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [10:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [11:1] oram_addr,
    output      [ 1:0] oram_we,
    input       [15:0] oram_dout,
    output      [12:1] fgram_addr,
    output      [ 1:0] fgram_we,
    input       [15:0] fgram_dout,
    output      [12:1] txram_addr,
    output      [ 1:0] txram_we,
    input       [15:0] txram_dout,
    output      [10:1] bgram_addr,
    output      [ 1:0] bgram_we,
    input       [15:0] bgram_dout,

    output reg  [15:0] scr0, scr1, scr2, scr3, scr4, scr5,
    output reg         ven,         // Hot Mind video enable (scroll register 6 bit 0)
    output reg  [ 7:0] snd_latch,
    output reg         snd_wr,
    output      [21:1] cpu_addr
);

`ifndef NOMAIN
wire [23:1] A;
wire [ 2:0] fc;
wire        as_n, lds_n, uds_n, wr_n, dtack_n, vpa_n, bus_n;
wire        cpu_cen, cpu_cenb, int_ack, bus_busy;
wire [ 1:0] dsn, wen;
reg  [15:0] cpu_din;
reg         wram_cs, pal_cs, oram_cs, fg_cs, tx_cs, io_cs, scr_cs, bg_cs;
reg         irq, lvbl_l, wr_l;
wire [ 7:0] pg = A[23:16];
wire        ht = hv==2'd1, lb = hv==2'd2, bb = hv==2'd3;

assign dsn       = { uds_n, lds_n };
assign bus_n     = as_n | (lds_n & uds_n);
assign wen       = {2{~wr_n}} & ~dsn;
assign rom_addr  = A[21:1];
assign cpu_addr  = A[21:1];
assign bmp_addr  = A[18:1];
assign bmp_dsn   = dsn;
assign bmp_we    = !wr_n;
assign wram_addr = A[15:1];
assign pal_addr  = A[10:1];
assign oram_addr = A[11:1];
assign fgram_addr= A[12:1];
assign txram_addr= exc ? { 1'b0, A[11:1] } : A[12:1];
assign bgram_addr= A[10:1];
assign bgram_we  = bg_cs ? wen : 2'b00;
assign wram_we   = wram_cs ? wen : 2'b00;
assign pal_we    = pal_cs  ? wen : 2'b00;
assign oram_we   = oram_cs ? wen : 2'b00;
assign fgram_we  = fg_cs ? wen : 2'b00;
assign txram_we  = tx_cs ? wen : 2'b00;
assign int_ack   = fc == 3'b111 && !as_n;
assign vpa_n     = !int_ack;
assign bus_busy  = (rom_cs && !rom_ok) || (bmp_cs && !bmp_ok);

always @* begin
    rom_cs = 0; bmp_cs = 0; wram_cs = 0; pal_cs = 0; oram_cs = 0; fg_cs = 0; tx_cs = 0; io_cs = 0; scr_cs = 0; bg_cs = 0;
    if( !bus_n && hm ) begin
        rom_cs  = ht ? A[23:20] == 0 && A[19:18] != 2'b10 : A[23:18] == 0;
        bg_cs   = pg == 8'h10 && A[15:14] == 2'b00;
        fg_cs   = pg == 8'h10 && A[15:14] == 2'b01;
        tx_cs   = pg == 8'h10 && A[15];
        scr_cs  = pg == 8'h11 && A[15:4] == 0;
        oram_cs = pg == 8'h20 && (bb ? A[15:10] == 6'b0001_00 : A[15:12] == 0);
        pal_cs  = pg == 8'h28 && A[15:11] == 0;
        io_cs   = pg == 8'h30 && A[15:5] == 0;
        wram_cs = ht ? A[23:18] == 6'b0000_10 : pg == 8'hff;
    end else if( !bus_n ) begin
        rom_cs  = exc ? A[23:20] < 4'h3 : A[23:20] == 0;
        oram_cs = pg == 8'h44 && A[15:12] == 0;
        fg_cs   = pg == 8'h50 && A[15:12] == 4'h0;
        tx_cs   = exc ? (pg == 8'h50 && A[15:12] == 4'h1) : (pg == 8'h50 && A[15:13] == 3'b001);
        scr_cs  = pg == 8'h51 && A[15:4] == 0;
        bmp_cs  = A[23:19] == 5'b0110_0;            // 600000-67ffff
        io_cs   = pg == 8'h70 && A[15:5] == 0;
        pal_cs  = pg == 8'h78 && A[15:11] == 0;
        wram_cs = pg == 8'hff;
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs  ? rom_data  :
               bmp_cs  ? bmp_data  :
               wram_cs ? wram_dout :
               pal_cs  ? pal_dout  :
               oram_cs ? oram_dout :
               fg_cs   ? fgram_dout :
               tx_cs   ? txram_dout :
               bg_cs   ? bgram_dout :
               io_cs   ? ( A[4:1]==4'h8 ? { 8'hff, sys } : A[4:1]==4'h9 ? { 8'hff, p1 } :
                           A[4:1]==4'ha ? { 8'hff, hm && hv==0 ? disp : hm && lb ? 8'hff : p2 } :
                           A[4:1]==4'hd ? { 8'hff, hm && lb ? 8'hff : dsw2 } :
                           A[4:1]==4'he ? { 8'hff, hm && lb ? { 7'h7f, service } : dsw1 } : 16'hffff ) :
               16'hffff;
end

always @(posedge clk) begin
    snd_wr <= 0;
    wr_l   <= !wr_n && !bus_n;
    lvbl_l <= lvbl;
    if( rst ) begin
        irq <= 0; snd_latch <= 0; ven <= 0; eep_cs <= 0; eep_clk <= 0; eep_di <= 0;
        scr0 <= 0; scr1 <= 0; scr2 <= 0; scr3 <= 0; scr4 <= 0; scr5 <= 0;
    end else begin
        if( !lvbl && lvbl_l && dip_pause ) irq <= 1;
        if( int_ack ) irq <= 0;
        if( hm && hv==0 && io_cs && !wr_n && A[4:1]==4'ha && !lds_n ) begin   // 300015
            eep_cs  <= cpu_dout[0];
            eep_clk <= cpu_dout[1];
            eep_di  <= cpu_dout[2];
        end
        if( io_cs && !wr_n && !wr_l && A[4:1]==4'hf && !lds_n ) begin
            snd_latch <= cpu_dout[7:0];
            snd_wr    <= 1;
        end
        if( scr_cs && !wr_n ) case( A[3:1] )
            0: scr0 <= cpu_dout;
            1: scr1 <= cpu_dout;
            2: scr2 <= cpu_dout;
            3: scr3 <= cpu_dout;
            4: scr4 <= cpu_dout;
            5: scr5 <= cpu_dout;
            6: ven  <= cpu_dout[0];
            default:;
        endcase
    end
end

jtframe_m68k u_cpu(
    .clk     ( clk       ),
    .rst     ( rst       ),
    .cpu_cen ( cpu_cen   ),
    .cpu_cenb( cpu_cenb  ),
    .BERRn   ( 1'b1      ),
    .VPAn    ( vpa_n     ),
    .BGACKn  ( 1'b1      ),
    .HALTn   ( dip_pause ),
    .RESETn  (           ),
    .eab     ( A         ),
    .ASn     ( as_n      ),
    .LDSn    ( lds_n     ),
    .UDSn    ( uds_n     ),
    .eRWn    ( wr_n      ),
    .DTACKn  ( dtack_n   ),
    .iEdb    ( cpu_din   ),
    .oEdb    ( cpu_dout  ),
    .BRn     ( 1'b1      ),
    .BGn     (           ),
    .IPLn    ( irq ? (hm && !bb ? 3'b001 : 3'b101) : 3'b111 ),
    .FC      ( fc        )
);

jtframe_68kdtack_cen u_dtack(
    .rst       ( rst      ),
    .clk       ( clk      ),
    .cpu_cen   ( cpu_cen  ),
    .cpu_cenb  ( cpu_cenb ),
    .bus_cs    ( rom_cs | bmp_cs ),
    .bus_busy  ( bus_busy ),
    .bus_legit ( 1'b0     ),
    .bus_ack   ( 1'b0     ),
    .ASn       ( as_n     ),
    .DSn       ( dsn      ),
    .num       ( 4'd1     ),
    .den       ( 5'd4     ),
    .DTACKn    ( dtack_n  ),
    .wait2     ( 1'b0     ),
    .wait3     ( 1'b0     ),
    .fave      (          ),
    .fworst    (          )
);
`else
initial begin rom_cs=0; bmp_cs=0; snd_latch=0; snd_wr=0; scr0=0; scr1=0; scr2=0; scr3=0; scr4=0; scr5=0; ven=0; eep_cs=0; eep_clk=0; eep_di=0; end
assign cpu_dout=0, cpu_addr=0, rom_addr=0, bmp_addr=0, bmp_dsn=3, bmp_we=0, wram_addr=0, wram_we=0, pal_addr=0, pal_we=0,
       oram_addr=0, oram_we=0, fgram_addr=0, fgram_we=0, txram_addr=0, txram_we=0, bgram_addr=0, bgram_we=0;
`endif

endmodule
