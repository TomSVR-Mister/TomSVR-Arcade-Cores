/*  This file is part of JTGAELCO2.
    SPDX-License-Identifier: GPL-3.0-or-later
    DS5002FP protection CPU of the protected Gaelco 2 sets (MAME gaelco_ds5002fp.cpp), from our JTWRALLY.
    The DS5002FP is an 8051 whose program sits in a battery-backed 32 kB SRAM. Maniac Square never writes
    MCON/RPCTL, so the defaults stored with the dump apply (MCON=19, RPCTL=00): partitioned mode, partition
    0x1000, range 0x7fff. MOVX to 1000-7FFF reaches the SRAM itself (MAME: the games use it as scratch
    memory); 8000-FFFF is the window into the 68000 shared RAM (big endian); 0000-0FFF is open.
    The SRAM is one dual-port RAM: port 0 = download (clk96, while the game is held in reset) or the MCU's
    data accesses, port 1 = instruction fetch. */

module jtgaelco2_mcu(
    input             rst,
    input             clk,      // 48 MHz
    input             clk96,    // download clock
    input             cen,      // 12 MHz oscillator enable
    // shared RAM (MCU side), byte address inside the 32 kB window
    output     [14:0] sh_addr,
    output     [ 7:0] sh_dout,
    output            sh_wr,
    input      [ 7:0] sh_din,
    // program download
    input      [14:0] prog_addr,
    input      [ 7:0] prog_data,
    input             prom_we
);

wire [ 7:0] rom_data, ram_data, ram_q, pre_dout, sram_q;
wire [15:0] pre_addr, pre_rom;
wire [ 6:0] ram_addr;
wire        ram_we, pre_wr, pre_acc;
reg  [15:0] rom_addr, xa;
reg  [ 7:0] xd;
reg         xw;
reg  [ 1:0] cen_dly;

wire        sram_sel = xa[15:12] != 0 && !xa[15];   // 1000-7FFF
wire        sh_sel   = xa[15];                      // 8000-FFFF

assign sh_addr = xa[14:0];
assign sh_dout = xd;
assign sh_wr   = xw & sh_sel;

// the 8051 outputs change on cen and are taken two clocks later (multicycle in syn/timing.sdc);
// cen comes every fourth clock, so the RAMs still answer before the next cen
always @(posedge clk) begin
    cen_dly <= { cen_dly[0], cen };
    if( cen_dly[1] ) begin
        xa       <= pre_addr;
        xd       <= pre_dout;
        xw       <= pre_wr & pre_acc;
        rom_addr <= pre_rom;
    end
end

wire [ 7:0] x_din = sram_sel ? sram_q : sh_sel ? sh_din : 8'hff;

jtframe_dual_ram #(.AW(15),.SIMFILE("mcu.bin")) u_sram(
    .clk0   ( clk96     ),
    .data0  ( prom_we ? prog_data : xd ),
    .addr0  ( prom_we ? prog_addr : xa[14:0] ),
    .we0    ( prom_we | (xw & sram_sel) ),
    .q0     ( sram_q    ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( rom_addr[14:0] ),
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
