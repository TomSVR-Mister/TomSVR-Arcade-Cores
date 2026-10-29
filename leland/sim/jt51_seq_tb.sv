// Drives jt51 with the same 4 MHz / 2 MHz enables and single-clock write pulses as leland_sound.sv,
// plays one carrier at A4 and writes the low-res output to jt51_seq.pcm (62.5 kHz, 16-bit mono).
`timescale 1ns / 1ps
module jt51_seq_tb;

reg clk = 0;
always #10.4165 clk = ~clk;

reg rst = 1;
reg [3:0] div = 0;
wire cen = (div == 4'd11);
reg phase = 0;
wire cen_p1 = cen && phase;
always @(posedge clk) begin
	div <= (div == 4'd11) ? 4'd0 : div + 4'd1;
	if (cen) phase <= ~phase;
end

reg        wr = 0;
reg        a0 = 0;
reg  [7:0] din = 0;
wire [7:0] dout;
wire signed [15:0] left, right;
wire sample;

jt51 u_ym(
	.rst(rst), .clk(clk), .cen(cen), .cen_p1(cen_p1),
	.cs_n(1'b0), .wr_n(~(wr & cen_p1)), .a0(a0), .din(din), .dout(dout),
	.ct1(), .ct2(), .irq_n(), .sample(sample), .left(left), .right(right), .xleft(), .xright());

task automatic ymw(input [7:0] r, input [7:0] d);
	begin
		@(negedge clk); a0 = 0; din = r; wr = 1;
		@(negedge clk); while (!cen_p1) @(negedge clk);
		@(negedge clk); wr = 0;
		repeat (400) @(negedge clk);
		a0 = 1; din = d; wr = 1;
		@(negedge clk); while (!cen_p1) @(negedge clk);
		@(negedge clk); wr = 0;
		repeat (400) @(negedge clk);
	end
endtask

integer fd, n, sfd, sa, sd;
initial begin
	fd = $fopen("jt51_seq.pcm", "wb");
	repeat (10) @(posedge clk);
	rst = 0;
	repeat (2000) @(posedge clk);
	sfd = $fopen("ym_seq.txt", "r");
	while (!$feof(sfd)) begin
		if ($fscanf(sfd, "%d %h\n", sa, sd) == 2) begin
			@(negedge clk); a0 = sa[0]; din = sd[7:0]; wr = 1;
			@(negedge clk); while (!cen_p1) @(negedge clk);
			@(negedge clk); wr = 0;
			repeat (150) @(negedge clk);
		end
	end
	repeat (24_000_000) @(posedge clk);         // 100 ms
	$fclose(fd);
	$display("TONE DONE samples=%0d", n);
	$finish;
end

always @(posedge clk) if (sample) begin
	n <= n + 1;
	$fwrite(fd, "%c%c", left[7:0], left[15:8]);
end

endmodule
