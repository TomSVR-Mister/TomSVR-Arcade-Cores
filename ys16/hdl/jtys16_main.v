/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 16-bit board without sound CPU (Paparazzi, Shocking, Bomb Kick).
 * Built on JTFRAME by Jose Tejada (jotego). Memory map from MAME's yunsun16.cpp. */

module jtys16_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,

    input       [15:0] inputs,
    input       [ 7:0] sys,
    input       [15:0] dipsw,

    output      [15:0] cpu_dout,
    // SDRAM ROM
    output      [18:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    // BRAM
    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [13:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [13:1] vram0_addr,
    output      [ 1:0] vram0_we,
    input       [15:0] vram0_dout,
    output      [13:1] vram1_addr,
    output      [ 1:0] vram1_we,
    input       [15:0] vram1_dout,
    output      [11:1] objram_addr,
    output      [ 1:0] objram_we,
    input       [15:0] objram_dout,
    // video registers
    output reg  [15:0] scr0x, scr0y, scr1x, scr1y, prio,
    // OKI
    output             oki_wrn,
    input       [ 7:0] oki_dout,
    output reg  [ 1:0] oki_bank
);

`ifndef NOMAIN
wire [23:1] A;
wire [ 2:0] fc;
wire        as_n, lds_n, uds_n, wr_n, dtack_n, vpa_n, bus_n;
wire        cpu_cen, cpu_cenb, int_ack, bus_busy;
wire [ 1:0] dsn, wen;
wire [ 2:0] ipl_n;
reg  [15:0] cpu_din;
reg         irq_n;
reg         wram_cs, pal_cs, vram0_cs, vram1_cs, objram_cs, io_cs;
wire        io_wr = io_cs && !wr_n;

assign dsn        = { uds_n, lds_n };
assign bus_n      = as_n | (lds_n & uds_n);
assign wen        = {2{~wr_n}} & ~dsn;
assign rom_addr   = A[18:1];
assign wram_addr  = A[15:1];
assign pal_addr   = A[13:1];
assign vram0_addr = A[13:1];
assign vram1_addr = A[13:1];
assign objram_addr= A[11:1];
assign wram_we    = wram_cs   ? wen : 2'b00;
assign pal_we     = pal_cs    ? wen : 2'b00;
assign vram0_we   = vram0_cs  ? wen : 2'b00;
assign vram1_we   = vram1_cs  ? wen : 2'b00;
assign objram_we  = objram_cs ? wen : 2'b00;
assign int_ack    = fc == 3'b111 && !as_n;
assign vpa_n      = !int_ack;
assign ipl_n      = irq_n ? 3'b111 : 3'b101;     // level 2
assign bus_busy   = rom_cs && !rom_ok;
assign oki_wrn    = !(io_wr && A[8:1]==8'hc4 && !lds_n);   // 800189

always @* begin
    rom_cs    = 0;
    wram_cs   = 0;
    pal_cs    = 0;
    vram0_cs  = 0;
    vram1_cs  = 0;
    objram_cs = 0;
    io_cs     = 0;
    if( !bus_n ) begin
        rom_cs    = A[23:19] == 0;                  // 000000-07ffff
        io_cs     = A[23:9]  == 15'h4000;           // 800000-8001ff
        pal_cs    = A[23:14] == 10'b1001_0000_00;   // 900000-903fff
        vram1_cs  = A[23:14] == 10'b1001_0000_10;   // 908000-90bfff
        vram0_cs  = A[23:14] == 10'b1001_0000_11;   // 90c000-90ffff
        objram_cs = A[23:12] == 12'h910;            // 910000-910fff
        wram_cs   = A[23:16] == 8'hff;              // ff0000-ffffff
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs    ? rom_data    :
               wram_cs   ? wram_dout   :
               pal_cs    ? pal_dout    :
               vram0_cs  ? vram0_dout  :
               vram1_cs  ? vram1_dout  :
               objram_cs ? objram_dout :
               io_cs     ? ( A[8:1]==8'h00 ? inputs :
                             A[8:1]==8'h0c ? { 8'hff, sys } :
                             A[8:1]==8'h0d ? { 8'hff, dipsw[ 7:0] } :
                             A[8:1]==8'h0e ? { 8'hff, dipsw[15:8] } :
                             A[8:1]==8'hc4 ? { 8'hff, oki_dout } : 16'hffff ) :
               16'hffff;
end

// video registers, OKI bank, interrupt
always @(posedge clk) begin
    if( rst ) begin
        scr0x <= 0; scr0y <= 0; scr1x <= 0; scr1y <= 0; prio <= 0;
        oki_bank <= 0;
    end else if( io_wr ) begin
        case( A[8:1] )
            8'h86: begin if(!uds_n) scr1x[15:8]<=cpu_dout[15:8]; if(!lds_n) scr1x[7:0]<=cpu_dout[7:0]; end // 80010c
            8'h87: begin if(!uds_n) scr1y[15:8]<=cpu_dout[15:8]; if(!lds_n) scr1y[7:0]<=cpu_dout[7:0]; end // 80010e
            8'h8a: begin if(!uds_n) scr0x[15:8]<=cpu_dout[15:8]; if(!lds_n) scr0x[7:0]<=cpu_dout[7:0]; end // 800114
            8'h8b: begin if(!uds_n) scr0y[15:8]<=cpu_dout[15:8]; if(!lds_n) scr0y[7:0]<=cpu_dout[7:0]; end // 800116
            8'haa: begin if(!uds_n) prio[15:8] <=cpu_dout[15:8]; if(!lds_n) prio[7:0] <=cpu_dout[7:0]; end // 800154
            8'hc0: if(!lds_n) oki_bank <= cpu_dout[1:0];                                                   // 800181
            default:;
        endcase
    end
end

// IRQ 2 asserted at the start of vblank, cleared by a write to 8001fe
reg lvbl_l;
always @(posedge clk) begin
    lvbl_l <= lvbl;
    if( rst ) irq_n <= 1;
    else begin
        if( !lvbl && lvbl_l ) irq_n <= 0;
        if( io_wr && A[8:1]==8'hff ) irq_n <= 1;
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
    .IPLn    ( ipl_n     ),
    .FC      ( fc        )
);

// 16 MHz from 48 MHz
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
    .num       ( 4'd1     ),
    .den       ( 5'd3     ),
    .DTACKn    ( dtack_n  ),
    .wait2     ( 1'b0     ),
    .wait3     ( 1'b0     ),
    .fave      (          ),
    .fworst    (          )
);
`else
initial begin rom_cs=0; scr0x=0; scr0y=0; scr1x=0; scr1y=0; prio=0; oki_bank=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, pal_addr=0, pal_we=0, vram0_addr=0, vram0_we=0,
       vram1_addr=0, vram1_we=0, objram_addr=0, objram_we=0, oki_wrn=1;
`endif

endmodule
