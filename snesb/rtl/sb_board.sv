// TomSVR SNES arcade bootlegs (MAME nintendo/snesb.cpp): what the board's Lattice pLSI adds on the 5A22 bus.
// Everything is set per game by the MRA header (tools/snesb_build.py), from MAME's address maps:
//   - DSW1 at 77:0071, COIN at 77:0079 (bits 0/1 = coin 1/2, active low) when header 010 bit 0; with bit 1 also
//     DSW2 at 77:0073 and 77:0072/0074/007A read as 0 (MAME nopr, extrainp_map)
//   - up to 8 constant reads (protection checks), a read counter (returns 1, 2, 3... per read)
//   - two RAM windows of up to 256 bytes (78:1000 etc., "shared with the PLD" in MAME), cleared on load,
//     with up to 4 bytes set on every reset (wldgunsb continue counter)
//   - 00:7000-7FFF reading ROM C0:7000-7FFF (sblast2b), done in main.v via sb_mirror7

module sb_board
(
	input             clk,
	input             reset,          // SNES reset
	input             dl_start,       // start of a cart download: clear the RAM

	input             hdr_wr,
	input       [8:0] hdr_a,
	input       [7:0] hdr_d,

	input      [23:0] ca,
	input             rd_n,
	input             wr_n,
	input       [7:0] cpu_do,

	input       [7:0] dsw1,
	input       [7:0] dsw2,
	input       [1:0] coin,           // active high

	output reg        sel,            // registered: one master clock behind the address (timing)
	output reg  [7:0] di,
	output            mirror7,
	output            wram_en,
	output reg [16:0] wram_addr,
	output reg  [7:0] wram_val
);

reg  [7:0] flags;
reg  [3:0] nconst;
reg [23:0] c_addr[8];
reg  [7:0] c_val[8];
reg [23:0] cnt_addr;
reg [23:0] ram_base[2];
reg  [7:0] ram_last;
reg  [1:0] ram_en;
reg  [2:0] ninit;
reg  [7:0] init_off[4], init_val[4];

assign mirror7 = flags[4];
assign wram_en = flags[5];

initial begin
	flags = 0; nconst = 0; ram_en = 0; ninit = 0;
end

always @(posedge clk) if (hdr_wr) begin
	casez (hdr_a)
		9'h010: flags <= hdr_d;
		9'h011: nconst <= hdr_d[3:0];
		9'h014: cnt_addr[23:16] <= hdr_d;
		9'h015: cnt_addr[15:8] <= hdr_d;
		9'h016: cnt_addr[7:0] <= hdr_d;
		9'h018: ram_base[0][23:16] <= hdr_d;
		9'h019: ram_base[0][15:8] <= hdr_d;
		9'h01A: ram_base[0][7:0] <= hdr_d;
		9'h01B: ram_last <= hdr_d;
		9'h01C: ram_base[1][23:16] <= hdr_d;
		9'h01D: ram_base[1][15:8] <= hdr_d;
		9'h01E: ram_base[1][7:0] <= hdr_d;
		9'h01F: ram_en <= hdr_d[1:0];
		9'b0_001?_????: begin   // 020-03F constant reads
			case (hdr_a[1:0])
				2'd0: c_addr[hdr_a[4:2]][23:16] <= hdr_d;
				2'd1: c_addr[hdr_a[4:2]][15:8]  <= hdr_d;
				2'd2: c_addr[hdr_a[4:2]][7:0]   <= hdr_d;
				2'd3: c_val[hdr_a[4:2]]         <= hdr_d;
			endcase
		end
		9'h060: ninit <= hdr_d[2:0];
		9'h061, 9'h063, 9'h065, 9'h067: init_off[hdr_a[2:1]] <= hdr_d;
		9'h062, 9'h064, 9'h066, 9'h068: init_val[hdr_a[2:1] - 1'd1] <= hdr_d;
		9'h070: wram_addr[16] <= hdr_d[0];
		9'h071: wram_addr[15:8] <= hdr_d;
		9'h072: wram_addr[7:0] <= hdr_d;
		9'h073: wram_val <= hdr_d;
		default: ;
	endcase
end

// RAM: window 0 = 000-0FF, window 1 = 100-1FF
reg  [7:0] ram[512];
reg  [8:0] clr_a;
reg        clearing;
reg  [2:0] init_n = 3'd7;
reg        reset_d;

wire [23:0] off0 = ca - ram_base[0];
wire [23:0] off1 = ca - ram_base[1];
wire        in0 = ram_en[0] && off0 <= {16'd0, ram_last};
wire        in1 = ram_en[1] && off1 <= {16'd0, ram_last};
wire  [8:0] ram_a = in0 ? {1'b0, off0[7:0]} : {1'b1, off1[7:0]};

always @(posedge clk) begin
	reset_d <= reset;
	if (dl_start) begin clearing <= 1; clr_a <= 0; end
	else if (clearing) begin
		ram[clr_a] <= 0;
		clr_a <= clr_a + 1'd1;
		if (&clr_a) clearing <= 0;
	end else if (~reset & reset_d) init_n <= 0;            // reset just ended (header loaded by then)
	else if (init_n < ninit && init_n < 3'd4) begin
		ram[{1'b0, init_off[init_n[1:0]]}] <= init_val[init_n[1:0]];
		init_n <= init_n + 1'd1;
	end else if (~wr_n && (in0 || in1)) ram[ram_a] <= cpu_do;
end

// read counter: the value seen is count + 1, the count advances at the end of each read
reg  [7:0] cnt;
reg        rd_n_d;
wire       cnt_sel = flags[3] && ca == cnt_addr;
always @(posedge clk) begin
	rd_n_d <= rd_n;
	if (reset) cnt <= 0;
	else if (rd_n & ~rd_n_d & cnt_sel) cnt <= cnt + 1'd1;
end

wire io  = flags[0] && ca[23:8] == 16'h7700;
wire io2 = flags[1] && ca[23:8] == 16'h7700;

integer k;
reg       sel_c;
reg [7:0] di_c;
always @(posedge clk) begin sel <= sel_c; di <= di_c; end
always @(*) begin
	sel_c = 0;
	di_c = 8'h00;
	if (io && ca[7:0] == 8'h71) begin sel_c = 1; di_c = dsw1; end
	if (io && ca[7:0] == 8'h79) begin sel_c = 1; di_c = {6'b000000, ~coin[1], ~coin[0]}; end
	if (io2 && ca[7:0] == 8'h73) begin sel_c = 1; di_c = dsw2; end
	if (io2 && (ca[7:0] == 8'h72 || ca[7:0] == 8'h74 || ca[7:0] == 8'h7A)) begin sel_c = 1; di_c = 8'h00; end
	for (k = 0; k < 8; k = k + 1) if (k < nconst && ca == c_addr[k]) begin sel_c = 1; di_c = c_val[k]; end
	if (cnt_sel) begin sel_c = 1; di_c = cnt + 1'd1; end
	if (in0 || in1) begin sel_c = 1; di_c = ram[ram_a]; end
end

endmodule
