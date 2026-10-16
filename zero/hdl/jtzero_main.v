/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Comad Zero Zone board (MAME zerozone.cpp): 68000 at 10 MHz, IRQ 1 at vblank (hold).
 *   000000-01ffff ROM          080000 system, 080002 inputs, 080008 DSW B (high byte), 08000a DSW A (low byte)
 *   084000 sound latch (+Z80 IRQ)   088000-0881ff palette   098000 watchdog?   09c000-09ffff video RAM (map at 09ce00)
 *   0b4001 tile bank           0c0000-0cffff RAM          0f8000-0f87ff RAM
 * Built on JTFRAME by Jose Tejada (jotego). */

module jtzero_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,

    input       [ 7:0] sys,
    input       [15:0] inputs,
    input       [15:0] dipsw,

    output      [15:0] cpu_dout,
    output      [16:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,

    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [10:1] xram_addr,
    output      [ 1:0] xram_we,
    input       [15:0] xram_dout,
    output      [13:1] vram_addr,
    output      [ 1:0] vram_we,
    input       [15:0] vram_dout,
    output      [ 8:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,

    output reg  [ 2:0] tilebank,
    output reg         snd_wr
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
reg         wram_cs, xram_cs, vram_cs, pal_cs, io_cs, bank_cs;

assign dsn       = { uds_n, lds_n };
assign bus_n     = as_n | (lds_n & uds_n);
assign wen       = {2{~wr_n}} & ~dsn;
assign rom_addr  = A[16:1];
assign wram_addr = A[15:1];
assign xram_addr = A[10:1];
assign vram_addr = A[13:1];
assign pal_addr  = A[8:1];
assign wram_we   = wram_cs ? wen : 2'b00;
assign xram_we   = xram_cs ? wen : 2'b00;
assign vram_we   = vram_cs ? wen : 2'b00;
assign pal_we    = pal_cs  ? wen : 2'b00;
assign int_ack   = fc == 3'b111 && !as_n;
assign vpa_n     = !int_ack;
assign ipl_n     = irq_n ? 3'b111 : 3'b110;     // level 1
assign bus_busy  = rom_cs && !rom_ok;

always @* begin
    rom_cs = 0; wram_cs = 0; xram_cs = 0; vram_cs = 0; pal_cs = 0; io_cs = 0; bank_cs = 0;
    if( !bus_n ) begin
        rom_cs  = A[23:17] == 0;                 // 000000-01ffff
        io_cs   = A[23:14] == 10'h020;           // 080000-083fff (inputs)
        pal_cs  = A[23:9]  == 15'h0440;          // 088000-0881ff
        vram_cs = A[23:14] == 10'h027;           // 09c000-09ffff
        bank_cs = A[23:14] == 10'h02d;           // 0b4000
        wram_cs = A[23:16] == 8'h0c;             // 0c0000-0cffff
        xram_cs = A[23:11] == 13'h1f0;           // 0f8000-0f87ff
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs  ? rom_data  :
               wram_cs ? wram_dout :
               xram_cs ? xram_dout :
               vram_cs ? vram_dout :
               pal_cs  ? pal_dout  :
               io_cs   ? ( A[3:1]==0 ? { 8'hff, sys } :
                           A[3:1]==1 ? inputs :
                           A[3:1]==4 ? { dipsw[15:8], 8'hff } :
                           A[3:1]==5 ? { 8'hff, dipsw[7:0] } : 16'hffff ) :
               16'h0000;
end

// sound latch (084000, high byte) and tile bank (0b4001)
always @(posedge clk) begin
    snd_wr <= 0;
    if( rst ) begin
        tilebank <= 0;
    end else begin
        if( !bus_n && !wr_n && A[23:14]==10'h021 && !uds_n ) snd_wr <= 1;   // 084000-087fff
        if( bank_cs && !wr_n && !lds_n ) tilebank <= cpu_dout[2:0];
    end
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

// 10 MHz from 48 MHz
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
    .num       ( 4'd5     ),
    .den       ( 5'd24    ),
    .DTACKn    ( dtack_n  ),
    .wait2     ( 1'b0     ),
    .wait3     ( 1'b0     ),
    .fave      (          ),
    .fworst    (          )
);
`else
initial begin rom_cs=0; tilebank=0; snd_wr=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, xram_addr=0, xram_we=0, vram_addr=0, vram_we=0, pal_addr=0, pal_we=0;
`endif

endmodule
