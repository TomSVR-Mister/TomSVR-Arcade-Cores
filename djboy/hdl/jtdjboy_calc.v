/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Kaneko CALC1 on the Air Buster main bus at efe0-eff5 (MAME kaneko/kaneko_hit.cpp type 0, airbustr.cpp calc1_r/w).
 * 16-bit registers, low byte at the even address. Writes: 00 x1p 02 x1s 04 y1p 06 y1s 08 x2p 0a x2s 0c y2p 0e y2s
 * 10 mult_a 12 mult_b. Reads: 04 collision flags, 10/12 product high/low, 14 random number, others 0.
 * Differences in the 16-bit sums are kept to 16 bits as in MAME (int16_t). */
module jtdjboy_calc(
    input             rst,
    input             clk,
    input             we,
    input      [ 4:0] addr,
    input      [ 7:0] din,
    output reg [ 7:0] dout
);

reg  [15:0] x1p, x1s, y1p, y1s, x2p, x2s, y2p, y2s, mult_a, mult_b, lfsr, rd;
wire [31:0] mult = mult_a * mult_b;
wire [15:0] x12 = x1p - (x2p + x2s);
wire [15:0] y12 = y1p - (y2p + y2s);
wire [15:0] x21 = (x1p + x1s) - x2p;
wire [15:0] y21 = (y1p + y1s) - y2p;
wire        overlap = x12[15] && y12[15] && !x21[15] && !y21[15];
wire [15:0] coll = { y1p < y2p, y1p == y2p, y1p > y2p, 1'b0,
                     x1p < x2p, x1p == x2p, x1p > x2p, 8'd0, overlap };

always @(posedge clk) begin
    if( rst ) begin
        x1p <= 0; x1s <= 0; y1p <= 0; y1s <= 0; x2p <= 0; x2s <= 0; y2p <= 0; y2s <= 0;
        mult_a <= 0; mult_b <= 0; lfsr <= 16'hace1;
    end else begin
        lfsr <= { lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10] };
        if( we ) case( addr[4:1] )
            4'h0: if( addr[0] ) x1p[15:8]    <= din; else x1p[7:0]    <= din;
            4'h1: if( addr[0] ) x1s[15:8]    <= din; else x1s[7:0]    <= din;
            4'h2: if( addr[0] ) y1p[15:8]    <= din; else y1p[7:0]    <= din;
            4'h3: if( addr[0] ) y1s[15:8]    <= din; else y1s[7:0]    <= din;
            4'h4: if( addr[0] ) x2p[15:8]    <= din; else x2p[7:0]    <= din;
            4'h5: if( addr[0] ) x2s[15:8]    <= din; else x2s[7:0]    <= din;
            4'h6: if( addr[0] ) y2p[15:8]    <= din; else y2p[7:0]    <= din;
            4'h7: if( addr[0] ) y2s[15:8]    <= din; else y2s[7:0]    <= din;
            4'h8: if( addr[0] ) mult_a[15:8] <= din; else mult_a[7:0] <= din;
            4'h9: if( addr[0] ) mult_b[15:8] <= din; else mult_b[7:0] <= din;
            default:;
        endcase
    end
end

always @* begin
    case( addr[4:1] )
        4'h2:    rd = coll;
        4'h8:    rd = mult[31:16];
        4'h9:    rd = mult[15:0];
        4'ha:    rd = lfsr;
        default: rd = 16'd0;
    endcase
end

always @(posedge clk) dout <= addr[0] ? rd[15:8] : rd[7:0];

endmodule
