/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Afega background (MAME nmk16 afega grdnstrm video): 256x32 tiles of 16x16x8, opaque, palette 0-255.
 *   Map index (tilemap_scan_pages): { row[4], col[7:0], row[3:0] }. Tile = video RAM word, modulo the ROM size:
 *   tmod 0: 12288 tiles (3 MB), 1: 16384 (4 MB), 2: 4096 (1 MB).
 * Graphics in SDRAM: the two ROM halves (MAME RGN_FRAC(1,2)) byte-interleaved: byte 2k = first half byte k (pen bits 7-4),
 *   byte 2k+1 = second half byte k (pen bits 3-0). Each byte holds two pixels, the left one in the high nibble.
 *   8 pixels = two 32-bit words at { tile, x[3], y[3:0], word }.
 * The 33 8-pixel columns covering the next line go into a 512-pixel ping-pong line buffer indexed by map x mod 512. */

module jtafega_bg(
    input              rst,
    input              clk,
    input       [ 1:0] tmod,
    input       [ 8:0] hdump,
    input              hs_start,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [11:0] scrx,
    input       [ 8:0] scry,

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
reg  [ 8:0] mapy;
reg  [ 8:0] sx[0:1];
reg  [ 8:0] col;            // map x / 8
reg  [ 5:0] cnt;
reg  [13:0] tile;
reg         lbuf, wsel;
reg  [ 1:0] wcnt;
reg  [31:0] wa, wb;
reg  [ 2:0] px;
reg  [ 1:0] up;
wire [31:0] wsh = px[2] ? wb : wa;
wire [ 7:0] fb  = wsh[ {px[1],4'd0}   +: 8 ];
wire [ 7:0] sb  = wsh[ {px[1],4'd8}   +: 8 ];
wire [ 7:0] pen = px[0] ? { fb[3:0], sb[3:0] } : { fb[7:4], sb[7:4] };
wire [ 8:0] rd_x = hdump + sx[vdump[0]];

assign vram_addr = { mapy[8], col[8:1], mapy[7:4] };
assign rom_addr  = { tile, col[0], mapy[3:0], wsel };

always @* begin
    case( tmod )
        0: case( vram_dout[15:12] )     // code / 4096 mod 3
            0,3,6,9,12,15: up = 0;
            1,4,7,10,13:   up = 1;
            default:       up = 2;
        endcase
        1: up = vram_dout[13:12];
        default: up = 0;
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0;
    end else begin
        case( st )
            IDLE: if( hs_start ) begin
                mapy <= vrender + scry;
                lbuf <= vrender[0];
                sx[vrender[0]] <= scrx[8:0];
                col  <= scrx[11:3];
                cnt  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin       // two clocks of BRAM latency
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin
                    tile <= { up, vram_dout[11:0] };
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
                    st   <= cnt==32 ? IDLE : RD;
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
