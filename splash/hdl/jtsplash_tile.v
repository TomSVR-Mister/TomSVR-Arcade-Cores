/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Splash! tilemaps (MAME splash_v.cpp). Both are transparent on pen 0.
 *   B16=0, tilemap 0: 64x32 tiles of 8x8, word = { colour, code[11:8], code[7:0] },
 *                     tile = code + 0x2000, X scroll fixed at 4, Y scroll = scr
 *   B16=1, tilemap 1: 32x32 tiles of 16x16 at video RAM word 0x800, word = { colour, code[9:6], code[5:0], flipx, flipy },
 *                     tile = code + 0xc00, no X scroll, Y scroll = scr
 * Graphics in SDRAM: 32-bit words, byte k = bit plane k (byte 0 = pen bit 3), leftmost pixel in the MSB.
 *   8x8: word { code, row }; 16x16: word { code, right half, row }.
 * The line after the current one is rendered (whole 512-pixel map row) into a ping-pong line buffer. */

module jtsplash_tile #(parameter B16=0)(
    input              rst,
    input              clk,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [15:0] scr,

    output      [12:1] vram_addr,
    input       [15:0] vram_dout,

    output reg  [18:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl          // { colour, pen }
);

localparam [2:0] IDLE=0, RD=1, FETCH=2, FWAIT=3, WRITE=4;

reg  [ 2:0] st;
reg  [ 8:0] mapy;
reg  [ 5:0] col;
reg  [15:0] attr;
reg         lbuf, half;
reg  [ 1:0] wcnt;
reg  [31:0] w;
reg  [ 2:0] px;
reg         start, hzero_l;
wire        flipx = B16 && attr[1];     // MAME TILE_FLIPXY: bit 1 = X, bit 0 = Y
wire        flipy = B16 && attr[0];
wire [ 3:0] row   = B16 ? (mapy[3:0] ^ {4{flipy}}) : { 1'b0, mapy[2:0] };
wire [ 2:0] bx    = flipx ? px : ~px;          // bit inside each plane byte
wire [ 4:0] b5    = { 2'd0, bx };
wire [ 3:0] pen   = { w[b5], w[5'd8+b5], w[5'd16+b5], w[5'd24+b5] };
wire [ 8:0] waddr = B16 ? { col[4:0], half, px } : { col, px };
wire [ 8:0] rd_x  = B16 ? hdump : hdump + 9'd4;

assign vram_addr = B16 ? { 2'b10, mapy[8:4], col[4:0] } : { 1'b0, mapy[7:3], col };

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
                mapy <= vrender + scr[8:0];
                lbuf <= vrender[0];
                col  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin       // two clocks of BRAM latency
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin attr <= vram_dout; half <= 0; st <= FETCH; end
            end
            FETCH: begin
                rom_addr <= B16 ? { 2'b11, attr[11:8], attr[7:2], half ^ flipx, row }
                                : { 2'b10, attr[11:0], row[2:0] };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    w      <= rom_data;
                    px     <= 0;
                    st     <= WRITE;
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                if( px==7 ) begin
                    if( B16 && !half ) begin
                        half <= 1;
                        st   <= FETCH;
                    end else begin
                        col  <= col + 1'd1;
                        wcnt <= 0;
                        st   <= (B16 ? col[4:0]==31 : col==63) ? IDLE : RD;
                    end
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { attr[15:12], pen } ),
    .addr0  ( { lbuf, waddr } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], rd_x } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
