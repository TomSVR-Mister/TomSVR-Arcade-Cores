/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * VISYS tilemap (MAME oneshot.cpp): 32x32 tiles of 16x16x8, tile number = video RAM word idx*2+1,
 *   pen 0 transparent, no X scroll, Y scroll = scr (mid layer only).
 * Graphics in SDRAM: 8x8 tile n, row r = two 32-bit words { n, r, w }; byte k of the 64-bit row = pen bit 7-k,
 *   leftmost pixel in each byte's MSB. A 16x16 tile t = 8x8 tiles 4t (TL), 4t+1 (TR), 4t+2 (BL), 4t+3 (BR).
 * The next line (320 pixels) is rendered into a ping-pong line buffer. */

module jtmadd_tile(
    input              rst,
    input              clk,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [ 8:0] scr,

    output      [11:1] vram_addr,
    input       [15:0] vram_dout,

    output reg  [21:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [2:0] IDLE=0, RD=1, FETCH=2, FWAIT=3, WRITE=4;

reg  [ 2:0] st;
reg  [ 8:0] mapy;
reg  [ 4:0] col;
reg  [13:0] code;
reg         lbuf, half, wsel;
reg  [ 1:0] wcnt;
reg  [31:0] wa, wb;
reg  [ 2:0] px;
reg         start, hzero_l;
wire [ 2:0] b = ~px;
wire [ 7:0] pen = { wa[b], wa[8+b], wa[16+b], wa[24+b], wb[b], wb[8+b], wb[16+b], wb[24+b] };

assign vram_addr = { mapy[8:4], col, 1'b1 };

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
                mapy <= vrender + scr;
                lbuf <= vrender[0];
                col  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin       // two clocks of BRAM latency
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin code <= vram_dout[13:0]; half <= 0; wsel <= 0; st <= FETCH; end
            end
            FETCH: begin
                rom_addr <= { code, mapy[3], half, mapy[2:0], wsel };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
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
                    wsel <= 0;
                    if( !half ) begin
                        half <= 1;
                        st   <= FETCH;
                    end else begin
                        col  <= col + 1'd1;
                        wcnt <= 0;
                        st   <= col==19 ? IDLE : RD;
                    end
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( pen       ),
    .addr0  ( { lbuf, col, half, px } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
