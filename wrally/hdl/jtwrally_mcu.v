/*  This file is part of JTWRALLY.
    SPDX-License-Identifier: GPL-3.0-or-later
    World Rally DS5002FP protection CPU (MAME gaelco_ds5002fp.cpp).
    The DS5002FP is an 8051 with its program in a battery-backed 32 kB SRAM. The game
    sets MCON=88 RPCTL=20 at boot, so every MOVX goes to the expanded bus, which is the
    16 kB dual-port RAM shared with the 68000 (address & 3FFF, big endian). The DS
    specific SFRs are not modelled: the program only writes them during start-up. */

module jtwrally_mcu(
    input             rst,
    input             clk,
    input             cen,      // 12 MHz oscillator enable
    // shared RAM (MCU side)
    output     [13:0] x_addr,
    output     [ 7:0] x_dout,
    output            x_wr,
    input      [ 7:0] x_din,
    // program download
    input      [14:0] prog_addr,
    input      [ 7:0] prog_data,
    input             prom_we
);

wire [ 7:0] rom_data, ram_data, ram_q, pre_dout;
wire [15:0] pre_addr, pre_rom;
wire [ 6:0] ram_addr;
wire        ram_we, pre_wr, pre_acc;
reg  [15:0] rom_addr, xa;
reg  [ 7:0] xd;
reg         xw;

assign x_addr = xa[13:0];
assign x_dout = xd;
assign x_wr   = xw;

always @(posedge clk) begin
    xa       <= pre_addr;
    xd       <= pre_dout;
    xw       <= pre_wr & pre_acc;
    rom_addr <= pre_rom;
end

jtframe_dual_ram #(.AW(15),.SIMFILE("mcu.bin")) u_prog(
    .clk0   ( clk       ),
    .data0  ( prog_data ),
    .addr0  ( prog_addr ),
    .we0    ( prom_we   ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( rom_addr[14:0] ),
    .we1    ( 1'b0      ),
    .q1     ( rom_data  )
);

jtframe_ram_rst #(.AW(7),.CEN_RD(1)) u_iram(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .cen    ( cen       ),
    .addr   ( ram_addr  ),
    .data   ( ram_data  ),
    .we     ( ram_we    ),
    .q      ( ram_q     )
);

jt8051 u_mcu(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen       ),
    .int0n      ( 1'b1      ),
    .int1n      ( 1'b1      ),
    .p0_i       ( 8'hff     ),
    .p1_i       ( 8'hff     ),
    .p2_i       ( 8'hff     ),
    .p3_i       ( 8'hff     ),
    .p0_o       (           ),
    .p1_o       (           ),
    .p2_o       (           ),
    .p3_o       (           ),
    .rom_data   ( rom_data  ),
    .rom_addr   ( pre_rom   ),
    .ram_din    ( ram_q     ),
    .ram_dout   ( ram_data  ),
    .ram_addr   ( ram_addr  ),
    .ram_we     ( ram_we    ),
    .x_din      ( x_din     ),
    .x_dout     ( pre_dout  ),
    .x_addr     ( pre_addr  ),
    .x_wr       ( pre_wr    ),
    .x_acc      ( pre_acc   )
);

endmodule
