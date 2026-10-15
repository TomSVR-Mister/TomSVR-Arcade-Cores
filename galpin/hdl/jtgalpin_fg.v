/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gals Pinball foreground tilemap: 64x32 tiles of 16x8 pixels, 4bpp, no scroll.
 * code = videoram[offs], attr = colorram[offs]: bits 7-4 colour, bit 3 = tile not drawn.
 * Only columns 0-31 are visible (512 pixels).
 * A line is rendered into a ping-pong line buffer during the previous line. */

module jtgalpin_fg(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              hs,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [ 9:0] hdump,

    output      [11:1] vidram_addr,
    input       [15:0] vidram_dout,
    output      [11:1] colram_addr,
    input       [15:0] colram_dout,

    output reg  [18:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl          // {colour, pen}, pen 0 = transparent
);

localparam [2:0] IDLE=0, MAP=1, MAP2=2, MAP3=3, FETCH=4, FWAIT=5, WRITE=6;

reg  [ 2:0] st;
reg  [ 7:0] line;
reg  [ 4:0] col;
reg         half, hs_l, lbuf;
reg  [ 2:0] k;
reg  [12:0] code;
reg  [ 4:0] attr;           // {colour, skip}
reg  [31:0] data;
reg  [ 1:0] wcnt;
wire [31:0] rot = { data[15:0], data[31:16] };
reg  [ 3:0] pen;
wire        we = st == WRITE;
wire [ 9:0] waddr = { lbuf, col, half, k };
wire [ 9:0] raddr = { vdump[0], hdump[8:0] };
// render the next line during the whole current line (the buffer being shown is the other half)
reg         start, hzero_l;
always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

assign vidram_addr = { line[7:3], 1'b0, col };
assign colram_addr = { line[7:3], 1'b0, col };

always @* begin
    case( k )
        0: pen = rot[31:28];
        1: pen = rot[27:24];
        2: pen = rot[23:20];
        3: pen = rot[19:16];
        4: pen = rot[15:12];
        5: pen = rot[11: 8];
        6: pen = rot[ 7: 4];
        7: pen = rot[ 3: 0];
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        st     <= IDLE;
        rom_cs <= 0;
        hs_l   <= 0;
    end else begin
        hs_l <= hs;
        case( st )
            IDLE: if( start ) begin
                line <= vrender[7:0];
                lbuf <= vrender[0];
                col  <= 0;
                half <= 0;
                st   <= MAP;
            end
            MAP:  st <= MAP2;   // BRAM address settles
            MAP2: st <= MAP3;
            MAP3: begin
                code <= vidram_dout[12:0];
                attr <= colram_dout[7:3];
                st   <= FETCH;
            end
            FETCH: begin
                rom_addr <= { code, half, line[2:0] };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    data   <= rom_data;
                    rom_cs <= 0;
                    k      <= 0;
                    st     <= WRITE;
                end
            end
            WRITE: begin
                k <= k + 1'd1;
                if( k==7 ) begin
                    half <= ~half;
                    if( half ) begin
                        col <= col + 1'd1;
                        st  <= col==31 ? IDLE : MAP;
                    end else begin
                        st  <= FETCH;
                    end
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    // render side
    .clk0   ( clk       ),
    .data0  ( (attr[0] || pen==0) ? 8'd0 : { attr[4:1], pen } ),
    .addr0  ( waddr     ),
    .we0    ( we        ),
    .q0     (           ),
    // display side
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( raddr     ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
