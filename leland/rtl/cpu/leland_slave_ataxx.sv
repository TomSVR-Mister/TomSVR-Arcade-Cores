// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 shimian5

// Ataxx slave Z80 (MAME leland.cpp ataxx_state::slave_map_program / slave_map_io_2).

module leland_slave_ataxx
(
	input         clk_sys,
	input         reset,
	input         CE_6M,
	input         wsf_mode,    // WSF family: 0x160000-byte ROM, banks up to 15 plus bit 5
	input         slave_1mb,   // WSF family with a 1 MB ROM: bank register bit 5 is unused

	output [20:0] rom_addr,
	input   [7:0] rom_data,

	output        vp_req,
	output        vp_rd,
	output        vp_trans,
	output [15:0] vp_addr,
	output  [7:0] vp_data,
	input         vp_pop,
	input   [7:0] vp_rdata,

	output [11:0] wram_addr,
	output  [7:0] wram_din,
	output        wram_we,
	input   [7:0] wram_dout,

	input         slave_int_req,
	input         nmi_n,
	output        slave_halt_n,

	input   [7:0] raster_line,

	output        rom_req,
	input         rom_stall
);

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
reg   [7:0] cpu_din;

reg int_n;
always @(posedge clk_sys) begin
	if (reset)
		int_n <= 1'b1;
	else if (slave_int_req)
		int_n <= 1'b0;
	else if (CE_6M && ~iorq_n && ~m1_n)
		int_n <= 1'b1;
end

wire mem_access = ~mreq_n & rfsh_n;
wire in_fixed   = (cpu_addr[15:13] == 3'd0);
wire in_banked  = (cpu_addr[15:13] >= 3'd1) && (cpu_addr[15:13] <= 3'd4);
wire in_rom_hi  = (cpu_addr[15:13] == 3'd5) || (cpu_addr[15:13] == 3'd6);
wire in_wram    = (cpu_addr[15:12] == 4'hE);
wire in_top     = (cpu_addr[15:2] == 14'h3FFF);

wire rom_read_cyc = mem_access & ~rd_n & (in_fixed | in_banked | in_rom_hi);
assign rom_req = rom_read_cyc;

wire vport_stall;
wire cpu_wait_n = ~((rom_read_cyc & rom_stall) | vport_stall);

tv80s_ce #(.Mode(0), .T2Write(1), .IOWait(1)) slave_cpu
(
	.reset_n(~reset),
	.clk    (clk_sys),
	.cen    (CE_6M),
	.wait_n (cpu_wait_n),
	.int_n  (int_n),
	.nmi_n  (nmi_n),
	.busrq_n(1'b1),
	.m1_n   (m1_n),
	.mreq_n (mreq_n),
	.iorq_n (iorq_n),
	.rd_n   (rd_n),
	.wr_n   (wr_n),
	.rfsh_n (rfsh_n),
	.halt_n (halt_n),
	.busak_n(busak_n),
	.A      (cpu_addr),
	.di     (cpu_din),
	.dout   (cpu_dout)
);

assign slave_halt_n = halt_n;

// Bank register (ataxx_slave_banksw_w): block at 0x10000*bank + 0x8000*data[4] (+0x100000*data[5]
// when the ROM is larger than 1 MB); bank 0 and blocks past the end of the ROM (0x60000 bytes
// for Ataxx, 0x160000 for the WSF family, 0x100000 with slave_1mb) map the window onto the raw
// image.
reg [5:0] bank_reg;
wire [3:0] bank = bank_reg[3:0];
wire [5:0] block = {bank_reg[5] & wsf_mode & ~slave_1mb, bank, bank_reg[4]};
wire bank_raw = (bank == 4'd0) || (block >= (slave_1mb ? 6'd32 : wsf_mode ? 6'd44 : 6'd12));

assign rom_addr = (in_banked & ~bank_raw) ? {block, cpu_addr[14:0]}
	: {6'b0, cpu_addr};

assign wram_addr = cpu_addr[11:0];
assign wram_din  = cpu_dout;
assign wram_we   = mem_access & ~wr_n & in_wram;

// VRAM port at 0x60-0x7F, offset shuffled as in ataxx_svram_port_r/w
wire io_rd   = ~iorq_n & ~rd_n;
wire io_wr   = ~iorq_n & ~wr_n;
wire io_vram = (cpu_addr[7:5] == 3'b011);
wire [4:0] vp_shuf = {cpu_addr[4], cpu_addr[0], cpu_addr[3:1]};

wire vidlat_sel = in_top & ~cpu_addr[1];
wire vidlat_wr  = CE_6M && mem_access && ~wr_n && vidlat_sel;

wire [7:0] vram_rd_data;

leland_vram_port #(.TRANS_EN(1'b1)) vport
(
	.clk_sys(clk_sys),
	.reset(reset),
	.CE_6M(CE_6M),

	.cpu_addr({cpu_addr[15:5], vp_shuf}),
	.cpu_dout(cpu_dout),
	.io_wr(io_wr),
	.io_rd(io_rd),
	.io_vram_sel(io_vram),
	.vidlat_wr(vidlat_wr),
	.vidlat_hi(cpu_addr[0]),

	.rd_data(vram_rd_data),
	.vp_stall(vport_stall),

	.vp_req(vp_req),
	.vp_rd(vp_rd),
	.vp_trans(vp_trans),
	.vp_addr(vp_addr),
	.vp_data(vp_data),
	.vp_pop(vp_pop),
	.vp_rdata(vp_rdata)
);

wire bank_wr = CE_6M && mem_access && ~wr_n && (cpu_addr == 16'hFFFF);

always @(posedge clk_sys) begin
	if (reset)
		bank_reg <= 6'd1;
	else if (bank_wr)
		bank_reg <= cpu_dout[5:0];
end

always @(*) begin
	cpu_din = 8'hFF;
	if (mem_access && ~rd_n) begin
		if      (in_fixed || in_banked || in_rom_hi) cpu_din = rom_data;
		else if (in_wram)                            cpu_din = wram_dout;
		else if (in_top && cpu_addr[1:0] == 2'b10)   cpu_din = raster_line;
	end else if (io_rd) begin
		if (io_vram) cpu_din = vram_rd_data;
	end
end

endmodule
