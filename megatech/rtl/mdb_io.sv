/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Mega Drive arcade bootleg boards (TomSVR_mdboot): the board I/O around the Mega Drive game side.
 * Written from MAME's sega/megadriv_acbl.cpp (memory maps, input ports, PIC glue).
 *
 * family (MRA header byte 0)
 *   1  Actel boards: DSWA/B/C at 770070/72/74, coins on I/O port C (mk3mdb, ssf2mdb, barekch, srmdb)
 *   2  biohzdmb: DSWA/B/C at 770070-75, COINS at 770078 (bit 7 coin 1, bit 6 coin 2, active low)
 *   3  barek2ch: IN0 at 380070 (bit 6 coin 1, bit 7 coin 2), DSWA at 380078, DSWB at 38007a
 *   4  barek3mb: COINS at 380070 (bit 7 coin 1, bit 6 coin 2), DSW at 380078
 *   5  sonic2mb: 300000 = {DSW, 6'h3f, coin 2, coin 1} (active low); RAM at 200000-2023ff
 *   6  PIC16C57 boards, latches written at 220000, read at 330000 (aladmdb, barek2mb)
 *   7  PIC16C57 board, latches written at 200000, read at 300000 (jparkmb)
 *   8  Conny boards: DSW at 800000, COINS at 840000 (bit 0), protection word at {prot_hi, 16'h0} = prot_val;
 *      every coin edge (press and release) pulses the 68000 NMI for 1 ms (MAME coin_inserted)
 *   9  Conny 3-in-1: as 8, plus the game bank write at 820000 (bits 1-0; 1 after reset)
 */

module mdb_io
(
	input             clk,          // clk_sys (~53.7 MHz)
	input             reset,

	input       [7:0] family,
	input       [7:0] prot_hi,      // Conny protection word address bits 23-16
	input       [7:0] prot_val,
	input      [23:0] dsw,          // {DSWC, DSWB, DSWA}, active high = switch value as MAME reads it
	input             coin1,        // active high
	input             coin2,

	// PIC program download (2048 x 12, little endian words in the MRA)
	input             pic_wr,
	input      [10:0] pic_wa,
	input      [11:0] pic_wd,

	// 68000 bus (cartridge port)
	input      [23:1] addr,
	input             oe,
	input             lwr,
	input             uwr,
	input      [15:0] din,
	output reg [15:0] dout,
	output reg        den,
	output            dtack,

	output reg  [1:0] bank,         // Conny 3-in-1 game bank (000000-0fffff)
	output            nmi,          // 68000 NMI (Conny coin)
	output      [1:0] exp_coin_n    // I/O port C bits 1-0 (Actel boards, active low)
);

wire [23:0] ba = {addr, 1'b0};
wire [7:0]  dswa = dsw[7:0], dswb = dsw[15:8], dswc = dsw[23:16];

wire f_actel = family == 8'd1;
wire f_bio   = family == 8'd2;
wire f_bk2ch = family == 8'd3;
wire f_bk3   = family == 8'd4;
wire f_son2  = family == 8'd5;
wire f_pica  = family == 8'd6;
wire f_picb  = family == 8'd7;
wire f_conny = family == 8'd8 || family == 8'd9;
wire f_3in1  = family == 8'd9;
wire f_pic   = f_pica | f_picb;

assign exp_coin_n = (f_actel) ? {~coin2, ~coin1} : 2'b11;

// ---------------------------------------------------------------- Conny coin: 1 frame impulse, NMI on both edges
localparam [19:0] IMP_LEN = 20'd895000;  // ~16.7 ms at 53.7 MHz (PORT_IMPULSE(1))
localparam [16:0] NMI_LEN = 17'd53700;   // 1 ms
reg  [19:0] imp_cnt;
reg  [16:0] nmi_cnt;
reg         coin_l;
wire        conny_coin = |imp_cnt;
always @(posedge clk) begin
	coin_l <= coin1;
	if (nmi_cnt) nmi_cnt <= nmi_cnt - 1'd1;
	if (imp_cnt) begin
		imp_cnt <= imp_cnt - 1'd1;
		if (imp_cnt == 20'd1) nmi_cnt <= NMI_LEN;             // release
	end
	if (reset) begin
		imp_cnt <= 0;
		nmi_cnt <= 0;
	end
	else if (f_conny && coin1 && !coin_l && !imp_cnt) begin
		imp_cnt <= IMP_LEN;                                   // press
		nmi_cnt <= NMI_LEN;
	end
end
assign nmi = |nmi_cnt;

// ---------------------------------------------------------------- PIC16C57 (aladmdb, barek2mb, jparkmb)
reg  [11:0] pic_rom[0:2047];
reg  [11:0] pic_q;
wire [10:0] pic_pa;
always @(posedge clk) begin
	if (pic_wr) pic_rom[pic_wa] <= pic_wd;
	pic_q <= pic_rom[pic_pa];
end

reg  [5:0] pic_div;
reg        pic_cen;
always @(posedge clk) begin
	pic_cen <= 0;
	pic_div <= pic_div + 1'd1;
	if (pic_div == 6'd53) begin                              // 4 MHz oscillator / 4 = ~1 MHz instruction rate
		pic_div <= 0;
		pic_cen <= 1;
	end
end

wire [3:0] pa_out;
wire [7:0] pc_out;
wire       pa_wr;
reg  [7:0] in_lsb, in_msb, out_lsb, out_msb;
reg  [7:0] pc_in;
always @* begin
	pc_in = 8'hff;
	if (!pa_out[3]) pc_in = pc_in & dswa;
	if (!pa_out[1]) pc_in = pc_in & (pa_out[0] ? in_msb : in_lsb);
end

// the program fetch has one clock of latency: give the PIC its enable two clocks after the address can change
reg pic_cen_d1, pic_cen_d2;
always @(posedge clk) {pic_cen_d2, pic_cen_d1} <= {pic_cen_d1, pic_cen};

jtplaymark_pic pic
(
	.rst(reset | ~f_pic),
	.clk(clk),
	.cen(pic_cen_d2),
	.prog_addr(pic_pa),
	.prog_data(pic_q),
	.pa_in(4'hf),
	.pa_out(pa_out),
	.pa_wr(pa_wr),
	.pb_in({4'hf, 3'b111, ~coin1}),   // IN0: bit 0 coin, others not connected
	.pb_out(),
	.pb_wr(),
	.pb_rd(),
	.pc_in(pc_in),
	.pc_out(pc_out),
	.pc_wr(),
	.pc_rd()
);

// output latches: written when port A has latch enable low and output select high (MAME mcu_porta_w)
reg pa_wr_d;
always @(posedge clk) begin
	pa_wr_d <= pa_wr;
	if (reset) begin
		out_lsb <= 0;
		out_msb <= 0;
	end
	else if (pa_wr_d && !pa_out[2] && pa_out[1]) begin
		if (pa_out[0]) out_msb <= pc_out;
		else           out_lsb <= pc_out;
	end
end

// ---------------------------------------------------------------- sonic2mb RAM 200000-2023ff (MAME md_bootleg_map)
wire       ram_cs = f_son2 && ba >= 24'h200000 && ba < 24'h202400;
reg [15:0] ram[0:4607];
reg [15:0] ram_q;
wire [12:0] ram_a = ba[13:1];
always @(posedge clk) begin
	if (ram_cs && uwr) ram[ram_a][15:8] <= din[15:8];
	if (ram_cs && lwr) ram[ram_a][7:0]  <= din[7:0];
	ram_q <= ram[ram_a];
end

// ---------------------------------------------------------------- 68000 side
wire pic_wcs = (f_pica && ba == 24'h220000) || (f_picb && ba == 24'h200000);
wire pic_rcs = (f_pica && ba == 24'h330000) || (f_picb && ba == 24'h300000);
wire bank_cs = f_3in1 && ba == 24'h820000;

reg  [15:0] rd_val;
reg         rd_hit;
always @* begin
	rd_hit = 1;
	rd_val = 16'hffff;
	if      ((f_actel | f_bio) && ba == 24'h770070) rd_val = {8'hff, dswa};
	else if ((f_actel | f_bio) && ba == 24'h770072) rd_val = {8'hff, dswb};
	else if ((f_actel | f_bio) && ba == 24'h770074) rd_val = {8'hff, dswc};
	else if (f_bio   && ba == 24'h770078) rd_val = {8'hff, ~coin1, ~coin2, 6'h3f};
	else if (f_bk2ch && ba == 24'h380070) rd_val = {8'hff, ~coin2, ~coin1, 6'h3f};
	else if (f_bk2ch && ba == 24'h380078) rd_val = {8'hff, dswa};
	else if (f_bk2ch && ba == 24'h38007a) rd_val = {8'hff, dswb};
	else if (f_bk3   && ba == 24'h380070) rd_val = {8'hff, ~coin1, ~coin2, 6'h3f};
	else if (f_bk3   && ba == 24'h380078) rd_val = {8'hff, dswa};
	else if (f_son2  && ba == 24'h300000) rd_val = {dswa, 6'h3f, ~coin2, ~coin1};
	else if (pic_rcs)                     rd_val = {out_msb, out_lsb};
	else if (f_conny && ba == 24'h800000) rd_val = {8'hff, dswa};
	else if (f_conny && ba == 24'h840000) rd_val = {15'd0, conny_coin};
	else if (f_conny && ba == {prot_hi, 16'h0000}) rd_val = {8'h00, prot_val};
	else if (ram_cs)                      rd_val = ram_q;
	else rd_hit = 0;
end

reg wr_hit;
always @(posedge clk) begin
	den    <= oe & rd_hit;
	dout   <= rd_val;
	wr_hit <= (lwr | uwr) & (pic_wcs | bank_cs | ram_cs);

	if (reset) bank <= f_3in1 ? 2'd1 : 2'd0;
	else if (bank_cs && (uwr | lwr)) bank <= uwr ? din[9:8] : din[1:0];

	if (pic_wcs && (uwr | lwr)) begin
		if (lwr) in_lsb <= din[7:0];
		if (uwr) in_msb <= din[15:8];
	end
end

assign dtack = den | wr_hit;

endmodule

/* Data descrambling of the Actel boards (MAME init_mk3mdb, init_srmdb, init_barekch, init_barek2ch, init_barek3,
 * init_biohzdmb): the 68000 high byte of each word (the first byte in the MRA image, din bits 7-0 of the WIDE
 * ioctl word) goes through XOR + bit swap per address range; some sets also get MAME's patched reset vectors.
 * scheme (MRA header byte 1): 1 mk3mdb, 2 srmdb, 3 barekch, 4 barek2ch, 5 barek3mb, 6 biohzdmb, 0 none. */
module mdb_descramble
(
	input       [7:0] scheme,
	input      [23:0] addr,         // byte address in the game ROM
	input      [15:0] din,          // {second byte, first byte} as ioctl_data
	output     [15:0] dout
);
wire [7:0] mdb_scheme = scheme;
function [7:0] bs8(input [7:0] v, input [2:0] b7, b6, b5, b4, b3, b2, b1, b0);
	bs8 = {v[b7], v[b6], v[b5], v[b4], v[b3], v[b2], v[b1], v[b0]};
endfunction
wire [23:0] dla = addr;
wire  [7:0] dh  = din[7:0];
reg   [7:0] dh_o;
reg  [15:0] dvec;                          // patched word (68000 order), dvec_en = use it
reg         dvec_en;
always @* begin
	dh_o = dh;
	dvec = 16'h0000;
	dvec_en = 0;
	case (mdb_scheme)
		8'd1: begin // mk3mdb
			if (dla < 24'h100000) dh_o = dla[19] ? bs8(~dh, 0,3,2,5,4,6,7,1) : bs8(~dh, 4,0,7,1,3,6,2,5);
			else if (dla < 24'h400000) dh_o = dla[19] ? bs8(~dh, 2,7,5,4,1,0,3,6) : bs8(dh, 6,1,4,2,7,0,3,5);
			case (dla)
				24'h0: begin dvec = 16'h0100; dvec_en = 1; end
				24'h2: begin dvec = 16'h0000; dvec_en = 1; end
				24'h4: begin dvec = 16'h0000; dvec_en = 1; end
				24'h6: begin dvec = 16'h0210; dvec_en = 1; end
				default:;
			endcase
		end
		8'd2: begin // srmdb
			if (dla < 24'h040000) dh_o = bs8(~dh, 5,1,6,2,4,3,7,0);
			else if (dla < 24'h080000) dh_o = bs8(dh, 2,6,1,5,0,7,3,4);
			case (dla)
				24'h0: begin dvec = 16'h0100; dvec_en = 1; end
				24'h2: begin dvec = 16'h0000; dvec_en = 1; end
				24'h6: begin dvec = 16'h00d2; dvec_en = 1; end
				default:;
			endcase
		end
		8'd3: if (dla < 24'h080000) dh_o = bs8(~dh, 7,1,4,0,6,5,3,2);       // barekch
		8'd4: begin                                                         // barek2ch
			if (dla < 24'h200000) dh_o = bs8(dh, 0,3,2,5,4,6,7,1);
			if (dla == 24'h6) begin dvec = 16'h0210; dvec_en = 1; end
		end
		8'd5: if (dla < 24'h300000) dh_o = bs8(dh, 6,2,4,0,7,1,3,5);        // barek3mb
		8'd6: begin                                                         // biohzdmb
			if (dla < 24'h080000) dh_o = bs8(~dh, 0,3,2,5,4,6,7,1);
			else if (dla < 24'h100000) dh_o = bs8(dh, 6,4,0,5,1,3,2,7);
			if (dla == 24'h4) begin dvec = 16'h0000; dvec_en = 1; end
			if (dla == 24'h6) begin dvec = 16'h0204; dvec_en = 1; end
		end
		default:;
	endcase
end
assign dout = dvec_en ? {dvec[7:0], dvec[15:8]} : {din[15:8], dh_o};

endmodule
