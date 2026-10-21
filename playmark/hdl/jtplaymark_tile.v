/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Playmark tile layer (MAME playmark_v.cpp bigtwin fg / tx): tile maps with 2 words per tile (code, colour),
 * 16x16 tiles in 32x32 (512x512) or 8x8 tiles in 64x32 (512x256), rows in order (TILEMAP_SCAN_ROWS).
 * Graphics: 4 planes in quarters of the ROM, interleaved in SDRAM so one 32-bit word = 8 pixels of a row,
 *   byte k = plane k (plane 3 = pen bit 3), leftmost pixel in bit 7.
 *   32 bytes per tile and plane: 16x16 word at { tile, x[3], y[3:0] }, 8x8 word at { tile, 2'b00, y[2:0] }
 * The 41 8-pixel columns covering the next line go into a 512-pixel ping-pong line buffer indexed by map x mod 512.
 * one (Hard Times board, MAME hrdtimes_get_*_tile_info): 1 word per tile, colour = bits 15-13 (c4: 15-12), ROM word =
 *   tbase + { code & tmask, x[3], y[3:0] } (16x16) or tbase + { code & tmask, y[2:0] } (8x8, 64x64 map).
 * page (Hard Times fg): 128x32 map of four 32x32 pages (MAME playmark_tilemap_scan_pages), x scroll 0-2047.
 * Output { colour[3:0], pen[3:0] }. */

module jtplaymark_tile(
    input              rst,
    input              clk,
    input              t16,         // 1: 16x16 tiles, 32 columns   0: 8x8 tiles, 64 columns
    input              c14,         // 1: 16384 tiles in the ROM   0: 8192
    input              one,         // 1 word per tile (Hot Mind)
    input              c4,          // 4-bit colour (Big Twin No Girls text)
    input              page,
    input       [18:0] tbase,
    input       [12:0] tmask,
    input       [ 8:0] hdump,
    input              hs_start,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [10:0] scrx,
    input       [ 8:0] scry,

    output      [12:1] vram_addr,
    input       [15:0] vram_dout,

    output      [20:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [2:0] IDLE=0, RD=1, FETCH=2, FWAIT=3, WRITE=4;

reg  [ 2:0] st;
reg  [ 8:0] mapy;
reg  [ 8:0] sx[0:1];
reg  [ 7:0] col;            // map x / 8
reg  [ 5:0] cnt;
reg  [15:0] code;
reg  [ 3:0] color;
reg         lbuf, wsel;
reg  [ 1:0] wcnt;
reg  [31:0] wa;
reg  [ 2:0] px;
wire [ 2:0] b   = ~px;
wire [ 3:0] pen = { wa[24+b], wa[16+b], wa[8+b], wa[b] };
wire [ 8:0] rd_x = hdump + sx[vdump[0]];
// tile index: 16x16 -> row * 32 + col, 8x8 -> row * 64 + col; 2 words per tile (1 for Hot Mind, 64x64 8x8 map)
wire [10:0] tidx = t16 ? { 1'b0, mapy[8:4], col[5:1] } : { mapy[7:3], col[5:0] };
wire [11:0] hidx = t16 ? { page ? col[7:6] : 2'b0, mapy[8:4], col[5:1] } : { mapy[8:3], col[5:0] };

assign vram_addr = one ? hidx : { tidx, wsel };
wire [13:0] tcode = { code[13] & c14, code[12:0] };
wire [12:0] mcode = code[12:0] & tmask;
assign rom_addr  = one ? tbase + ( t16 ? { 1'b0, mcode, col[0], mapy[3:0] } : { 3'd0, mcode, mapy[2:0] } ) :
                   t16 ? { tcode, col[0], mapy[3:0] } : { tcode, 2'd0, mapy[2:0] };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0;
    end else begin
        case( st )
            IDLE: if( hs_start ) begin
                mapy <= vrender + scry;
                lbuf <= vrender[0];
                sx[vrender[0]] <= scrx[8:0];
                col  <= scrx[10:3];
                cnt  <= 0;
                wcnt <= 0;
                wsel <= 0;
                st   <= RD;
            end
            RD: begin       // code then colour, one clock of BRAM latency each
                wcnt <= wcnt + 1'd1;
                if( wcnt==1 ) begin
                    code <= vram_dout; wsel <= 1;
                    if( one ) begin color <= c4 ? vram_dout[15:12] : { 1'b0, vram_dout[15:13] }; wsel <= 0; st <= FETCH; end
                end
                if( wcnt==3 ) begin color <= { 1'b0, vram_dout[2:0] }; wsel <= 0; st <= FETCH; end
            end
            FETCH: begin wcnt <= 0; st <= FWAIT; end
            FWAIT: begin
                rom_cs <= 1;
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    wa <= rom_data; px <= 0; st <= WRITE;
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
    .data0  ( { color, pen } ),
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
