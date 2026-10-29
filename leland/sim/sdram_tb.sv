//============================================================================
//  sdram_tb.sv — standalone testbench for rtl/mem/sdram.sv
//
//  Drives the SDRAM controller directly (no HPS, no CPUs, no video) against
//  Micron's official mt48lc16m16a2 behavioral model. This exists because the
//  project spent an entire session chasing a data-corruption bug purely via
//  hardware round-trips (rebuild -> flash -> read debug overlay -> repeat),
//  which is extremely slow. This testbench reproduces the same write/read
//  patterns in seconds of simulation time instead.
//
//  What it checks, in order:
//    1. Isolated single-byte write/readback (mirrors the on-hardware
//       byte-test diagnostic added to leland_board.sv).
//    2. A representative range of bytes written sequentially (mirrors how
//       HPS streams ROM data byte-by-byte), then read back two ways:
//         a. via rd0, in the same sequential order the CPU would use
//         b. via rd2, in reverse order (exercises the "cache-hit" word
//            optimization from a different angle, and the arbitration
//            when a request pattern doesn't match write order)
//    3. Explicit bank-boundary and row/column-boundary crossings.
//    4. Both byte parities (even and odd addresses) across all of the
//       above, since the DQM low/high-byte select is the most custom part
//       of this design.
//
//  Run with two different SDRAM densities to also check item 4 from the
//  debugging session (does a 64MB/128MB-chip-shaped part, which the
//  controller was never explicitly told about, behave any differently):
//    vsim ... +define+MT48LC16M16   (stock 32MB DE10-Nano chip, default)
//    vsim ... +define+MT48LC32M16   (64MB/128MB upgrade chip)
//
//  See README.md in this directory for exact compile/run commands.
//============================================================================

`timescale 1ns / 1ps

module sdram_tb;

//------------------------------------------------------------------
// Clock / reset
//------------------------------------------------------------------
localparam CLK_PERIOD = 20.83; // 48 MHz

reg clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

reg init = 1;

//------------------------------------------------------------------
// DUT <-> behavioral SDRAM chip model
//------------------------------------------------------------------
wire [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire        SDRAM_DQML, SDRAM_DQMH;
wire  [1:0] SDRAM_BA;
wire        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CKE, SDRAM_CLK;
wire        ready;

reg  [24:0] wr_addr;  reg  [7:0] wr_data;  reg  wr_req;  wire wr_ack;
reg  [24:0] rd0_addr; reg        rd0_req;  wire [7:0] rd0_data; wire rd0_ack;
reg  [24:0] rd1_addr; reg        rd1_req;  wire [7:0] rd1_data; wire rd1_ack;
reg  [24:0] rd2_addr; reg        rd2_req;  wire [7:0] rd2_data; wire rd2_ack;

// Explicit periodic refresh trigger (matches upstream's `refresh` port
// and leland_board.sv's real timer) — same < 7.8us pacing.
localparam REFRESH_CYCLES = 14'd370;
reg [13:0] refresh_cnt = 14'd0;
reg        refresh_req;
always @(posedge clk) begin
	if (refresh_cnt >= REFRESH_CYCLES) begin
		refresh_cnt <= 14'd0;
		refresh_req <= 1'b1;
	end else begin
		refresh_cnt <= refresh_cnt + 14'd1;
		refresh_req <= 1'b0;
	end
end

sdram #(.USE_ALTDDIO(1'b0)) dut
(
	.init   (init),
	.clk    (clk),
	.ready  (ready),
	.refresh(refresh_req),

	.SDRAM_DQ  (SDRAM_DQ),
	.SDRAM_A   (SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA  (SDRAM_BA),
	.SDRAM_nCS (SDRAM_nCS),
	.SDRAM_nWE (SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE (SDRAM_CKE),
	.SDRAM_CLK (SDRAM_CLK),

	.wr_addr(wr_addr), .wr_data(wr_data), .wr_req(wr_req), .wr_ack(wr_ack),
	.rd0_addr(rd0_addr), .rd0_req(rd0_req), .rd0_data(rd0_data), .rd0_ack(rd0_ack),
	.rd1_addr(rd1_addr), .rd1_req(rd1_req), .rd1_data(rd1_data), .rd1_ack(rd1_ack),
	.rd2_addr(rd2_addr), .rd2_req(rd2_req), .rd2_data(rd2_data), .rd2_ack(rd2_ack)
);

mt48lc16m16a2 chip
(
	.Dq   (SDRAM_DQ),
	.Addr (SDRAM_A),
	.Ba   (SDRAM_BA),
	.Clk  (SDRAM_CLK),
	.Cke  (SDRAM_CKE),
	.Cs_n (SDRAM_nCS),
	.Ras_n(SDRAM_nRAS),
	.Cas_n(SDRAM_nCAS),
	.We_n (SDRAM_nWE),
	.Dqm  ({SDRAM_DQMH, SDRAM_DQML})
);

//------------------------------------------------------------------
// Pass/fail bookkeeping
//------------------------------------------------------------------
integer errors = 0;
integer checks = 0;

task check_byte(input [24:0] addr, input [7:0] expected, input [7:0] actual, input [255:0] label);
	begin
		checks = checks + 1;
		if (expected !== actual) begin
			errors = errors + 1;
			$display("FAIL [%0s] addr=0x%06x expected=0x%02x actual=0x%02x (t=%0t)",
			          label, addr, expected, actual, $time);
		end
	end
endtask

//------------------------------------------------------------------
// Level-req / pulse-ack driver tasks (match leland_board.sv's protocol)
//------------------------------------------------------------------
task sdram_write(input [24:0] addr, input [7:0] data);
	begin
		@(posedge clk);
		wr_addr <= addr;
		wr_data <= data;
		wr_req  <= 1'b1;
		@(posedge clk);
		while (!wr_ack) @(posedge clk);
		wr_req <= 1'b0;
		@(posedge clk);
	end
endtask

task sdram_read(input [24:0] addr, output [7:0] data);
	begin
		@(posedge clk);
		rd0_addr <= addr;
		rd0_req  <= 1'b1;
		@(posedge clk);
		while (!rd0_ack) @(posedge clk);
		data = rd0_data;
		rd0_req <= 1'b0;
		@(posedge clk);
	end
endtask

task sdram_read_ch2(input [24:0] addr, output [7:0] data);
	begin
		@(posedge clk);
		rd2_addr <= addr;
		rd2_req  <= 1'b1;
		@(posedge clk);
		while (!rd2_ack) @(posedge clk);
		data = rd2_data;
		rd2_req <= 1'b0;
		@(posedge clk);
	end
endtask

//------------------------------------------------------------------
// Test sequence
//------------------------------------------------------------------
localparam TEST_BASE = 25'h000000; // start of address range under test
localparam TEST_LEN  = 4096;       // bytes — spans multiple rows/columns
                                    // (row boundary every 512 bytes at
                                    // col_bits=9, or 1024 at col_bits=10)

localparam CONTEND_BASE = 25'h200000; // separate region for the rd1 contender
localparam CONTEND_LEN  = 512;

reg [7:0] expected_mem [0:TEST_LEN-1];
reg [7:0] contend_mem  [0:CONTEND_LEN-1];
reg [7:0] rdata;
integer i;
reg       contend_active;
integer   contend_count;
reg       trace_on;

initial begin
	wr_req  = 0; rd0_req = 0; rd1_req = 0; rd2_req = 0;
	wr_addr = 0; wr_data = 0;
	rd0_addr = 0; rd1_addr = 0; rd2_addr = 0;
	contend_active = 1'b0;
	contend_count  = 0;
	trace_on       = 1'b0;

	// Init sequence
	init = 1;
	repeat (10) @(posedge clk);
	init = 0;

	$display("=== Waiting for SDRAM controller ready ===");
	wait (ready);
	repeat (5) @(posedge clk);
	$display("=== Controller ready at t=%0t ===", $time);

	//--------------------------------------------------------------
	// 1. Isolated single-byte test (mirrors the hardware diagnostic)
	//--------------------------------------------------------------
	$display("=== Test 1: isolated single-byte write/readback ===");
	sdram_write(25'h100000, 8'hA5);
	sdram_read(25'h100000, rdata);
	check_byte(25'h100000, 8'hA5, rdata, "isolated-byte");

	//--------------------------------------------------------------
	// 2. Sequential range write (mirrors HPS ROM streaming), then
	//    read back via rd0 in the SAME order, and via rd2 in
	//    REVERSE order.
	//--------------------------------------------------------------
	$display("=== Test 2: sequential %0d-byte range write, forward+reverse readback ===", TEST_LEN);
	for (i = 0; i < TEST_LEN; i = i + 1) begin
		expected_mem[i] = (i * 37 + 11) & 8'hFF; // simple deterministic pattern, non-trivial
		sdram_write(TEST_BASE + i[24:0], expected_mem[i]);
	end

	$display("--- forward readback via rd0 ---");
	for (i = 0; i < TEST_LEN; i = i + 1) begin
		sdram_read(TEST_BASE + i[24:0], rdata);
		check_byte(TEST_BASE + i[24:0], expected_mem[i], rdata, "seq-fwd-rd0");
	end

	$display("--- reverse readback via rd2 ---");
	for (i = TEST_LEN - 1; i >= 0; i = i - 1) begin
		sdram_read_ch2(TEST_BASE + i[24:0], rdata);
		check_byte(TEST_BASE + i[24:0], expected_mem[i], rdata, "seq-rev-rd2");
	end

	//--------------------------------------------------------------
	// 3. Explicit boundary crossings: bank, row, column, and both
	//    byte parities right at the boundary.
	//--------------------------------------------------------------
	$display("=== Test 3: explicit boundary crossings ===");
	// Bank boundary: bit 23 flips (addr[24:23] = bank)
	sdram_write(25'h7FFFFE, 8'h11); sdram_write(25'h7FFFFF, 8'h22);
	sdram_write(25'h800000, 8'h33); sdram_write(25'h800001, 8'h44);
	sdram_read(25'h7FFFFE, rdata); check_byte(25'h7FFFFE, 8'h11, rdata, "bank-boundary");
	sdram_read(25'h7FFFFF, rdata); check_byte(25'h7FFFFF, 8'h22, rdata, "bank-boundary");
	sdram_read(25'h800000, rdata); check_byte(25'h800000, 8'h33, rdata, "bank-boundary");
	sdram_read(25'h800001, rdata); check_byte(25'h800001, 8'h44, rdata, "bank-boundary");

	// Row boundary for col_bits=9 (512-byte-pair rows -> row flips
	// every 1024 bytes): straddle it explicitly.
	sdram_write(25'h0003FE, 8'h55); sdram_write(25'h0003FF, 8'h66);
	sdram_write(25'h000400, 8'h77); sdram_write(25'h000401, 8'h88);
	sdram_read(25'h0003FE, rdata); check_byte(25'h0003FE, 8'h55, rdata, "row-boundary-9col");
	sdram_read(25'h0003FF, rdata); check_byte(25'h0003FF, 8'h66, rdata, "row-boundary-9col");
	sdram_read(25'h000400, rdata); check_byte(25'h000400, 8'h77, rdata, "row-boundary-9col");
	sdram_read(25'h000401, rdata); check_byte(25'h000401, 8'h88, rdata, "row-boundary-9col");

	// Row boundary for col_bits=10 (1024-byte-pair rows -> row flips
	// every 2048 bytes): straddle it too, harmless on the 9-col part.
	sdram_write(25'h0007FE, 8'h99); sdram_write(25'h0007FF, 8'hAA);
	sdram_write(25'h000800, 8'hBB); sdram_write(25'h000801, 8'hCC);
	sdram_read(25'h0007FE, rdata); check_byte(25'h0007FE, 8'h99, rdata, "row-boundary-10col");
	sdram_read(25'h0007FF, rdata); check_byte(25'h0007FF, 8'hAA, rdata, "row-boundary-10col");
	sdram_read(25'h000800, rdata); check_byte(25'h000800, 8'hBB, rdata, "row-boundary-10col");
	sdram_read(25'h000801, rdata); check_byte(25'h000801, 8'hCC, rdata, "row-boundary-10col");

	//--------------------------------------------------------------
	// 4. Concurrent multi-channel contention — the one scenario none
	//    of the tests above exercise. On real hardware, the Master
	//    CPU starts hammering rd0 continuously at the exact moment
	//    the diagnostic scanner starts using rd2 (both triggered by
	//    the same reset falling edge), yet the isolated/sequential
	//    tests above (each channel exercised alone or in sequence)
	//    all passed while hardware still showed a checksum mismatch —
	//    pointing at genuine concurrent contention as the remaining
	//    suspect. rd1 stands in for "the other CPU channel" here so
	//    it doesn't collide with the rd0/rd2 tasks already used above.
	//--------------------------------------------------------------
	$display("=== Test 4: concurrent contention (rd1 hammering while wr+rd2 run) ===");
	// Contender reads a separate, stable region (never rewritten during
	// the contention window) so its checks can't race against the main
	// thread's concurrent writes to TEST_BASE — that would just be a
	// bug in this testbench, not a meaningful finding either way.
	for (i = 0; i < CONTEND_LEN; i = i + 1) begin
		contend_mem[i] = (i * 89 + 23) & 8'hFF;
		sdram_write(CONTEND_BASE + i[24:0], contend_mem[i]);
	end

	contend_active = 1'b1;
	fork
		begin : contender
			reg [7:0] cdata;
			integer idx;
			while (contend_active) begin
				idx = contend_count % CONTEND_LEN;
				rd1_addr <= CONTEND_BASE + idx[24:0];
				rd1_req  <= 1'b1;
				@(posedge clk);
				while (!rd1_ack) @(posedge clk);
				cdata = rd1_data;
				check_byte(CONTEND_BASE + idx[24:0], contend_mem[idx], cdata, "contend-rd1");
				rd1_req <= 1'b0;
				contend_count = contend_count + 1;
				@(posedge clk);
			end
		end
	join_none

	// Re-run the sequential write + rd2 readback (test 2's pattern) on
	// TEST_BASE while the rd1 contender above hammers CONTEND_BASE in
	// parallel — genuine concurrent multi-channel traffic.
	$display("--- test 4 write loop starting (i=0, addr=0x%06x) at t=%0t ---", TEST_BASE, $time);
	trace_on = 1'b1;
	fork
		begin : trace
			while (trace_on) begin
				@(posedge clk);
				$display("t=%0t state=%0d we=%b busy0..3=%b%b%b%b wr_ack=%b a=0x%06x bank=%0d | cmd(ras,cas,we)=%b%b%b A=0x%04x dqm=%b%b dq_oe=%b dq_r=0x%04x DQ=0x%04x",
				          $time, dut.state, dut.we,
				          dut.ch0_busy, dut.ch1_busy, dut.ch2_busy, dut.ch3_busy,
				          wr_ack, dut.a, dut.bank,
				          SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_A, SDRAM_DQMH, SDRAM_DQML,
				          dut.sdram_dq_oe, dut.sdram_dq_r, SDRAM_DQ);
			end
		end
	join_none

	for (i = 0; i < TEST_LEN; i = i + 1) begin
		expected_mem[i] = (i * 53 + 7) & 8'hFF; // different pattern from test 2
		if (i < 2) $display("--- test 4 write i=%0d addr=0x%06x data=0x%02x issuing at t=%0t ---", i, TEST_BASE+i[24:0], expected_mem[i], $time);
		sdram_write(TEST_BASE + i[24:0], expected_mem[i]);
		if (i < 2) $display("--- test 4 write i=%0d wr_ack seen, returned at t=%0t ---", i, $time);
		if (i == 1) trace_on = 1'b0;
	end
	for (i = 0; i < TEST_LEN; i = i + 1) begin
		if (i < 2) begin
			$display("--- test 4 READBACK i=%0d addr=0x%06x issuing at t=%0t ---", i, TEST_BASE+i[24:0], $time);
			trace_on = 1'b1;
			fork
				begin : trace2
					while (trace_on) begin
						@(posedge clk);
						$display("t=%0t state=%0d we=%b busy0..3=%b%b%b%b rd2_ack=%b rd2_data=0x%02x a=0x%06x bank=%0d | cmd(ras,cas,we)=%b%b%b A=0x%04x dqm=%b%b dq_oe=%b DQ=0x%04x",
						          $time, dut.state, dut.we,
						          dut.ch0_busy, dut.ch1_busy, dut.ch2_busy, dut.ch3_busy,
						          rd2_ack, rd2_data, dut.a, dut.bank,
						          SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_A, SDRAM_DQMH, SDRAM_DQML,
						          dut.sdram_dq_oe, SDRAM_DQ);
					end
				end
			join_none
		end
		sdram_read_ch2(TEST_BASE + i[24:0], rdata);
		if (i < 2) begin
			trace_on = 1'b0;
			$display("--- test 4 READBACK i=%0d rd2_ack seen, data=0x%02x (expected 0x%02x) at t=%0t ---", i, rdata, expected_mem[i], $time);
		end
		check_byte(TEST_BASE + i[24:0], expected_mem[i], rdata, "contend-rd2");
	end

	contend_active = 1'b0;
	repeat (20) @(posedge clk); // let the contender task wind down cleanly
	$display("--- contention test ran %0d concurrent rd1 accesses ---", contend_count);

	//--------------------------------------------------------------
	// 5. Realistic CPU fetch pattern: repeatedly read byte 0 then byte 1
	//    of the SAME 16-bit word, back-to-back, many times in a row via
	//    rd0 -- exactly what a Z80 does on opcode+operand fetches that
	//    land in the same word, and exactly the access pattern that
	//    triggers the "cache-hit" optimization's piggybacked
	//    AUTO_REFRESH (sdram.sv's {2'b0X, MODE_NORMAL, STATE_START}
	//    case). If that optimization violates the SDRAM's
	//    precharge-before-refresh requirement under this pattern, the
	//    Micron behavioral model will print its own
	//    "ERROR: All banks must be Precharge before Auto Refresh"
	//    message (it does not go through check_byte/errors -- watch the
	//    raw transcript for it) and, if this testbench's own
	//    same-word-readback checks below start failing afterward, that
	//    confirms the violation actually corrupts subsequent reads.
	//--------------------------------------------------------------
	$display("=== Test 5: repeated same-word 8-bit reads via rd0 (realistic CPU fetch pattern) ===");
	sdram_write(25'h300000, 8'hDE);
	sdram_write(25'h300001, 8'hAD);
	for (i = 0; i < 500; i = i + 1) begin
		sdram_read(25'h300000, rdata);
		check_byte(25'h300000, 8'hDE, rdata, "same-word-rd0-lo");
		sdram_read(25'h300001, rdata);
		check_byte(25'h300001, 8'hAD, rdata, "same-word-rd0-hi");
	end
	$display("--- test 5 done at t=%0t ---", $time);

	//--------------------------------------------------------------
	// Summary
	//--------------------------------------------------------------
	$display("");
	$display("=== SUMMARY: %0d checks, %0d errors ===", checks, errors);
	if (errors == 0) $display("=== PASS ===");
	else              $display("=== FAIL ===");

	$finish;
end

// Safety timeout in case a wr_ack/rd_ack never arrives (controller hang)
initial begin
	#15_000_000; // generous margin — test 4 roughly doubles total sim time
	$display("=== TIMEOUT: simulation did not finish in time — controller likely hung ===");
	$finish;
end

endmodule
