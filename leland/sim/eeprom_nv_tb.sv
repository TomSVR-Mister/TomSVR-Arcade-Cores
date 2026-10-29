// Checks the EEPROM save port: a game WRITE sets nv_dirty and shows up
// big-endian on nv_rd_data; the load port does not set nv_dirty.
`timescale 1ns/1ps
module eeprom_nv_tb;
reg clk = 0; always #10 clk = ~clk;
reg cs = 0, sclk = 0, di = 0, mem_wr = 0, dirty_clr = 0;
reg [5:0] wa = 0; reg [15:0] wd = 0; reg [6:0] ra = 0;
wire dout, dirty; wire [7:0] rd;
integer errors = 0;
leland_eeprom_93c46 dut(.clk_sys(clk), .reset(1'b0), .cs(cs), .clk_in(sclk), .di(di), .do_out(dout),
	.mem_wr(mem_wr), .mem_wr_addr(wa), .mem_wr_data(wd),
	.nv_rd_addr(ra), .nv_rd_data(rd), .nv_dirty(dirty), .nv_dirty_clr(dirty_clr));
task bit_(input b); begin di = b; #40 sclk = 1; #40 sclk = 0; end endtask
task check(input [7:0] got, input [7:0] exp, input [8*16-1:0] what);
	if (got !== exp) begin errors = errors + 1; $display("FAIL %0s got %02x exp %02x", what, got, exp); end endtask
integer i;
initial begin
	dirty_clr = 1; #40 dirty_clr = 0;
	@(posedge clk); mem_wr = 1; wa = 6'd5; wd = 16'hA1B2; @(posedge clk); mem_wr = 0; #40;
	ra = 7'd10; #5 check(rd, 8'hA1, "load hi"); ra = 7'd11; #5 check(rd, 8'hB2, "load lo");
	check({7'd0, dirty}, 8'd0, "dirty after load");
	cs = 1; bit_(1); bit_(0); bit_(1);            // start + WRITE opcode 01
	for (i = 5; i >= 0; i = i - 1) bit_(6'd9 >> i & 1);
	for (i = 15; i >= 0; i = i - 1) bit_(16'h1234 >> i & 1);
	cs = 0; #100;
	check({7'd0, dirty}, 8'd1, "dirty after write");
	ra = 7'd18; #5 check(rd, 8'h12, "game hi"); ra = 7'd19; #5 check(rd, 8'h34, "game lo");
	dirty_clr = 1; #40 dirty_clr = 0; #40;
	check({7'd0, dirty}, 8'd0, "dirty cleared");
	if (errors == 0) $display("=== PASS ==="); else $display("=== FAIL ===");
	$finish;
end
endmodule
