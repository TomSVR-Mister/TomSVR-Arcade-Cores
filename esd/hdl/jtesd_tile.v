/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * ESD 16-bit tilemap (MAME esd16.cpp): 128x64 tiles of 8x8x8, or 64x64 tiles of 16x16x8 (layer size register).
 *   Tile code = video RAM word. A 16x16 tile is four 8x8 ones: code * 4 + (y >= 8) * 2 + (x >= 8).
 *   Codes wrap at the ROM size (4 MB: 65536 8x8 / 16384 16x16 tiles; 2 MB with t2m).
 * Graphics in SDRAM: the MAME region as is, one byte per pixel, 8 bytes per tile row (two 32-bit words).
 * The 41 8-pixel columns covering the next line are rendered into a 512-pixel ping-pong line buffer
 * indexed by map x modulo 512. */

module jtesd_tile(
    input              rst,
    input              clk,
    input              big,
    input              t2m,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [ 9:0] scrx,
    input       [ 9:0] scry,

    output      [13:1] vram_addr,
    input       [15:0] vram_dout,

    output      [21:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [2:0] IDLE=0, RD=1, FETCH=2, FWAIT=3, WRITE=4;

reg  [ 2:0] st;
reg  [ 9:0] mapy;
reg  [ 8:0] sx[0:1];
reg  [ 6:0] col;
reg  [ 5:0] cnt;
reg  [15:0] code;
reg         lbuf, wsel;
reg  [ 1:0] wcnt;
reg  [31:0] wa, wb;
reg  [ 2:0] px;
reg         start, hzero_l;
wire [31:0] wsh = px[2] ? wb : wa;
wire [ 7:0] pen = wsh[ {px[1:0],3'd0} +: 8 ];
wire [ 8:0] rd_x = hdump + sx[vdump[0]];

assign vram_addr = big ? { 1'b0, mapy[9:4], col[6:1] } : { mapy[8:3], col };
assign rom_addr  = { code, mapy[2:0], wsel };

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
                mapy <= { 1'b0, vrender } + scry;
                lbuf <= vrender[0];
                sx[vrender[0]] <= scrx[8:0];
                col  <= scrx[9:3];
                cnt  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin       // two clocks of BRAM latency
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin
                    code <= big ? { vram_dout[13:0], mapy[3], col[0] } : vram_dout;
                    if( t2m ) code[15] <= 0;
                    wsel <= 0;
                    st   <= FETCH;
                end
            end
            FETCH: begin
                wcnt  <= 0;
                st    <= FWAIT;
            end
            FWAIT: begin
                rom_cs <= 1;
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    if( wsel ) begin wb <= rom_data; px <= 0; st <= WRITE; end
                    else begin wa <= rom_data; wsel <= 1; st <= FETCH; end
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                if( px==7 ) begin
                    col  <= col + 1'd1;
                    cnt  <= cnt + 1'd1;
                    wcnt <= 0;
                    st   <= cnt==40 ? IDLE : RD;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( pen       ),
    .addr0  ( { lbuf, col[5:0], px } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], rd_x } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
