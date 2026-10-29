`timescale 1ns/1ps
// Testbench for the DDR3-backed retimer (rtl/video/leland_retimer.sv).
//   +vsize=N   OSD V Size index 0..7
//   +mode=0    frame-coherence pattern (exact, requires vsize=0)
//   +mode=1    constant colour: every active output pixel must equal it,
//              and the active line count must equal nact
//   +mode=2    vertical ramp: output column must be monotonic
//   +ax=1      4-bit-per-channel (Ataxx/WSF) pixels
//   +ms=N      simulated milliseconds (default 100)
// Game side: 424x256, one pixel every 7 clk (~63 Hz, faster than the reader).
module tb_retimer2;
reg clk = 0;
always #10 clk = ~clk;

integer vsize_i, mode_i, ms_i, ax_i;
initial begin
	if (!$value$plusargs("ax=%d",    ax_i))    ax_i    = 0;
	if (!$value$plusargs("vsize=%d", vsize_i)) vsize_i = 0;
	if (!$value$plusargs("mode=%d",  mode_i))  mode_i  = 0;
	if (!$value$plusargs("ms=%d",    ms_i))    ms_i    = 100;
end

function [23:0] expand(input [7:0] c);
	if (ax_i != 0) expand = { {2{c[7:4]}}, {2{c[3:0]}}, {2{c[5:2]}} };
	else expand = { {c[2:0],c[2:0],c[2:1]}, {c[5:3],c[5:3],c[5:4]}, {c[7:6],c[7:6],c[7:6],c[7:6]} };
endfunction

// ---------------- game side ----------------
reg [2:0] gcnt = 0;
reg [9:0] ghc = 0;
reg [8:0] gvc = 0;
reg [7:0] gframe = 0;
reg g_hb = 1, g_vb = 1;
reg [23:0] g_rgb = 0;
wire g_ce = (gcnt == 6);

function [7:0] src_code(input integer x, input integer y, input [7:0] f);
	case (mode_i)
		1: src_code = 8'hB6;
		2: src_code = {2'(y * 4 / 240), 3'(y * 8 / 240), 3'(y * 8 / 240)};
		default: src_code = (x*3 + y*5 + f*7) & 8'hFF;
	endcase
endfunction

always @(posedge clk) begin
	gcnt <= g_ce ? 0 : gcnt + 1;
	if (g_ce) begin
		g_hb  <= (ghc >= 320);
		g_vb  <= (gvc >= 240);
		g_rgb <= (ghc < 320 && gvc < 240) ? expand(src_code(ghc, gvc, gframe)) : 24'd0;
		if (ghc == 423) begin
			ghc <= 0;
			if (gvc == 255) begin gvc <= 0; gframe <= gframe + 1; end
			else gvc <= gvc + 1;
		end else ghc <= ghc + 1;
	end
end

// ---------------- DUT + DDR3 model ----------------
wire o_ce, o_hb, o_hs, o_vb, o_vs;
wire [23:0] o_rgb;
wire        ddr_clk, ddr_rd, ddr_we;
wire  [7:0] ddr_bc, ddr_be;
wire [28:0] ddr_addr;
wire [63:0] ddr_din;
reg         ddr_busy = 0;
reg  [63:0] ddr_dout = 0;
reg         ddr_dv   = 0;
wire        wf_ovf;

leland_retimer #(.GAMMA_HEX("../../rtl/video/gamma_inv.hex")) dut(
	.clk_sys(clk), .stop(1'b0),
	.g_ce_pix(g_ce), .g_hblank(g_hb), .g_vblank(g_vb), .g_rgb(g_rgb), .g_ax(ax_i != 0),
	.vpos(4'd0), .vsize(vsize_i[2:0]),
	.o_ce_pix(o_ce), .o_hblank(o_hb), .o_hsync(o_hs), .o_vblank(o_vb), .o_vsync(o_vs), .o_rgb(o_rgb),
	.DDRAM_CLK(ddr_clk), .DDRAM_BUSY(ddr_busy), .DDRAM_BURSTCNT(ddr_bc), .DDRAM_ADDR(ddr_addr),
	.DDRAM_DOUT(ddr_dout), .DDRAM_DOUT_READY(ddr_dv), .DDRAM_RD(ddr_rd), .DDRAM_DIN(ddr_din),
	.DDRAM_BE(ddr_be), .DDRAM_WE(ddr_we), .wf_overflow(wf_ovf));

logic [63:0] mem [bit [28:0]];
// read response queue: {due_cycle, data}
longint cyc = 0;
longint q_due  [0:255];
logic [63:0] q_dat [0:255];
integer qh = 0, qt = 0;
integer accepted_rd = 0, accepted_wr = 0;
longint last_due = 0;

always @(posedge clk) begin
	cyc <= cyc + 1;
	ddr_dv <= 0;
	// response
	if (qh != qt && q_due[qh % 256] <= cyc) begin
		ddr_dout <= q_dat[qh % 256];
		ddr_dv   <= 1;
		qh = qh + 1;
	end
	// accept
	if ((ddr_rd | ddr_we) & ~ddr_busy) begin
		if (ddr_we) begin
			mem[ddr_addr] = ddr_din;
			accepted_wr = accepted_wr + 1;
		end else begin
			longint d;
			d = cyc + 25 + ($urandom % 40);
			if (d <= last_due) d = last_due + 1;
			last_due = d;
			q_due[qt % 256] = d;
			q_dat[qt % 256] = mem.exists(ddr_addr) ? mem[ddr_addr] : 64'd0;
			qt = qt + 1;
			accepted_rd = accepted_rd + 1;
		end
	end
	ddr_busy <= (($urandom % 4) == 0);
end

// ---------------- output capture ----------------
integer nact_exp;
always @* case (vsize_i) 1: nact_exp=236; 2: nact_exp=232; 3: nact_exp=228; 4: nact_exp=224;
	5: nact_exp=220; 6: nact_exp=216; 7: nact_exp=208; default: nact_exp=240; endcase

integer ox = 0, oy = 0, frames = 0, bad = 0, tears = 0, skipped = 0, last_f = -1;
integer f, k, x, y, match, ok, nonmono = 0;
integer line_clks, min_line = 99999, max_line = 0, last_hs_clk = -1, clkn = 0;
reg [23:0] img [0:76799];
reg prev_hs = 0, prev_vb = 0;

always @(posedge clk) begin
	clkn <= clkn + 1;
	if (o_ce) begin
		if (o_hs && !prev_hs) begin
			if (last_hs_clk >= 0) begin
				line_clks = clkn - last_hs_clk;
				if (line_clks < min_line) min_line = line_clks;
				if (line_clks > max_line) max_line = line_clks;
			end
			last_hs_clk = clkn;
		end
		prev_hs <= o_hs;

		if (!o_hb && !o_vb) begin
			img[oy*320 + ox] = o_rgb;
			ox = ox + 1;
		end
		if (o_hb && ox != 0) begin
			if (ox != 320) begin $display("ERR: line width %0d", ox); bad = bad + 1; end
			ox = 0; oy = oy + 1;
		end
		if (o_vb && !prev_vb && oy != 0) begin
			if (oy != nact_exp) begin $display("ERR: frame height %0d expected %0d", oy, nact_exp); bad = bad + 1; end
			if (frames >= 2) begin
				if (mode_i == 0) begin
					match = -1;
					for (f = 0; f < 256; f = f + 1) if (img[0] == expand((f*7) & 8'hFF)) match = f;
					ok = 1;
					for (k = 0; k < 76800 && ok; k = k + 1) begin
						x = k % 320; y = k / 320;
						if (match < 0 || img[k] != expand((x*3 + y*5 + match*7) & 8'hFF)) ok = 0;
					end
					if (!ok) begin tears = tears + 1; $display("TEAR/incoherent out frame %0d (match %0d)", frames, match); end
					else begin
						if (last_f >= 0) skipped = skipped + (((match - last_f) & 255) - 1);
						last_f = match;
					end
				end else if (mode_i == 1) begin
					for (k = 0; k < oy*320; k = k + 1)
						if (img[k] != expand(8'hB6)) begin
							if (bad < 5) $display("ERR const: pix %0d = %h", k, img[k]);
							bad = bad + 1;
						end
				end else if (mode_i == 2) begin
					for (y = 1; y < oy; y = y + 1)
						if (img[y*320][7:0] < img[(y-1)*320][7:0] ||
						    img[y*320][15:8] < img[(y-1)*320][15:8] ||
						    img[y*320][23:16] < img[(y-1)*320][23:16]) nonmono = nonmono + 1;
					if (frames == 2) $display("ramp: first line %h, last line %h", img[0], img[(oy-1)*320]);
				end
			end
			frames = frames + 1;
			oy = 0; ox = 0;
		end
		prev_vb <= o_vb;
	end
end

initial begin
	#(ms_i * 1000000);
	$display("mode=%0d vsize=%0d: out frames=%0d bad=%0d tears=%0d nonmono=%0d skipped=%0d ddr wr=%0d rd=%0d fifo_overflow=%0d",
		mode_i, vsize_i, frames, bad, tears, nonmono, skipped, accepted_wr, accepted_rd, wf_ovf);
	$display("line clks min/max = %0d/%0d (expect 3052)", min_line, max_line);
	if (bad == 0 && tears == 0 && nonmono == 0 && frames > 4 && min_line == 3052 && max_line == 3052 && !wf_ovf) $display("PASS");
	else $display("FAIL");
	$finish;
end
endmodule
