`timescale 1ns/1ps
// Testbench for rtl/mem/leland_ddr_loader.sv
//  1. DDR load: image staged in a DDR3 model, download ends with no bytes and
//     ioctl_addr = length (odd length, not a multiple of 8). The replay must
//     produce exactly the image, in order, with o_addr = byte offset, honouring
//     b_wait, and o_download must be high continuously (no glitch).
//  2. Streamed load: bytes pass straight through, no replay.
module tb_loader;
reg clk = 0;
always #10 clk = ~clk;

localparam LEN = 1003;

reg        ioctl_download = 0;
reg [15:0] ioctl_index = 0;
reg [26:0] ioctl_addr = 0;
reg        ioctl_wr = 0;
reg  [7:0] ioctl_data = 0;
wire       ioctl_wait;
wire       o_download, o_wr, active;
wire [15:0] o_index;
wire [26:0] o_addr;
wire  [7:0] o_data;
reg        b_wait = 0;
wire       ddr_acq, ddr_read;
wire [28:0] ddr_addr;
reg        ddr_busy = 0;
reg [63:0] ddr_rdata = 0;
reg        ddr_rdv = 0;

leland_ddr_loader dut(.clk(clk),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_addr(ioctl_addr),
	.ioctl_wr(ioctl_wr), .ioctl_data(ioctl_data), .ioctl_wait(ioctl_wait),
	.o_download(o_download), .o_index(o_index), .o_addr(o_addr), .o_wr(o_wr), .o_data(o_data),
	.b_wait(b_wait), .active(active),
	.ddr_acquire(ddr_acq), .ddr_addr(ddr_addr), .ddr_read(ddr_read),
	.ddr_busy(ddr_busy), .ddr_rdata(ddr_rdata), .ddr_rdata_ready(ddr_rdv));

// ---- DDR3 model (read only), image at word 0x06000000 ----
reg [7:0] image [0:4095];
integer i;
function [63:0] word_at(input [28:0] a);
	integer b, base;
	begin
		base = (a - 29'h06000000) * 8;
		word_at = 64'd0;
		for (b = 0; b < 8; b = b + 1) word_at[b*8 +: 8] = image[base + b];
	end
endfunction

integer lat = 0;
reg [28:0] pend_addr;
reg        pend = 0;
always @(posedge clk) begin
	ddr_rdv <= 0;
	ddr_busy <= ($urandom % 3) == 0;
	if (ddr_read & ~ddr_busy & ~pend) begin pend <= 1; pend_addr <= ddr_addr; lat <= 20 + ($urandom % 20); end
	else if (pend) begin
		if (lat == 0) begin ddr_rdata <= word_at(pend_addr); ddr_rdv <= 1; pend <= 0; end
		else lat <= lat - 1;
	end
	b_wait <= ($urandom % 5) == 0;
end

// ---- capture ----
integer got = 0, errs = 0, dl_glitch = 0;
reg saw_dl = 0, dl_prev = 0;
reg [7:0] cap [0:4095];
reg replay_phase = 0;
always @(posedge clk) begin
	dl_prev <= o_download;
	if (replay_phase) begin
		if (saw_dl && dl_prev && !o_download && got != LEN) dl_glitch = dl_glitch + 1;
		if (o_download) saw_dl <= 1;
		if (o_wr) begin
			if (!o_download) begin errs = errs + 1; $display("ERR wr outside download"); end
			if (o_addr !== got) begin errs = errs + 1; if (errs < 5) $display("ERR addr %0d != %0d", o_addr, got); end
			if (o_data !== image[got]) begin errs = errs + 1; if (errs < 5) $display("ERR data @%0d: %h != %h", got, o_data, image[got]); end
			if (o_index != 0) errs = errs + 1;
			got = got + 1;
		end
	end
end

integer s_got = 0, s_errs = 0;
reg stream_phase = 0;
always @(posedge clk) if (stream_phase && o_wr) begin
	if (o_data !== (8'h40 + s_got[7:0])) s_errs = s_errs + 1;
	s_got = s_got + 1;
end

initial begin
	for (i = 0; i < 4096; i = i + 1) image[i] = (i * 7 + 3) & 8'hFF;
	repeat (10) @(posedge clk);

	// --- 1: DDR load
	replay_phase = 1;
	ioctl_index = 16'd0;
	@(posedge clk); ioctl_download <= 1;
	repeat (200) @(posedge clk);            // HPS copying to DDR3
	@(posedge clk); ioctl_addr <= LEN; ioctl_download <= 0;   // end: length, no bytes
	repeat (100000) begin
		@(posedge clk);
		if (got == LEN && !active) disable_wait;
	end
end

task disable_wait; begin end endtask

initial begin
	#8000000;  // 8 ms
	$display("DDR replay: got %0d of %0d bytes, errs=%0d, download glitches=%0d, active=%0d", got, LEN, errs, dl_glitch, active);
	replay_phase = 0;

	// --- 2: streamed load passes through
	stream_phase = 1;
	@(posedge clk); ioctl_index <= 16'd0; ioctl_download <= 1; ioctl_addr <= 0;
	repeat (5) @(posedge clk);
	for (i = 0; i < 20; i = i + 1) begin
		@(posedge clk); ioctl_data <= 8'h40 + i; ioctl_wr <= 1; ioctl_addr <= i;
		@(posedge clk); ioctl_wr <= 0;
		repeat (3) @(posedge clk);
	end
	@(posedge clk); ioctl_addr <= 20; ioctl_download <= 0;
	repeat (200) @(posedge clk);
	$display("Stream pass-through: got %0d of 20 bytes, errs=%0d, replay active=%0d", s_got, s_errs, active);

	if (got == LEN && errs == 0 && dl_glitch == 0 && !active && s_got == 20 && s_errs == 0) $display("PASS");
	else $display("FAIL");
	$finish;
end
endmodule
