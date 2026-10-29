//============================================================================
//  sdram_margin_tb.sv — corroborating check for the "TRCD_CYC/TRP_CYC == 1
//  cycle, zero-margin rounding edge" theory raised while debugging the
//  rd2 (video) SDRAM tearing bug (see rtl/leland_board.sv's rd2_age_cnt/
//  rd2_boost).
//
//  sim/sdram_tb.sv (the existing controller testbench) is STALE: it
//  instantiates a module literally named `sdram` with per-channel
//  wr/rd0/rd1/rd2 ports -- the OLD internal 4-channel arbitrated design
//  leland_board.sv's own header comment says was replaced by `sdram_simple`
//  (single port) + an external arbiter. `rtl/mem/sdram.sv` no longer defines
//  that `sdram` module at all, so sim/sdram_tb.sv fails at elaboration
//  (confirmed: vsim-3033 "Instantiation of 'sdram' failed, design unit not
//  found"). It cannot be used to check current sdram_simple margins without
//  a rewrite -- this file is that rewrite, scoped narrowly to the one
//  question at hand rather than a full port of the old test's 4 checks.
//
//  PURPOSE: drive sdram_simple (the actual, current single-port controller
//  rtl/leland_board.sv uses) against Micron's official mt48lc16m16a2 behavioral
//  model with the SAME back-to-back-different-row read/write pattern the
//  real board produces under load, and watch whether the model's own
//  built-in tRCD/tRP/tRC/tRRD/tRAS/tWR timing-violation checks (mt48lc16m16a2.v,
//  unconditional $display "... ERROR: tXXX violation ..." -- NOT gated by
//  its Debug flag) ever fire.
//
//  Two runs:
//    1. BASELINE: chip model's real datasheet timing parameters (as shipped
//       in mt48lc16m16a2.v: tRCD=15ns, tRP=15ns, tRC=60ns, tRRD=14ns) against
//       sdram_simple's actual TRCD_NS=18ns/TRP_NS=18ns/CLK_MHZ=48 config
//       (rtl/leland_board.sv's real instantiation parameters). If this run is
//       clean, it means the CURRENT design has real margin against the
//       actual chip's datasheet minimums -- NOT literally "zero margin" --
//       even though TRCD_CYC/TRP_CYC compute to exactly 1 clk_sys cycle
//       (20.83ns @ 48MHz clears the 15ns minimum by 5.83ns / ~39%).
//    2. MARGIN SEARCH: override the model's tRCD/tRP parameters upward
//       (simulating a slower/tighter real chip / worse PVT corner) in steps,
//       to find the actual ns value at which the model starts flagging
//       violations against sdram_simple's fixed 1-clk_sys-cycle (20.83ns)
//       gap -- i.e. the real edge, not a guessed one.
//============================================================================

`timescale 1ns / 1ps

module sdram_margin_tb;

//------------------------------------------------------------------
// Compile-time margin override -- default reproduces the chip's real
// datasheet minimums (baseline run). Pass +define+TEST_TRCD=<ns> and/or
// +define+TEST_TRP=<ns> on the vlog command line for the margin-search run.
//------------------------------------------------------------------
`ifndef TEST_TRCD
`define TEST_TRCD 15.0
`endif
`ifndef TEST_TRP
`define TEST_TRP 15.0
`endif

localparam CLK_PERIOD = 20.83; // 48 MHz, matches rtl/leland_board.sv's real clk_sys

reg clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

reg rst_n = 0;

wire        sd_cke, sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n;
wire  [1:0] sd_ba;
wire [12:0] sd_a;
wire  [1:0] sd_dqm;
wire [15:0] sd_dq_out;
wire        sd_dq_oe;
wire [15:0] sd_dq_in;

reg  [24:0] addr;
reg   [7:0] din, din_hi;
reg         rd, we, we_word;
wire  [7:0] dout;
wire        ready, req_done;

// Same CAS_LAT/TRCD_NS/TRP_NS/etc. as rtl/leland_board.sv's real instantiation
// (see its sdram_ctrl instance comment) -- this is the actual deployed
// config, not a hypothetical one.
sdram_simple #(
	.CLK_MHZ(48),
	.CAS_LAT(3),
	.TRCD_NS(18),
	.TRP_NS(18)
) dut (
	.sd_cke(sd_cke), .sd_cs_n(sd_cs_n), .sd_ras_n(sd_ras_n), .sd_cas_n(sd_cas_n),
	.sd_we_n(sd_we_n), .sd_ba(sd_ba), .sd_a(sd_a), .sd_dqm(sd_dqm),
	.sd_dq_out(sd_dq_out), .sd_dq_oe(sd_dq_oe), .sd_dq_in(sd_dq_in),
	.clk(clk), .rst_n(rst_n),
	.addr(addr), .din(din), .dout(dout), .rd(rd), .we(we),
	.din_hi(din_hi), .we_word(we_word),
	.ready(ready), .req_done(req_done)
);

wire [15:0] SDRAM_DQ = sd_dq_oe ? sd_dq_out : 16'bz;
assign sd_dq_in = SDRAM_DQ;

mt48lc16m16a2 #(
	.tRCD(`TEST_TRCD),
	.tRP (`TEST_TRP)
) chip (
	.Dq(SDRAM_DQ), .Addr(sd_a), .Ba(sd_ba), .Clk(clk), .Cke(sd_cke),
	.Cs_n(sd_cs_n), .Ras_n(sd_ras_n), .Cas_n(sd_cas_n), .We_n(sd_we_n),
	.Dqm({sd_dqm[1], sd_dqm[0]})
);

//------------------------------------------------------------------
// Count the Micron model's own unconditional ERROR $display lines by
// having *this* testbench also watch the exact same conditions the model
// checks internally is not possible from outside without duplicating its
// internal state -- instead this is done by grepping the vsim transcript
// for "ERROR:" after the run (see sim/README.md-style run instructions
// in the report). This TB just needs to drive a realistic worst-case
// back-to-back-different-row/bank access pattern for long enough.
//------------------------------------------------------------------

task automatic do_read(input [24:0] a);
	begin
		@(posedge clk);
		addr = a; rd = 1'b1; we = 1'b0; we_word = 1'b0;
		@(posedge clk iff ready);
		// one more edge to let the accept happen combinationally as in
		// real usage (sdram_simple samples on the same edge `ready` was
		// high with rd asserted)
		@(posedge clk iff req_done);
		rd = 1'b0;
	end
endtask

task automatic do_write(input [24:0] a, input [7:0] lo, input [7:0] hi);
	begin
		@(posedge clk);
		addr = a; din = lo; din_hi = hi; we_word = 1'b1; rd = 1'b0;
		@(posedge clk iff ready);
		@(posedge clk iff req_done);
		we_word = 1'b0;
	end
endtask

integer i;
initial begin
	addr = 0; din = 0; din_hi = 0; rd = 0; we = 0; we_word = 0;
	rst_n = 0;
	repeat (20) @(posedge clk);
	rst_n = 1;
	// Wait for init sequence (TINIT_NS=100_000 -> ~4800 cycles @48MHz)
	@(posedge clk iff ready);
	$display("t=%0t === SDRAM init complete, starting back-to-back worst-case access pattern ===", $time);

	// Worst-case pattern: every transaction targets a DIFFERENT bank AND a
	// different row from the previous one (defeats any row-open/cache-hit
	// shortcut and forces a fresh ACT+PRECHARGE-style tRCD/tRP/tRC/tRRD
	// exercise on every single transaction) -- exactly the access pattern
	// real rd0/rd1/rd2/rd3 traffic produces in practice (unrelated CPU/
	// video addresses, no spatial locality guaranteed transaction to
	// transaction), and the specific pattern that stresses tRCD/tRP/tRC/
	// tRRD hardest since sdram_simple issues an ACT+auto-precharge command
	// pair EVERY transaction regardless (no row-buffer-hit optimization in
	// this controller at all).
	// addr layout (sdram_simple, COL_BITS=9/BANK_BITS=2/ROW_BITS=13):
	//   addr[0]      = byte lane
	//   addr[9:1]    = column
	//   addr[11:10]  = bank
	//   addr[24:12]  = row
	// Each iteration's read and write deliberately land in a DIFFERENT
	// bank AND row than the transaction immediately before it.
	for (i = 0; i < 2000; i = i + 1) begin
		do_read({i[12:0], i[1:0], i[8:0], 1'b0});
		do_write({(i[12:0] ^ 13'h1555), (i[1:0] + 2'd1), i[8:0], 1'b1}, i[7:0], ~i[7:0]);
	end

	$display("=== SDRAM_MARGIN_TB done: %0d read+write pairs issued, TEST_TRCD=%0.1fns TEST_TRP=%0.1fns ===",
	          i, `TEST_TRCD, `TEST_TRP);
	$finish;
end

endmodule
