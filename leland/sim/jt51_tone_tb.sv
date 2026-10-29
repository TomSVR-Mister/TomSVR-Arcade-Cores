// Drives jt51 with the same 4 MHz / 2 MHz enables and single-clock write pulses as leland_sound.sv,
// plays one carrier at A4 and writes the low-res output to jt51_tone.pcm (62.5 kHz, 16-bit mono).
`timescale 1ns / 1ps
module jt51_tone_tb;

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

integer fd, n;
initial begin
	fd = $fopen("jt51_tone.pcm", "wb");
	repeat (200) @(posedge clk);
	rst = 0;
	repeat (2000) @(posedge clk);
	ymw(8'h20, 8'hC7);                         // ch0: L+R, FB 0, CON 7
	ymw(8'h28, 8'h4A);                         // key code
	ymw(8'h30, 8'h00);
	ymw(8'h40, 8'h01); ymw(8'h48, 8'h01); ymw(8'h50, 8'h01); ymw(8'h58, 8'h01);   // MUL 1
	ymw(8'h60, 8'h7F); ymw(8'h68, 8'h7F); ymw(8'h70, 8'h7F); ymw(8'h78, 8'h10);   // TL: only the last op audible
	ymw(8'h80, 8'h1F); ymw(8'h88, 8'h1F); ymw(8'h90, 8'h1F); ymw(8'h98, 8'h1F);   // AR 31
	ymw(8'hA0, 8'h00); ymw(8'hA8, 8'h00); ymw(8'hB0, 8'h00); ymw(8'hB8, 8'h00);
	ymw(8'hC0, 8'h00); ymw(8'hC8, 8'h00); ymw(8'hD0, 8'h00); ymw(8'hD8, 8'h00);
	ymw(8'hE0, 8'h0F); ymw(8'hE8, 8'h0F); ymw(8'hF0, 8'h0F); ymw(8'hF8, 8'h0F);
	ymw(8'h08, 8'h78);                         // key on, all ops, ch0
	repeat (4_800_000) @(posedge clk);         // 100 ms
	$fclose(fd);
	$display("TONE DONE samples=%0d", n);
	$finish;
end

always @(posedge clk) if (sample) begin
	n <= n + 1;
	$fwrite(fd, "%c%c", left[7:0], left[15:8]);
end

endmodule
