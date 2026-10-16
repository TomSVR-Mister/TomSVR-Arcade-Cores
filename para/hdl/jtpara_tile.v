/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Paradise fixed 32x32 tilemap of 8x8 tiles (MAME paradise.cpp). Code = vram[i] | vram[i+0x400] << 8.
 *   B8=0: 8x8x4 packed (gfx_8x8x4_packed_msb), 32 bytes per tile, one 32-bit word per row
 *   B8=1: 8x8x8 (layout_8x8x8): low nibble from the first half of the region, high nibble from the second half
 * Graphics ROMs are stored inverted (ROMREGION_INVERT): data is complemented here.
 * The next line is rendered into a ping-pong line buffer during the current line. */

module jtpara_tile #(parameter B8=0, AW=18, HALF=18'h20000)(
    input              rst,
    input              clk,
    input              flip,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output      [10:0] vram_addr,
    input       [ 7:0] vram_dout,

    output reg [AW-1:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [AW-3:0] HALFW = HALF[AW-1:2];
localparam [2:0] IDLE=0, LO=1, HI=2, FETCH=3, FWAIT=4, WRITE=5;

reg  [ 2:0] st;
reg  [ 7:0] line, lo;
reg  [ 4:0] col;
reg  [15:0] code;
reg         lbuf, part, hi_sel;
reg  [ 1:0] wcnt;
reg  [31:0] wa, wb;
reg  [ 2:0] px;
reg         start, hzero_l;
wire [ 7:0] ba = wa[8*px[2:1]+:8], bb = wb[8*px[2:1]+:8];
wire [ 3:0] na = px[0] ? ba[3:0] : ba[7:4], nb = px[0] ? bb[3:0] : bb[7:4];
wire [ 7:0] pen = B8 ? { nb, na } : { 4'd0, na };
wire [ 7:0] rd_h = flip ? ~hdump[7:0] : hdump[7:0];

assign vram_addr = { hi_sel, line[7:3], col };

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; hi_sel <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                line   <= flip ? ~vrender[7:0] : vrender[7:0];
                lbuf   <= vrender[0];
                col    <= 0;
                hi_sel <= 0;
                wcnt   <= 0;
                st     <= LO;
            end
            LO: begin       // two clocks of BRAM latency
                wcnt <= wcnt + 1'd1;
                if( wcnt==1 ) begin lo <= vram_dout; hi_sel <= 1; wcnt <= 0; st <= HI; end
            end
            HI: begin
                wcnt <= wcnt + 1'd1;
                if( wcnt==1 ) begin code <= { vram_dout, lo }; hi_sel <= 0; part <= 0; st <= FETCH; end
            end
            FETCH: begin
                // codes wrap within one half (MAME RGN_FRAC(1,2))
                rom_addr <= B8 ? ((part ? HALFW : {AW-2{1'b0}}) | ({ code, line[2:0] } & (HALFW - 1'd1)))
                               : { code, line[2:0] };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    if( !part ) wa <= ~rom_data; else wb <= ~rom_data;
                    if( B8 && !part ) begin
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
                    st   <= col==31 ? IDLE : LO;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(9)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( pen       ),
    .addr0  ( { lbuf, col, px } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], rd_h } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
