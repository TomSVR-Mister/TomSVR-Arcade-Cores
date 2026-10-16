/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Min Corp. board (MAME gumbo.cpp): 68000 at 7.16 MHz, IRQ 1 at vblank (hold). Three memory maps (header):
 *   0 Gumbo:    ROM 000000, RAM 080000-083fff, palette 1b0000, I/O 1c0100/1c0200/1c0301, bg 1e0000, fg 1f0000
 *   1 Miss Puzzle / Miss Bingo: ROM, RAM 100000, fg 190000, palette 1a0000, I/O 1b0xxx, bg 1c0000
 *   2 Double Point: ROM, RAM 080000, palette 1b0000 (write only), I/O 1c0xxx, fg 1e0000, bg 1f0000
 * Built on JTFRAME by Jose Tejada (jotego). */

module jtgumbo_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,
    input       [ 1:0] mapsel,

    input       [15:0] inputs,
    input       [ 7:0] dsw,

    output      [15:0] cpu_dout,
    output      [18:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,

    output      [13:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [12:1] bgram_addr,
    output      [ 1:0] bgram_we,
    input       [15:0] bgram_dout,
    output      [14:1] fgram_addr,
    output      [ 1:0] fgram_we,
    input       [15:0] fgram_dout,
    output      [ 9:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,

    output             oki_wrn,
    input       [ 7:0] oki_dout
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
reg         wram_cs, bgram_cs, fgram_cs, pal_cs, io_cs;
wire        in_cs  = io_cs && A[11:8]==4'h1;
wire        dsw_cs = io_cs && A[11:8]==4'h2;
wire        oki_cs = io_cs && A[11:8]==4'h3;

assign dsn        = { uds_n, lds_n };
assign bus_n      = as_n | (lds_n & uds_n);
assign wen        = {2{~wr_n}} & ~dsn;
assign rom_addr   = A[18:1];
assign wram_addr  = A[13:1];
assign bgram_addr = A[12:1];
assign fgram_addr = A[14:1];
assign pal_addr   = A[9:1];
assign wram_we    = wram_cs  ? wen : 2'b00;
assign bgram_we   = bgram_cs ? wen : 2'b00;
assign fgram_we   = fgram_cs ? wen : 2'b00;
assign pal_we     = pal_cs   ? wen : 2'b00;
assign oki_wrn    = !(oki_cs && !wr_n && !lds_n);
assign int_ack    = fc == 3'b111 && !as_n;
assign vpa_n      = !int_ack;
assign ipl_n      = irq_n ? 3'b111 : 3'b110;     // level 1
assign bus_busy   = rom_cs && !rom_ok;

always @* begin
    rom_cs = 0; wram_cs = 0; bgram_cs = 0; fgram_cs = 0; pal_cs = 0; io_cs = 0;
    if( !bus_n ) begin
        rom_cs = A[23:19] == 0;                                  // 000000-07ffff
        case( mapsel )
            1: begin    // Miss Puzzle / Miss Bingo
                wram_cs  = A[23:14] == 10'h040;                  // 100000-103fff
                fgram_cs = A[23:15] == 9'h032;                   // 190000-197fff
                pal_cs   = A[23:10] == 14'h0680;                 // 1a0000-1a03ff
                io_cs    = A[23:12] == 12'h1b0;                  // 1b0xxx
                bgram_cs = A[23:13] == 11'h0e0;                  // 1c0000-1c1fff
            end
            2: begin    // Double Point
                wram_cs  = A[23:14] == 10'h020;                  // 080000-083fff
                pal_cs   = A[23:10] == 14'h06c0;                 // 1b0000-1b03ff
                io_cs    = A[23:12] == 12'h1c0;                  // 1c0xxx
                fgram_cs = A[23:14] == 10'h078;                  // 1e0000-1e3fff
                bgram_cs = A[23:12] == 12'h1f0;                  // 1f0000-1f0fff
            end
            default: begin  // Gumbo
                wram_cs  = A[23:14] == 10'h020;                  // 080000-083fff
                pal_cs   = A[23:10] == 14'h06c0;                 // 1b0000-1b03ff
                io_cs    = A[23:12] == 12'h1c0;                  // 1c0xxx
                bgram_cs = A[23:12] == 12'h1e0;                  // 1e0000-1e0fff
                fgram_cs = A[23:14] == 10'h07c;                  // 1f0000-1f3fff
            end
        endcase
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs   ? rom_data   :
               wram_cs  ? wram_dout  :
               bgram_cs ? bgram_dout :
               fgram_cs ? fgram_dout :
               pal_cs   ? (mapsel==2 ? 16'h0000 : pal_dout) :
               in_cs    ? inputs     :
               dsw_cs   ? { dsw, 8'hff } :
               oki_cs   ? { 8'hff, oki_dout } :
               16'h0000;
end

// IRQ 1 at the start of vblank, cleared on acknowledge
reg lvbl_l;
always @(posedge clk) begin
    lvbl_l <= lvbl;
    if( rst ) irq_n <= 1;
    else begin
        if( !lvbl && lvbl_l ) irq_n <= 0;
        if( int_ack ) irq_n <= 1;
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

// 7.2 MHz from 48 MHz (board: 14.318 MHz / 2)
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
    .den       ( 5'd20    ),
    .DTACKn    ( dtack_n  ),
    .wait2     ( 1'b0     ),
    .wait3     ( 1'b0     ),
    .fave      (          ),
    .fworst    (          )
);
`else
initial rom_cs=0;
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, bgram_addr=0, bgram_we=0, fgram_addr=0, fgram_we=0,
       pal_addr=0, pal_we=0, oki_wrn=1;
`endif

endmodule
