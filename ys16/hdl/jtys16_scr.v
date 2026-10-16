/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 16 scroll layer (MAME yunsun16.cpp):
 *   64x64 tiles of 16x16x8, arranged as 4x4 pages of 16x16 tiles; tile index
 *   = row[5:4], col[5:0], row[3:0]. Each tile is two words: code, attr (colour 3:0, flip X bit 5).
 *   Pen 0xff is transparent. Screen pixel (x,y) shows tilemap (x + DX + scrollx, y + 16 + scrolly).
 * The next line is rendered into a ping-pong line buffer during the current line. */

module jtys16_scr #(parameter [9:0] DX=10'h34)(
    input              rst,
    input              clk,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [15:0] scrx,
    input       [15:0] scry,

    output      [13:1] vram_addr,
    input       [15:0] vram_dout,

    output reg  [21:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [11:0] pxl          // {colour, pen}; pen ff = transparent
);

localparam [3:0] IDLE=0, C0=1, C1=2, C2=3, A1=4, A2=5, FETCH=6, FWAIT=7, WRITE=8;

reg  [ 3:0] st;
reg  [ 9:0] tmy, xs;
reg  [ 4:0] t;
reg  [ 5:0] col;
reg  [15:0] code;
reg  [ 3:0] color;
reg         flipx, lbuf, attr_sel;
reg  [ 1:0] fidx, wcnt;
reg  [31:0] w[0:3];
reg  [ 3:0] px;
reg  [ 9:0] sx;
reg  [ 7:0] pen;
reg         start, hzero_l;
wire [ 3:0] tp = flipx ? ~px : px;
wire [31:0] a = w[{tp[3],1'b0}], b = w[{tp[3],1'b1}];
wire [ 2:0] bx = 3'd7 - tp[2:0];
wire [11:0] idx = { tmy[9:8], col, tmy[7:4] };

assign vram_addr = { idx, attr_sel };

always @* begin
    // byte order in each 32-bit word: { b3, b2, b1, b0 } (A = bytes 0-3, B = bytes 4-7)
    // pixel bits, MSB first: b6, b4, b2, b0, b7, b5, b3, b1 (MAME layout_16x16x8)
    pen = { b[16+bx], b[bx], a[16+bx], a[bx], b[24+bx], b[8+bx], a[24+bx], a[8+bx] };
end

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

always @(posedge clk) begin
    if( rst ) begin
        st     <= IDLE;
        rom_cs <= 0;
        attr_sel <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                tmy  <= vrender[7:0] + 10'h10 + scry[9:0];
                xs   <= DX + scrx[9:0];
                lbuf <= vrender[0];
                t    <= 0;
                st   <= C0;
            end
            C0: begin
                col      <= xs[9:4] + {1'b0,t};
                attr_sel <= 0;
                st       <= C1;
            end
            C1: st <= C2;           // BRAM latency
            C2: begin
                st <= A1;
            end
            A1: begin
                code     <= vram_dout;
                attr_sel <= 1;
                st       <= A2;
                wcnt     <= 0;
            end
            A2: begin
                if( wcnt==2 ) begin
                    color <= vram_dout[3:0];
                    flipx <= vram_dout[5];
                    fidx  <= 0;
                    st    <= FETCH;
                end else wcnt <= wcnt + 1'd1;
            end
            FETCH: begin
                rom_addr <= { code[13:0], tmy[3:0], fidx };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    w[fidx] <= rom_data;
                    rom_cs  <= 0;
                    fidx    <= fidx + 1'd1;
                    if( fidx==3 ) begin
                        px <= 0;
                        sx <= { 1'b0, t, 4'd0 } - { 6'd0, xs[3:0] };
                        st <= WRITE;
                    end else st <= FETCH;
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                sx <= sx + 1'd1;
                if( px==15 ) begin
                    t  <= t + 1'd1;
                    st <= t==24 ? IDLE : C0;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

wire we = st==WRITE && !sx[9];

jtframe_dual_ram #(.DW(12),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { color, pen } ),
    .addr0  ( { lbuf, sx[8:0] } ),
    .we0    ( we        ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 12'd0     ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
