/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Playmark sprites (MAME playmark_v.cpp draw_sprites). 4 words per entry; entry e (from 1) uses
 *   y = word 3 of entry e-1 (bit 14: flip x), x = (w1 & 1ff) - 23, colour = w1[13:9], code = w2 >> 4 (Big Twin, 32x32)
 *   or w2 >> 2 (Excelsior, 16x16). sy = (248 - height - y) & ff. The list ends at the entry whose y word is 2000.
 *   MAME draws from the end of the list down to entry 1 with pdrawgfx (the first pixel drawn wins), so higher
 *   entries are on top: here the list is scanned upwards and later pixels overwrite earlier ones.
 *   Priority (Excelsior): w1 bit 15 -> 1, else colour & c == c -> 2, else 0.
 * Graphics: 4 planes in quarters, interleaved so a 32-bit word = 8 pixels (byte k = plane k, bit 7 leftmost)
 *   32x32: 128 bytes per sprite and plane, word at { code, y[4], x[4:3], y[3:0] }
 *   16x16:  32 bytes,                       word at { code, x[3], y[3:0] }
 * hm (Hot Mind): 16x16 as Excelsior, 512 entries, x - 9 and y - 8 more (MAME m_xoffset / m_yoffset), 32 colours.
 * Line buffer output { pri[1:0], colour[4:0], pen[3:0] }, cleared as it is read. */

module jtplaymark_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              exc,         // Excelsior: 16x16, 416 entries   Big Twin: 32x32, 128 entries
    input              hm,          // Hot Mind (16x16, set exc too)
    input       [ 8:0] hdump,
    input              hs_start,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    // CPU writes to the sprite RAM
    input       [11:1] cpu_addr,
    input       [15:0] cpu_dout,
    input       [ 1:0] oram_we,

    output      [20:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [10:0] pxl
);

localparam [2:0] IDLE=0, SCAN=1, FETCH=2, FWAIT=3, DRAW=4;

reg  [ 2:0] st;
reg  [ 8:0] ent, t1;
reg         t1v, lbuf;
reg  [ 8:0] line;
reg  [15:0] c1, c2;
reg         fx;
reg  [ 4:0] dy;
reg  [ 1:0] xg, wcnt;
reg  [ 2:0] px;
reg  [31:0] wa;
wire [15:0] q1, q2, q3;
wire [ 8:0] last = hm ? 9'd511 : exc ? 9'd415 : 9'd127;
wire [ 7:0] sy   = (exc ? 8'd232 : 8'd216) - q3[7:0];
wire [ 8:0] dyw  = line + (hm ? 9'd8 : 9'd0) - { 1'b0, sy };
wire        hit  = exc ? dyw < 9'd16 : dyw < 9'd32;
wire        done = q3 == 16'h2000 || t1 > last;
wire [ 1:0] xs   = xg ^ { 2{fx} };                   // source column group
wire [ 2:0] b    = fx ? px : ~px;
wire [ 3:0] pen  = { wa[24+b], wa[16+b], wa[8+b], wa[b] };
wire [ 9:0] wx   = { 1'b0, c1[8:0] } - (hm ? 10'd32 : 10'd23) + { 5'd0, exc ? 1'b0 : xg[1], xg[0], px };
wire [ 4:0] col  = c1[13:9];
wire [ 1:0] pri  = c1[15] ? 2'd1 : col[3:2]==2'b11 ? 2'd2 : 2'd0;
wire [ 1:0] nw   = exc ? 2'd1 : 2'd3;                // words per row - 1

assign rom_addr = exc ? { c2[15:14] & {2{~hm}}, c2[13:2], xs[0], dy[3:0] } : { 2'd0, c2[13:4], dy[4], xs, dy[3:0] };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; t1v <= 0;
    end else begin
        t1 <= ent;
        case( st )
            IDLE: begin
                t1v <= 0;
                if( hs_start && vrender < 9'd256 ) begin
                    line <= vrender;
                    lbuf <= vrender[0];
                    ent  <= 1;
                    st   <= SCAN;
                end
            end
            SCAN: begin
                ent <= ent + 1'd1;
                t1v <= 1;
                if( t1v ) begin
                    if( done ) begin
                        st <= IDLE;
                    end else if( hit ) begin
                        c1 <= q1; c2 <= q2;
                        fx <= q3[14];
                        dy <= dyw[4:0];
                        xg <= 0;
                        ent <= t1 + 1'd1;
                        t1v <= 0;
                        st  <= FETCH;
                    end
                end
            end
            FETCH: begin wcnt <= 0; st <= FWAIT; end
            FWAIT: begin
                rom_cs <= 1;
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    wa <= rom_data; px <= 0; st <= DRAW;
                end
            end
            DRAW: begin
                px <= px + 1'd1;
                if( px==7 ) begin
                    xg <= xg + 1'd1;
                    st <= xg==nw ? SCAN : FETCH;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

// copies of words 1-3 of every entry
wire [8:0] wr_ent = cpu_addr[11:3];
jtframe_dual_ram16 #(.AW(9)) u_w1(
    .clk0(clk), .data0(cpu_dout), .addr0(wr_ent), .we0(cpu_addr[2:1]==2'd1 ? oram_we : 2'b00), .q0(),
    .clk1(clk), .data1(16'd0), .addr1(ent), .we1(2'b00), .q1(q1) );
jtframe_dual_ram16 #(.AW(9)) u_w2(
    .clk0(clk), .data0(cpu_dout), .addr0(wr_ent), .we0(cpu_addr[2:1]==2'd2 ? oram_we : 2'b00), .q0(),
    .clk1(clk), .data1(16'd0), .addr1(ent), .we1(2'b00), .q1(q2) );
jtframe_dual_ram16 #(.AW(9)) u_w3(
    .clk0(clk), .data0(cpu_dout), .addr0(wr_ent), .we0(cpu_addr[2:1]==2'd3 ? oram_we : 2'b00), .q0(),
    .clk1(clk), .data1(16'd0), .addr1(ent - 9'd1), .we1(2'b00), .q1(q3) );

jtframe_dual_ram #(.DW(11),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { pri, col, pen } ),
    .addr0  ( { lbuf, wx[8:0] } ),
    .we0    ( st==DRAW && pen!=0 && !wx[9] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 11'd0     ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( pxl_cen   ),
    .q1     ( pxl       )
);

endmodule
