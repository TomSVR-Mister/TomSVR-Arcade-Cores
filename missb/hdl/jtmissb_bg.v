/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Miss Bubble II background (MAME missb2.cpp): 8 bpp picture made of 256x16 strips, 4 kB each, 512 strips (2 MB).
 * Line y shows strip (bgvram << 4) + (y >> 4), row y & 15. Byte address in the strip (pen = byte):
 *   Miss Bubble II:   { x1, x5, x6, x4, y3, y2, y1, y0, x2, x3, x7, x0 }
 *   Bubble Pong Pong: { x7, x6, x5, x4, y3, y2, y1, y0, x3, x2, x1, x0 }
 * Read as 16-bit words (two pixels: x0 = 0 in the low byte) into a 256-pixel ping-pong line buffer. */

module jtmissb_bg(
    input              rst,
    input              clk,
    input              alt,
    input       [ 7:0] bgvram,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output      [20:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

reg  [ 7:0] y;
reg  [ 6:0] k;          // pixel pair
reg         lbuf, busy, hsel, start, hl;
reg  [ 1:0] wcnt;
reg  [15:0] data;
wire [ 7:0] x = { k, 1'b0 };
wire [ 8:0] strip = { bgvram[4:0], y[7:4] };
wire [11:0] boff = alt ? { x[7:4], y[3:0], x[3:0] } : { x[1], x[5], x[6], x[4], y[3:0], x[2], x[3], x[7], x[0] };

assign rom_addr = { strip, boff[11:1] };

always @(posedge clk) begin
    hl    <= hdump==0;
    start <= hdump==0 && !hl;
end

always @(posedge clk) begin
    if( rst ) begin
        busy <= 0; rom_cs <= 0;
    end else begin
        if( start ) begin
            y    <= vrender[7:0];
            lbuf <= vrender[0];
            k    <= 0;
            busy <= 1;
            wcnt <= 0;
            hsel <= 0;
            rom_cs <= 0;
        end else if( busy ) begin
            if( !hsel ) begin
                rom_cs <= 1;
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    data   <= rom_data;
                    rom_cs <= 0;
                    hsel   <= 1;
                end
            end else begin      // second clock writes the odd pixel
                hsel <= 0;
                wcnt <= 0;
                k    <= k + 1'd1;
                if( &k ) busy <= 0;
            end
        end
    end
end

wire       we   = busy && (hsel || (rom_ok && rom_cs && wcnt==3));
wire [7:0] wdat = hsel ? data[15:8] : rom_data[7:0];

jtframe_dual_ram #(.DW(8),.AW(9)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( wdat      ),
    .addr0  ( { lbuf, x[7:1], hsel } ),
    .we0    ( we        ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], hdump[7:0] } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
