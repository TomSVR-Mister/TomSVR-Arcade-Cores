/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SemiCom AT89C52 protection MCU (MAME snowbros.cpp semicom_mcu: Hyper Pacman, Cookie & Bibi 2).
 * After reset the program checksums itself to find its data, then writes 256 words into the 68000 RAM:
 * P2 = word offset, P1 = high byte, P0 = low byte, then pulses P3 (TXD, RXD, INT0 low and high again).
 * MAME writes the RAM on every P0/P1 write; here the word is written when INT0 (P3.2) goes low, after P0-P2 are
 * set, which stores the same data. Runs at 12 MHz (MAME: 16 MHz); it only does this one copy at power up.
 * The jt8051 outputs change on cen and are taken two clocks later (as in jtwrally_mcu). */

module jtsemicom_mcu(
    input             rst,
    input             clk,
    input             cen,      // 12 MHz oscillator enable, every fourth clock
    // RAM write request
    output reg [ 7:0] wr_offset,
    output reg [15:0] wr_data,
    output reg        wr_req,
    // program download
    input      [12:0] prog_addr,
    input      [ 7:0] prog_data,
    input             prom_we
);

wire [ 7:0] rom_data, ram_data, ram_q, p0, p1, p2, p3;
wire [15:0] pre_rom;
wire [ 6:0] ram_addr;
wire        ram_we;
reg  [12:0] rom_addr;
reg  [ 1:0] cen_dly;
reg         int0_l;

always @(posedge clk) begin
    cen_dly <= { cen_dly[0], cen };
    wr_req  <= 0;
    if( cen_dly[1] ) begin
        rom_addr <= pre_rom[12:0];
        int0_l   <= p3[2];
        if( int0_l && !p3[2] ) begin
            wr_offset <= p2;
            wr_data   <= { p1, p0 };
            wr_req    <= 1;
        end
    end
    if( rst ) int0_l <= 1;
end

jtframe_dual_ram #(.AW(13),.SIMFILE("mcu.bin")) u_prog(
    .clk0   ( clk       ),
    .data0  ( prog_data ),
    .addr0  ( prog_addr ),
    .we0    ( prom_we   ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( rom_addr  ),
    .we1    ( 1'b0      ),
    .q1     ( rom_data  )
);

jtframe_ram_rst #(.AW(7),.CEN_RD(1)) u_ramu(
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
    .p0_o       ( p0        ),
    .p1_o       ( p1        ),
    .p2_o       ( p2        ),
    .p3_o       ( p3        ),
    .rom_data   ( rom_data  ),
    .rom_addr   ( pre_rom   ),
    .ram_din    ( ram_q     ),
    .ram_dout   ( ram_data  ),
    .ram_addr   ( ram_addr  ),
    .ram_we     ( ram_we    ),
    .x_din      ( 8'hff     ),
    .x_dout     (           ),
    .x_addr     (           ),
    .x_wr       (           ),
    .x_acc      (           )
);

endmodule
