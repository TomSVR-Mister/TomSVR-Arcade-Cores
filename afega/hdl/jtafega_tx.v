/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Afega text layer (MAME nmk16 common_get_tx_tile_info): 32x32 tiles of 8x8x4 scanned by columns (index = col * 32 + row),
 *   word = { colour[3:0], code[11:0] }, palette 0x200 + colour * 16, pen 15 transparent. Codes wrap at 2048 (64 kB ROM).
 * Graphics in SDRAM: the ROM as is, 4 bytes per tile row, left pixel in the high nibble of the first byte.
 * Output { colour, pen }. */

module jtafega_tx(
    input              rst,
    input              clk,
    input       [ 8:0] hdump,
    input              hs_start,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [ 7:0] scrx,
    input       [ 7:0] scry,

    output      [10:1] vram_addr,
    input       [15:0] vram_dout,

    output      [15:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [2:0] IDLE=0, RD=1, FWAIT=3, WRITE=4;

reg  [ 2:0] st;
reg  [ 7:0] mapy;
reg  [ 7:0] sx[0:1];
reg  [ 4:0] col;
reg  [ 5:0] cnt;
reg  [15:0] code;
reg         lbuf;
reg  [ 1:0] wcnt;
reg  [31:0] wa;
reg  [ 2:0] px;
wire [ 3:0] pen = wa[ { px[2:1], ~px[0], 2'd0 } +: 4 ];
wire [ 7:0] rd_x = hdump[7:0] + sx[vdump[0]];

assign vram_addr = { col, mapy[7:3] };
assign rom_addr  = { code[10:0], mapy[2:0] };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0;
    end else begin
        case( st )
            IDLE: if( hs_start ) begin
                mapy <= vrender[7:0] + scry;
                lbuf <= vrender[0];
                sx[vrender[0]] <= scrx;
                col  <= scrx[7:3];
                cnt  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin
                    code <= vram_dout;
                    wcnt <= 0;
                    st   <= FWAIT;
                end
            end
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
                    st   <= cnt==32 ? IDLE : RD;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(9)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { code[15:12], pen } ),
    .addr0  ( { lbuf, col, px } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], rd_x } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
