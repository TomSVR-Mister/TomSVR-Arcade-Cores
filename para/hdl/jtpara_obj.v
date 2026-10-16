/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Paradise-family sprites (MAME paradise.cpp): entries of 4 bytes
 *   0: code low, 1: X, 2: Y + 2, 3: code high. 16x16x8, no colour, no flip, pen 0xff transparent,
 *   X wraps around at 256. Later entries are drawn over earlier ones.
 *   Paradise: 64 entries every 32 bytes. Target Ball (inc4): 64 entries every 4 bytes.
 *   Torus map (many): 512 entries every 4 bytes.
 * Sprite ROM (inverted): low nibble from the first half, high nibble from the second half (512 kB apart in SDRAM).
 *   Paradise layout: 128 bytes per tile and half, quadrants TL, TR, BL, BR of 8x8x4 packed pixels.
 *   Torus layout (tlay): 8 bytes per row (left 8 pixels, right 8 pixels).
 *   spr1m: 4096 tiles (Penky), otherwise 2048. */

module jtpara_obj(
    input              rst,
    input              clk,
    input              flip,
    input              inc4,
    input              many,
    input              tlay,
    input              spr1m,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output reg  [10:0] ram_addr,
    input       [ 7:0] ram_dout,

    output reg  [19:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [3:0] IDLE=0, CLR=1, SCAN=2, R1=3, R2=4, R3=5, R4=6, FETCH=7, FWAIT=8, WRITE=9;

reg  [ 3:0] st;
reg  [ 7:0] line, x, lo;
reg  [ 9:0] aidx;           // next entry to address (bit 9 = done)
reg  [ 8:0] hit, p1_idx, p2_idx;
reg         p1_v, p2_v;
reg  [11:0] code;
reg  [ 3:0] ydiff;
wire [ 8:0] ydiff_nx = { 1'b0, line } - ({ 1'b0, ram_dout } - 9'd2);
reg         lbuf;
reg  [ 1:0] wcnt, fidx;
reg  [31:0] w[0:3];         // A-left, B-left, A-right, B-right
reg  [ 3:0] px;
reg  [ 7:0] clr;
reg         start, hzero_l;
wire [31:0] wa = w[{px[3],1'b0}], wb = w[{px[3],1'b1}];
wire [ 7:0] ba = wa[8*px[2:1]+:8], bb = wb[8*px[2:1]+:8];
wire [ 7:0] pen = { px[0] ? bb[3:0] : bb[7:4], px[0] ? ba[3:0] : ba[7:4] };
wire [ 7:0] rd_h = flip ? ~hdump[7:0] : hdump[7:0];
wire [ 9:0] last = many ? 10'd511 : 10'd63;
reg  [ 8:0] waddr;
reg  [ 7:0] wdata;
reg         we;

function [10:0] eaddr( input [8:0] idx, input [1:0] k );
    eaddr = inc4 ? { idx, k } : { idx[5:0], 3'd0, k };
endfunction

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

always @* begin
    we    = 0;
    waddr = { lbuf, clr };
    wdata = 8'hff;
    if( st==CLR ) we = 1;
    if( st==WRITE ) begin
        waddr = { lbuf, x + {4'd0, px} };
        wdata = pen;
        we    = pen != 8'hff;
    end
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; p1_v <= 0; p2_v <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                line <= flip ? ~vrender[7:0] : vrender[7:0];
                lbuf <= vrender[0];
                clr  <= 0;
                st   <= CLR;
            end
            CLR: begin
                clr <= clr + 1'd1;
                if( clr==8'hff ) begin
                    aidx <= 0; p1_v <= 0; p2_v <= 0;
                    st   <= SCAN;
                end
            end
            // Y bytes are requested every clock and checked two clocks later (BRAM latency)
            SCAN: begin
                ram_addr <= eaddr( aidx[8:0], 2'd2 );
                p1_idx   <= aidx[8:0];
                p1_v     <= !aidx[9];
                p2_idx   <= p1_idx;
                p2_v     <= p1_v;
                if( !aidx[9] ) aidx <= aidx==last ? 10'h200 : aidx + 1'd1;
                if( p2_v && ydiff_nx[8:4]==0 ) begin
                    ydiff    <= ydiff_nx[3:0];
                    hit      <= p2_idx;
                    ram_addr <= eaddr( p2_idx, 2'd0 );
                    st       <= R1;
                end else if( !p2_v && !p1_v && aidx[9] ) begin
                    st <= IDLE;
                end
            end
            R1: begin ram_addr <= eaddr( hit, 2'd1 ); st <= R2; end
            R2: begin ram_addr <= eaddr( hit, 2'd3 ); lo <= ram_dout; st <= R3; end
            R3: begin x <= ram_dout; st <= R4; end
            R4: begin
                code <= spr1m ? { ram_dout[3:0], lo } : { 1'b0, ram_dout[2:0], lo };
                fidx <= 0;
                st   <= FETCH;
            end
            FETCH: begin
                // { half, code, quadrant row / row, right }
                rom_addr <= tlay ? { fidx[0], code, ydiff, fidx[1] }
                                 : { fidx[0], code, ydiff[3], fidx[1], ydiff[2:0] };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs  <= 0;
                    w[fidx] <= ~rom_data;
                    fidx    <= fidx + 1'd1;
                    if( fidx==3 ) begin px <= 0; st <= WRITE; end
                    else st <= FETCH;
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                if( px==15 ) begin
                    aidx <= { 1'b0, hit }==last ? 10'h200 : { 1'b0, hit } + 1'd1;
                    p1_v <= 0;
                    p2_v <= 0;
                    st   <= SCAN;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(9)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( wdata     ),
    .addr0  ( waddr     ),
    .we0    ( we        ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], rd_h } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
