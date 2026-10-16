/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gumbo tilemaps (MAME gumbo.cpp), no scroll, word = tile number, 8 bits per pixel (pen = byte):
 *   SMALL=0: background, 64x32 tiles of 8x8. SDRAM: per tile row two 32-bit words, A (pixels 0,2,4,6) then
 *            B (pixels 1,3,5,7) = the two halves of the MAME region interleaved by the MRA. word = { code, row, B }
 *   SMALL=1: foreground, 128x64 tiles of 4x4. SDRAM: one 32-bit word per tile row { B1, B0, A1, A0 }
 *            (pixels 0..3 = A0, B0, A1, B1). word = { code, row }
 *   big = 0: codes wrap at 16384 tiles, big = 1: at 32768.
 * The next line is rendered into a ping-pong line buffer (512 pixels). */

module jtgumbo_tile #(parameter SMALL=0, AW=21)(
    input              rst,
    input              clk,
    input              big,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output      [12:0] vram_addr,
    input       [15:0] vram_dout,

    output reg [AW-1:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [2:0] IDLE=0, RD=1, FETCH=2, FWAIT=3, WRITE=4;

reg  [ 2:0] st, px;
reg  [ 7:0] line;
reg  [ 6:0] col;
reg  [14:0] code;
reg  [ 1:0] wcnt;
reg  [31:0] wa, wb;
reg         lbuf, part, start, hzero_l;
wire [31:0] ws   = SMALL ? wa : (px[0] ? wb : wa);
wire [ 1:0] bsel = SMALL ? { px[0], px[1] } : px[2:1];
wire [ 7:0] pen  = ws[ 8*bsel +: 8 ];
wire [ 8:0] waddr = SMALL ? { col, px[1:0] } : { col[5:0], px };
wire [14:0] cmask = big ? 15'h7fff : 15'h3fff;

assign vram_addr = SMALL ? { line[7:2], col } : { 2'd0, line[7:3], col[5:0] };

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
                line <= vrender[7:0];
                lbuf <= vrender[0];
                col  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin code <= vram_dout[14:0] & cmask; part <= 0; st <= FETCH; end
            end
            FETCH: begin
                if( SMALL ) rom_addr <= { code, line[1:0] };
                else        rom_addr <= { code, line[2:0], part };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    if( !part ) wa <= rom_data; else wb <= rom_data;
                    if( !SMALL && !part ) begin
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
                if( SMALL ? px==3 : px==7 ) begin
                    col  <= col + 1'd1;
                    wcnt <= 0;
                    st   <= (SMALL ? col==127 : col[5:0]==63) ? IDLE : RD;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( pen       ),
    .addr0  ( { lbuf, waddr } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
