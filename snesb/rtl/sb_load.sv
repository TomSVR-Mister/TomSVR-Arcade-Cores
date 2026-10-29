// TomSVR SNES arcade bootlegs (MAME nintendo/snesb.cpp): ROM loader that undoes the board's scramble.
//
// The MRA sends index 0 = a 0x200-byte header + the ROM region exactly as in the MAME zips (user3, or user7 for the
// address-scrambled sets). MAME decodes with dst[i] = transform_bank(i)(nibble(src[P(i)])); here every source byte j
// is written once to its decoded address i = P^-1(j), so no extra memory is needed:
//   i     = {inv_hi[j >> 15], j[14:6], inv_lo[j[5:0]]}               (tables from the header, identity if unscrambled)
//   x     = src - B9 when i bit 12 is 0 (tmntmwb only, header flag bit 2)
//   x     = data_high[x >> 4] | data_low[x & 15]
//   x     = bitswap(x, sel[bank id of i >> 16]) ^ xor[...]           (up to 8 transforms, id per 64 KB bank)
//   x     = patch value if i is one of the 8 patch addresses          (MAME's boot vector / code patches)
// Each 16-bit download word becomes two SDRAM byte writes; ioctl_wait holds the next word until both are done.
// tools/snesb_build.py makes the header and checks this exact algorithm against MAME's decrypted ROM.

module sb_load
(
	input             clk,
	input             dl,            // cart download (index 0) in progress
	input             ioctl_wr,
	input      [24:0] ioctl_addr,
	input      [15:0] ioctl_dout,
	output reg        ioctl_wait,

	output reg        wr,            // one-clock byte write request
	output reg [23:0] addr,
	output reg  [7:0] data,

	output reg        hdr_wr,        // header bytes for the board (sb_board)
	output reg  [8:0] hdr_a,
	output reg  [7:0] hdr_d
);

reg  [6:0] inv_hi[128];
reg  [5:0] inv_lo[64];
reg  [7:0] nib_h[16], nib_l[16];
reg  [2:0] bank_id[64];
reg [23:0] tr_sel[8];
reg  [7:0] tr_xor[8];
reg [23:0] p_addr[8];
reg  [7:0] p_val[8];
reg  [3:0] npatch;
reg        f_sub;

initial begin
	integer k;
	for (k = 0; k < 128; k = k + 1) inv_hi[k] = k[6:0];
	for (k = 0; k < 64; k = k + 1) begin inv_lo[k] = k[5:0]; bank_id[k] = 0; end
	for (k = 0; k < 16; k = k + 1) begin nib_h[k] = {k[3:0], 4'h0}; nib_l[k] = {4'h0, k[3:0]}; end
	for (k = 0; k < 8; k = k + 1) begin tr_sel[k] = 24'hfac688; tr_xor[k] = 0; p_addr[k] = '1; p_val[k] = 0; end
	npatch = 0; f_sub = 0;
end

// header byte writes
task hdr_byte(input [8:0] a, input [7:0] d);
	casez (a)
		9'h010: f_sub <= d[2];
		9'h012: npatch <= d[3:0];
		9'b0_010?_????: begin   // 040-05F patches: 3 address bytes (big endian) + value
			case (a[1:0])
				2'd0: p_addr[a[4:2]][23:16] <= d;
				2'd1: p_addr[a[4:2]][15:8]  <= d;
				2'd2: p_addr[a[4:2]][7:0]   <= d;
				2'd3: p_val[a[4:2]]         <= d;
			endcase
		end
		9'b0_10??_????: bank_id[a[5:0]] <= d[2:0];                   // 080-0BF
		9'b0_110?_????: begin                                         // 0C0-0DF transforms
			case (a[1:0])
				2'd0: tr_sel[a[4:2]][7:0]   <= d;
				2'd1: tr_sel[a[4:2]][15:8]  <= d;
				2'd2: tr_sel[a[4:2]][23:16] <= d;
				2'd3: tr_xor[a[4:2]]        <= d;
			endcase
		end
		9'b0_1110_????: nib_h[a[3:0]] <= d;                           // 0E0-0EF
		9'b0_1111_????: nib_l[a[3:0]] <= d;                           // 0F0-0FF
		9'b1_0???_????: inv_hi[a[6:0]] <= d[6:0];                     // 100-17F
		9'b1_10??_????: inv_lo[a[5:0]] <= d[5:0];                     // 180-1BF
		default: ;
	endcase
endtask

function [7:0] bitswap(input [7:0] x, input [23:0] sel);
	integer k;
	for (k = 0; k < 8; k = k + 1) bitswap[k] = x[sel[3*k +: 3]];
endfunction

reg  [3:0] st;
reg  [4:0] gap;
reg        second;
reg [24:0] a_r;
reg  [7:0] d_hi;
reg [21:0] j;
reg  [7:0] x;
reg [21:0] i;
reg  [2:0] tid;
integer    pk;

always @(posedge clk) begin
	wr <= 0;
	hdr_wr <= 0;
	case (st)
		0: if (dl & ioctl_wr) begin
				ioctl_wait <= 1;
				a_r <= ioctl_addr; x <= ioctl_dout[7:0]; d_hi <= ioctl_dout[15:8]; second <= 0;
				st <= 1;
			end else ioctl_wait <= 0;
		1: begin   // one byte at a_r
				if (a_r < 25'h200) begin
					hdr_byte(a_r[8:0], x);
					hdr_wr <= 1; hdr_a <= a_r[8:0]; hdr_d <= x;
					st <= 6;
				end else if (a_r >= 25'h400200) begin
					st <= 6;                       // beyond 4 MB: not a bootleg ROM
				end else begin
					j <= a_r[21:0] - 22'h200;
					st <= 2;
				end
			end
		2: begin
				i <= {inv_hi[j[21:15]], j[14:6], inv_lo[j[5:0]]};
				if (f_sub & ~j[12]) x <= x - 8'hB9;    // j[12] = i[12]
				st <= 3;
			end
		3: begin
				x <= nib_h[x[7:4]] | nib_l[x[3:0]];
				tid <= bank_id[i[21:16]];
				st <= 4;
			end
		4: begin
				x <= bitswap(x, tr_sel[tid]) ^ tr_xor[tid];
				st <= 5;
			end
		5: begin
				data <= x;
				for (pk = 0; pk < 8; pk = pk + 1) if (pk < npatch && {2'b00, i} == p_addr[pk]) data <= p_val[pk];
				addr <= {2'b00, i};
				wr <= 1;
				gap <= 5'd6;
				st <= 7;
			end
		6: st <= 8;
		7: if (gap) gap <= gap - 1'd1; else st <= 8;   // let the SDRAM finish the write
		8: if (~second) begin
				second <= 1; a_r <= a_r + 1'd1; x <= d_hi; st <= 1;
			end else begin
				ioctl_wait <= 0; st <= 0;
			end
		default: st <= 0;
	endcase
	if (~dl) begin st <= 0; ioctl_wait <= 0; end
end

endmodule
