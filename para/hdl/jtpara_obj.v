/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Paradise sprites (MAME paradise.cpp, sprite_inc 0x20): 64 entries every 32 bytes:
 *   0: code low, 1: X, 2: Y + 2, 3: code high. 16x16x8 (layout_16x16x8), no colour, no flip, pen 0xff transparent,
 *   X wraps around at 256. Later entries are drawn over earlier ones.
 * Sprite ROM (inverted): low nibble from the first half (256 kB), high nibble from the second half;
 * each half holds 128 bytes per tile: quadrants TL, TR, BL, BR of 8x8x4 packed pixels. */

module jtpara_obj(
    input              rst,
    input              clk,
    input              flip,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output reg  [10:0] ram_addr,
    input       [ 7:0] ram_dout,

    output reg  [18:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [3:0] IDLE=0, CLR=1, R0=2, R1=3, R2=4, R3=5, R4=6, CHK=7, FETCH=8, FWAIT=9, WRITE=10;

reg  [ 3:0] st;
reg  [ 7:0] line, x, lo;
reg  [ 5:0] idx;
reg  [10:0] code;
reg  [ 8:0] ydiff;
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
reg  [ 8:0] waddr;
reg  [ 7:0] wdata;
reg         we;

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
        st <= IDLE; rom_cs <= 0;
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
                if( clr==8'hff ) begin idx <= 0; st <= R0; end
            end
            // read bytes 0..3 of the entry (BRAM data two clocks after the address)
            R0: begin ram_addr <= { idx, 5'd0 }; st <= R1; end
            R1: begin ram_addr <= { idx, 5'd1 }; st <= R2; end
            R2: begin ram_addr <= { idx, 5'd2 }; lo   <= ram_dout; st <= R3; end
            R3: begin ram_addr <= { idx, 5'd3 }; x    <= ram_dout; st <= R4; end
            R4: begin ydiff <= { 1'b0, line } - ({ 1'b0, ram_dout } - 9'd2); st <= CHK; end
            CHK: begin
                code <= { ram_dout[2:0], lo };
                if( ydiff[8:4]==0 ) begin
                    fidx <= 0;
                    st   <= FETCH;
                end else begin
                    idx <= idx + 1'd1;
                    st  <= idx==63 ? IDLE : R0;
                end
            end
            FETCH: begin
                // { half, code, bottom, right, row }
                rom_addr <= { fidx[0], code, ydiff[3], fidx[1], ydiff[2:0] };
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
                    idx <= idx + 1'd1;
                    st  <= idx==63 ? IDLE : R0;
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
