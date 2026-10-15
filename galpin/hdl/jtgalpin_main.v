/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gals Pinball / Hot Pinball (Comad, 1995-96) main CPU board.
 * Built on JTFRAME by Jose Tejada (jotego). Memory map from MAME's galspnbl.cpp. */

module jtgalpin_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,

    input       [ 7:0] in0,
    input       [ 7:0] in1,
    input       [ 7:0] sys,
    input       [15:0] dipsw,

    output      [15:0] cpu_dout,
    // SDRAM ROM
    output      [21:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    // BRAM
    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [11:1] objram_addr,
    output      [ 1:0] objram_we,
    input       [15:0] objram_dout,
    output      [11:1] colram_addr,
    output      [ 1:0] colram_we,
    input       [15:0] colram_dout,
    output      [11:1] vidram_addr,
    output      [ 1:0] vidram_we,
    input       [15:0] vidram_dout,
    output      [17:1] bg_addr,
    output      [ 1:0] bg_we,
    input       [15:0] bg_dout,
    output      [10:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    // sound
    output reg  [ 7:0] snd_cmd,
    output reg         snd_nmi
);

`ifndef NOMAIN
wire [23:1] A;
wire [ 2:0] fc;
wire        as_n, lds_n, uds_n, wr_n, dtack_n, vpa_n, bus_n;
wire        cpu_cen, cpu_cenb, int_ack, irq3_n, bus_busy;
wire [ 1:0] dsn, wen;
wire [ 2:0] ipl_n;
reg  [15:0] cpu_din;
reg         wram_cs, objram_cs, colram_cs, vidram_cs, bg_cs, pal_cs,
            in0_cs, in1_cs, sys_cs, dsw1_cs, dsw2_cs, snd_cs;

assign dsn        = { uds_n, lds_n };
assign bus_n      = as_n | (lds_n & uds_n);
assign wen        = {2{~wr_n}} & ~dsn;
assign rom_addr   = A[21:1];
assign wram_addr  = A[15:1];
assign objram_addr= A[11:1];
assign colram_addr= A[11:1];
assign vidram_addr= A[11:1];
assign bg_addr    = A[17:1];
assign pal_addr   = A[10:1];
assign wram_we    = wram_cs   ? wen : 2'b00;
assign objram_we  = objram_cs ? wen : 2'b00;
assign colram_we  = colram_cs ? wen : 2'b00;
assign vidram_we  = vidram_cs ? wen : 2'b00;
assign bg_we      = bg_cs     ? wen : 2'b00;
assign pal_we     = pal_cs    ? wen : 2'b00;
assign int_ack    = fc == 3'b111 && !as_n;
assign vpa_n      = !int_ack;
assign ipl_n      = irq3_n ? 3'b111 : 3'b100;
assign bus_busy   = rom_cs && !rom_ok;

always @* begin
    rom_cs    = 0;
    wram_cs   = 0;
    objram_cs = 0;
    colram_cs = 0;
    vidram_cs = 0;
    bg_cs     = 0;
    pal_cs    = 0;
    in0_cs    = 0;
    in1_cs    = 0;
    sys_cs    = 0;
    dsw1_cs   = 0;
    dsw2_cs   = 0;
    snd_cs    = 0;
    if( !bus_n ) begin
        rom_cs    = A[23:22] == 2'b00;                      // 000000-3fffff
        wram_cs   = A[23:16] == 8'h70 || A[23:16] == 8'h80; // 700000-70ffff (galspnbl), 800000-80ffff (hotpinbl)
        objram_cs = A[23:12] == 12'h880;                    // 880000-880fff
        colram_cs = A[23:12] == 12'h900;                    // 900000-900fff
        vidram_cs = A[23:12] == 12'h904;                    // 904000-904fff
        bg_cs     = A[23:18] == 6'b1001_10;                 // 980000-9bffff
        pal_cs    = A[23:11] == 13'h1402;                   // a01000-a017ff
        if( A[23:16] == 8'ha8 && A[15:7] == 0 ) begin       // a80000-a8007f
            in0_cs  = A[6:4] == 0;
            in1_cs  = A[6:4] == 1 &&  wr_n;
            snd_cs  = A[6:4] == 1 && !wr_n && !lds_n;
            sys_cs  = A[6:4] == 2;
            dsw1_cs = A[6:4] == 3;
            dsw2_cs = A[6:4] == 4;
        end
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs    ? rom_data    :
               wram_cs   ? wram_dout   :
               objram_cs ? objram_dout :
               colram_cs ? colram_dout :
               vidram_cs ? vidram_dout :
               bg_cs     ? bg_dout     :
               pal_cs    ? pal_dout    :
               in0_cs    ? { 8'hff, in0 } :
               in1_cs    ? { 8'hff, in1 } :
               sys_cs    ? { 8'hff, sys } :
               dsw1_cs   ? { 8'hff, dipsw[ 7:0] } :
               dsw2_cs   ? { 8'hff, dipsw[15:8] } :
               16'hffff;
end

// sound latch: byte write to a80011 raises the Z80 NMI
always @(posedge clk) begin
    if( rst ) begin
        snd_cmd <= 0;
        snd_nmi <= 0;
    end else begin
        snd_nmi <= 0;
        if( snd_cs ) begin
            snd_cmd <= cpu_dout[7:0];
            snd_nmi <= 1;
        end
    end
end

jtframe_edge #(.QSET(0)) u_irq3(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .edgeof ( ~lvbl     ),
    .clr    ( int_ack   ),
    .q      ( irq3_n    )
);

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
    .IPLn    ( ipl_n     ),
    .FC      ( fc        )
);

// 11.0592 MHz from 48 MHz (3/13 = 11.08 MHz)
jtframe_68kdtack_cen u_dtack(
    .rst       ( rst      ),
    .clk       ( clk      ),
    .cpu_cen   ( cpu_cen  ),
    .cpu_cenb  ( cpu_cenb ),
    .bus_cs    ( rom_cs   ),
    .bus_busy  ( bus_busy ),
    .bus_legit ( 1'b0     ),
    .bus_ack   ( 1'b0     ),
    .ASn       ( as_n     ),
    .DSn       ( dsn      ),
    .num       ( 4'd3     ),
    .den       ( 5'd13    ),
    .DTACKn    ( dtack_n  ),
    .wait2     ( 1'b0     ),
    .wait3     ( 1'b0     ),
    .fave      (          ),
    .fworst    (          )
);
`else
initial begin rom_cs=0; snd_cmd=0; snd_nmi=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, objram_addr=0, objram_we=0,
       colram_addr=0, colram_we=0, vidram_addr=0, vidram_we=0, bg_addr=0, bg_we=0,
       pal_addr=0, pal_we=0;
`endif

endmodule
