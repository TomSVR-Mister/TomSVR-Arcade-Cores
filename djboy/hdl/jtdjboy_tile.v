/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * One 16x16 tile layer (MAME tilemap, TILEMAP_SCAN_ROWS), rendered one line ahead into a line buffer.
 *   DJ Boy:     64 x 32 tiles, code = code byte + attr bits 3-0 << 8 + attr bit 7 << 12, colour = attr bits 7-4
 *   Air Buster: 32 x 32 tiles, code = code byte + attr bits 3-0 << 8, colour = attr bits 7-4
 * Graphics: MAME gfx_8x8x4_row_2x2_group_packed (128 bytes per tile, four 8x8 blocks TL TR BL BR, 4 bytes per
 * block row); DJ Boy high nibble first (msb), Air Buster low nibble first (lsb).
 * scrx/scry are the tile map coordinates of screen pixel 0 of MAME row 0. */
module jtdjboy_tile(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              hs_start,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [ 8:0] hdump,
    input              wide,        // 64 columns (DJ Boy)
    input              lsb,         // low nibble first (Air Buster)
    input       [ 9:0] scrx,
    input       [ 8:0] scry,
    // tile map RAM
    output      [10:0] vaddr,
    input       [ 7:0] vcode,
    input       [ 7:0] vattr,
    // graphics
    output      [19:2] gfx_addr,
    output reg         gfx_cs,
    input       [31:0] gfx_data,
    input              gfx_ok,
    output      [ 7:0] pxl          // { colour, pen }
);

localparam [2:0] IDLE=0, VRD=1, FETCH=2, DRAW=3;

reg  [ 2:0] st;
reg  [ 4:0] k;          // tile column in the line, 0-16
reg  [ 1:0] vwait, wcnt;
reg  [ 8:0] ty;
reg  [ 9:0] tx;
reg  [ 3:0] x0, px, col;
reg  [12:0] code;
reg         half, lbuf;
reg  [31:0] wa, wb;
reg  [ 8:0] wpos;
wire [31:0] w    = px[3] ? wb : wa;
wire [ 4:0] nib  = lsb ? { px[2:0], 2'd0 } : { px[2:1], ~px[0], 2'd0 };
wire [ 3:0] pen  = w[ nib +: 4 ];

assign vaddr    = wide ? { ty[8:4], tx[9:4] } : { 1'b0, ty[8:4], tx[8:4] };
assign gfx_addr = { code, ty[3], half, ty[2:0] };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; gfx_cs <= 0;
    end else case( st )
        IDLE: if( hs_start ) begin
            ty   <= vrender + scry;
            tx   <= scrx;
            x0   <= scrx[3:0];
            k    <= 0;
            lbuf <= vrender[0];
            vwait<= 0;
            st   <= VRD;
        end
        VRD: begin
            vwait <= vwait + 1'd1;
            if( vwait==2 ) begin
                code  <= { wide & vattr[7], vattr[3:0], vcode };
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
                if( !half ) begin
                    wa <= gfx_data; half <= 1;
                end else begin
                    wb   <= gfx_data;
                    px   <= 0;
                    wpos <= { k, 4'd0 } - { 5'd0, x0 };
                    st   <= DRAW;
                end
            end
        end
        DRAW: begin
            px   <= px + 1'd1;
            wpos <= wpos + 1'd1;
            if( px==15 ) begin
                k     <= k + 1'd1;
                tx    <= tx + 10'd16;
                vwait <= 0;
                st    <= k==16 ? IDLE : VRD;
            end
        end
        default: st <= IDLE;
    endcase
end

jtframe_dual_ram #(.DW(8),.AW(9)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { col, pen } ),
    .addr0  ( { lbuf, wpos[7:0] } ),
    .we0    ( st==DRAW && !wpos[8] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], hdump[7:0] } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
