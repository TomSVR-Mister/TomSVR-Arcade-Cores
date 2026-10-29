/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * One tile layer of MAME tecmo/tbowl.cpp (TILEMAP_SCAN_ROWS), rendered one line ahead into a 512 pixel line buffer
 * that covers both monitors (left = x 0-255, right = x 256-511; MAME adds 256 to the scroll of the right screen).
 *   BIG=0: text layer, 64 x 32 tiles of 8x8, code = code byte + attr bits 2-0 << 8, colour = attr bits 7-4
 *   BIG=1: bg layer, 128 x 32 tiles of 16x16, code = code byte + attr bits 3-0 << 8 (^ XORC), colour = attr 7-4
 * Graphics are MAME gfx_8x8x4_packed_msb (32 bytes per tile, 4 bytes per row, high nibble first); the 16x16 tiles
 * are four of them, TL TR BL BR (gfx_8x8x4_row_2x2_group_packed_msb). Every pixel is written, pen 0 included. */
module jttbowl_tile #(parameter
    BIG  = 1,
    XORC = 12'h000,
    VAW  = BIG ? 12 : 11,           // tile map RAM address width
    GAW  = BIG ? 17 : 14            // graphics word address width
)(
    input              rst,
    input              clk,
    input              line_start,
    input       [ 8:0] vrender,
    input       [10:0] scrx,
    input       [ 8:0] scry,
    // tile map RAM
    output  [VAW-1:0]  vaddr,
    input       [ 7:0] vcode,
    input       [ 7:0] vattr,
    // graphics
    output  [GAW+1:2]  gfx_addr,
    output reg         gfx_cs,
    input       [31:0] gfx_data,
    input              gfx_ok,
    // line buffer read out
    input       [ 9:0] rd_addr,     // { line parity, x }
    output      [ 7:0] pxl          // { colour, pen }
);

localparam [2:0] IDLE=0, VRD=1, FETCH=2, DRAW=3;
localparam [6:0] NT = BIG ? 7'd33 : 7'd64;

reg  [ 2:0] st;
reg  [ 6:0] k;          // tile column in the line
reg  [ 1:0] vwait, wcnt;
reg  [ 8:0] ty;
reg  [10:0] tx;
reg  [ 3:0] x0, px, col;
reg  [11:0] code;
reg         half, lbuf;
reg  [31:0] wa, wb;
reg  [ 9:0] wpos;
wire [31:0] w    = px[3] ? wb : wa;
wire [ 4:0] nib  = { px[2:1], ~px[0], 2'd0 };
wire [ 3:0] pen  = w[ nib +: 4 ];
wire        last = BIG ? px==15 : px==7;

generate
    if( BIG ) begin
        assign vaddr    = { ty[8:4], tx[10:4] };
        assign gfx_addr = { code, ty[3], half, ty[2:0] };
    end else begin
        assign vaddr    = { ty[7:3], tx[8:3] };
        assign gfx_addr = { code[10:0], ty[2:0] };
    end
endgenerate

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; gfx_cs <= 0;
    end else case( st )
        IDLE: if( line_start ) begin
            ty   <= vrender + scry;
            tx   <= BIG ? scrx : 11'd0;
            x0   <= BIG ? scrx[3:0] : 4'd0;
            k    <= 0;
            lbuf <= vrender[0];
            vwait<= 0;
            st   <= VRD;
        end
        VRD: begin
            vwait <= vwait + 1'd1;
            if( vwait==2 ) begin
                code  <= BIG ? { vattr[3:0], vcode } ^ XORC : { 1'b0, vattr[2:0], vcode };
                col   <= vattr[7:4];
                half  <= 0;
                wcnt  <= 0;
                st    <= FETCH;
            end
        end
        FETCH: begin
            gfx_cs <= 1;
            if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
            else if( gfx_ok ) begin
                gfx_cs <= 0;
                wcnt   <= 0;
                if( BIG && !half ) begin
                    wa <= gfx_data; half <= 1;
                end else begin
                    if( BIG ) wb <= gfx_data; else wa <= gfx_data;
                    px   <= 0;
                    wpos <= BIG ? { k[5:0], 4'd0 } - { 6'd0, x0 } : { k[6:0], 3'd0 };
                    st   <= DRAW;
                end
            end
        end
        DRAW: begin
            px   <= px + 1'd1;
            wpos <= wpos + 1'd1;
            if( last ) begin
                k     <= k + 1'd1;
                tx    <= tx + (BIG ? 11'd16 : 11'd8);
                vwait <= 0;
                st    <= k==NT-1 ? IDLE : VRD;
            end
        end
        default: st <= IDLE;
    endcase
end

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { col, pen } ),
    .addr0  ( { lbuf, wpos[8:0] } ),
    .we0    ( st==DRAW && !wpos[9] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( rd_addr   ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
