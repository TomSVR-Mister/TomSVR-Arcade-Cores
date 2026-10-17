/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 8-bit tilemaps (MAME yunsung8.cpp): fixed 64x32 maps of 8x8 tiles, code = { hi, lo }, colour RAM byte.
 *   BG8=1: background 8 bits per pixel, colour 3 bits. SDRAM: two 32-bit words per tile row (MRA interleave of the 4 ROM
 *          quarters in 16-bit units): word 0 = { Q1b1, Q1b0, Q0b1, Q0b0 }, word 1 = { Q3.., Q2.. }; pixel x: quarter x[1:0], byte x[2]
 *   BG8=0: text layer 4 bits per pixel, colour 6 bits, pen 0 transparent. SDRAM word = { B1, B0, A1, A0 } (16-bit interleave
 *          of the two halves); pixels: B0 lo, B0 hi, A0 lo, A0 hi, B1 lo, B1 hi, A1 lo, A1 hi
 * Output: { colour, pen } as an 11-bit palette index. Flip mirrors both axes of the 512x256 map. */

module jtys8_tile #(parameter BG8=1, AW=21)(
    input              rst,
    input              clk,
    input              flip,
    input              big,             // BG8: 32768 tiles, otherwise 16384
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output      [10:0] vram_addr,
    input       [ 7:0] lo_dout, hi_dout, col_dout,

    output reg [AW-1:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [10:0] pxl
);

localparam [2:0] IDLE=0, RD=1, FETCH=2, FWAIT=3, WRITE=4;

reg  [ 2:0] st, px;
reg  [ 7:0] line;
reg  [ 5:0] col;
reg  [15:0] code;
reg  [ 5:0] color;
reg  [ 1:0] wcnt;
reg  [31:0] w0, w1;
reg         lbuf, part, start, hzero_l;
wire [31:0] wsel   = BG8 ? (px[1] ? w1 : w0) : w0;
wire [ 1:0] bidx   = BG8 ? { px[0], px[2] } : { ~px[1], px[2] };
wire [ 7:0] byte8  = wsel[ 8*bidx +: 8 ];
wire [ 7:0] pen    = BG8 ? byte8 : { 4'd0, px[0] ? byte8[7:4] : byte8[3:0] };
wire [10:0] wdata  = BG8 ? { color[2:0], pen } : { 1'b0, color, pen[3:0] };
wire [ 8:0] rd_x   = flip ? ~hdump : hdump;

assign vram_addr = { line[7:3], col };

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                line <= flip ? ~vrender[7:0] : vrender[7:0];
                lbuf <= vrender[0];
                col  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin
                    code  <= { hi_dout, lo_dout } & (BG8 ? (big ? 16'h7fff : 16'h3fff) : 16'h1fff);
                    color <= col_dout[5:0];
                    part  <= 0;
                    st    <= FETCH;
                end
            end
            FETCH: begin
                if( BG8 ) rom_addr <= { code[14:0], line[2:0], part };
                else      rom_addr <= { code[12:0], line[2:0] };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    if( !part ) w0 <= rom_data; else w1 <= rom_data;
                    if( BG8 && !part ) begin
                        part <= 1;
                        st   <= FETCH;
                    end else begin
                        px <= 0;
                        st <= WRITE;
                    end
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                if( px==7 ) begin
                    col  <= col + 1'd1;
                    wcnt <= 0;
                    st   <= col==63 ? IDLE : RD;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(11),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( wdata     ),
    .addr0  ( { lbuf, col, px } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 11'd0     ),
    .addr1  ( { vdump[0], rd_x } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
