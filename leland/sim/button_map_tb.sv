// button_map: for every game, press each mapped button alone and check which board input it
// drives, that the direction bits pass through, and that unused buttons do nothing.
`timescale 1ns / 1ps
module button_map_tb;

reg  [7:0] game_id;
reg  [8:0] joy;
wire [7:0] board;
wire       menu;
wire [7:0] menu_p3;

button_map dut(.game_id(game_id), .joy(joy), .board(board), .menu(menu), .menu_p3(menu_p3));

integer errors = 0;

// Press one OSD button position (4..8) and expect the board bit (0 = none), the menu flag and
// the player 3 bits Menu Enter drives
task automatic check(input [7:0] gid, input integer pos, input integer board_bit, input exp_menu, input [7:0] exp_p3, input [255:0] name);
	reg [7:0] exp;
	begin
		game_id = gid;
		joy = 9'd1 << pos;
		#1;
		exp = (board_bit == 0) ? 8'h00 : (8'd1 << board_bit);
		if (board !== exp || menu !== exp_menu || menu_p3 !== exp_p3) begin
			errors = errors + 1;
			$display("FAIL game %0d %0s (OSD button %0d): board=%02x expected %02x, menu=%b expected %b, menu_p3=%02x expected %02x",
			         gid, name, pos - 3, board, exp, menu, exp_menu, menu_p3, exp_p3);
		end
	end
endtask

integer g, d;
initial begin
	// Off-Road, Track-Pak (ids 0, 1) and an unknown id fall back to the same layout
	for (g = 0; g < 2; g = g + 1) begin
		check(g, 4, 6, 0, 8'h00, "Gas");
		check(g, 5, 4, 0, 8'h00, "Nitro");
		check(g, 6, 7, 1, 8'h10, "Menu Enter");
		check(g, 7, 5, 0, 8'h00, "Coin");
	end
	check(8'd2, 4, 4, 0, 8'h00, "Jump");
	check(8'd2, 5, 5, 0, 8'h00, "Throw");
	check(8'd2, 6, 7, 0, 8'h00, "Coin");
	check(8'd2, 7, 6, 0, 8'h00, "Start");

	check(8'd3, 4, 4, 0, 8'h00, "Place");
	check(8'd3, 5, 7, 0, 8'h00, "Coin");
	check(8'd3, 6, 6, 0, 8'h00, "Start");
	check(8'd3, 7, 0, 0, 8'h00, "(unused)");

	check(8'd4, 4, 6, 0, 8'h00, "Gas");
	check(8'd4, 5, 4, 0, 8'h00, "Nitro");
	check(8'd4, 6, 0, 1, 8'h10, "Menu Enter");
	check(8'd4, 7, 7, 0, 8'h00, "Coin");

	check(8'd5, 4, 4, 0, 8'h00, "Punch/Kick");
	check(8'd5, 5, 5, 0, 8'h00, "Dive");
	check(8'd5, 6, 0, 1, 8'h40, "Menu Enter");
	check(8'd5, 7, 7, 0, 8'h00, "Coin");
	check(8'd5, 8, 6, 0, 8'h00, "Start");

	// Direction bits are untouched and nothing pressed gives nothing
	for (g = 0; g < 6; g = g + 1)
		for (d = 0; d < 16; d = d + 1) begin
			game_id = g; joy = {5'h00, d[3:0]}; #1;
			if (board !== {4'h0, d[3:0]} || menu !== 1'b0 || menu_p3 !== 8'h00) begin
				errors = errors + 1;
				$display("FAIL game %0d direction %0h: board=%02x menu=%b menu_p3=%02x", g, d, board, menu, menu_p3);
			end
		end

	if (errors == 0) $display("BUTTON_MAP PASS");
	else $display("BUTTON_MAP FAIL: %0d errors", errors);
	$finish;
end

endmodule
