/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Tecmo sprites as drawn by MAME tecmo_spr_device::tbowl_draw_sprites: 256 entries of 8 bytes, drawn in RAM order
 * (later entries on top), rendered one line ahead into a 512 pixel line buffer covering both monitors.
 *   byte 0: bit 7 enable, bit 5 flip x, bits 3-2 height (1/2/4/8 tiles), bits 1-0 width (1/2/4/8 tiles)
 *   byte 1-2: tile code (8x8 tiles), byte 3 bits 4-0: colour
 *   byte 4: bit 4 = y bit 8, bits 1-0 = x bits 9-8   byte 5: y   byte 6: x
 * Tiles of a sprite follow the Tecmo layout (x0 y0 x1 y1 x2 y2 interleaved). x wraps at 1024, y at 512.
 * Time per line: the entry scan takes one clock per sprite, tiles outside x 0-511 are not fetched, and the buffer
 * half that was just displayed is cleared during the horizontal blank (clr_go) through the read port. */
module jttbowl_obj(
    input              rst,
    input              clk,
    input              line_start,
    input       [ 8:0] vrender,
    input              clr_go,      // start clearing the read bank (after the last active pixel was read)
    // sprite RAM, one entry per read
    output      [ 7:0] oaddr,
    input       [63:0] odata,
    // graphics
    output      [18:2] gfx_addr,
    output reg         gfx_cs,
    input       [31:0] gfx_data,
    input              gfx_ok,
    // line buffer read out
    input       [ 9:0] rd_addr,     // { line parity, x }
    output      [ 8:0] pxl          // { colour, pen }
);

localparam [1:0] IDLE=0, SCAN=1, SPR=2;

reg  [ 1:0] st;
reg  [ 8:0] idx, pidx;
reg         pv;
reg  [ 1:0] wcnt;
reg  [ 8:0] y;
reg         lbuf;
// current sprite
reg  [15:0] code;
reg  [ 4:0] col;
reg         flip;
reg  [ 2:0] tr, fine, cmax, tcol;
reg  [ 3:0] fc;         // next column to fetch (4 bits: cmax+1 ends)
reg  [ 9:0] x, wpos, ntx;
reg  [31:0] pd, nd;
reg  [ 2:0] px;
reg         have, drawing;
// clearing
reg  [ 9:0] ccnt;
wire        clearing = ~ccnt[9];
// entry fields
wire [ 7:0] b0 = odata[ 7: 0], b1 = odata[15: 8], b2 = odata[23:16], b3 = odata[31:24],
            b4 = odata[39:32], b5 = odata[47:40], b6 = odata[55:48];
wire [ 3:0] hgt  = 4'd1 << b0[3:2];
wire [ 8:0] r    = y - { b4[4], b5 };
wire        hit  = pv && b0[7] && r < { 2'd0, hgt, 3'd0 };
wire [ 5:0] lay  = { tr[2], tcol[2], tr[1], tcol[1], tr[0], tcol[0] };
wire [15:0] tile = code + { 10'd0, lay };
wire [ 2:0] pp   = flip ? ~px : px;
wire [ 4:0] nib  = { pp[2:1], ~pp[0], 2'd0 };
wire [ 3:0] pen  = pd[ nib +: 4 ];
wire [ 9:0] tx   = x + { 4'd0, fc[2:0], 3'd0 };
wire        tvis = !tx[9] || tx > 10'd1016;    // some pixel of the tile lands in 0-511
wire        fdone= fc > { 1'b0, cmax };

assign oaddr    = idx[7:0];
assign gfx_addr = { tile[13:0], fine };

always @* tcol = flip ? cmax - fc[2:0] : fc[2:0];

always @(posedge clk) begin
    if( rst ) ccnt <= 10'h200;
    else if( clr_go ) ccnt <= 0;
    else if( clearing ) ccnt <= ccnt + 1'd1;
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; gfx_cs <= 0; pv <= 0; have <= 0; drawing <= 0;
    end else case( st )
        IDLE: if( line_start ) begin
            y    <= vrender;
            lbuf <= vrender[0];
            idx  <= 0;
            pv   <= 0;
            st   <= SCAN;
        end
        SCAN: begin     // odata belongs to pidx when pv is set
            if( hit ) begin
                code <= { b1, b2 };
                col  <= b3[4:0];
                flip <= b0[5];
                tr   <= r[5:3];
                fine <= r[2:0];
                fc   <= 0;
                cmax <= (3'd1 << b0[1:0]) - 3'd1;
                x    <= { b4[1:0], b6 };
                wcnt <= 0;
                have <= 0;
                idx  <= pidx + 1'd1;
                pv   <= 0;
                st   <= SPR;
            end else if( pv && pidx==9'd255 ) begin
                st <= IDLE;
            end else if( idx[8] ) begin
                st <= IDLE;     // the last entry was a hit and has been drawn
            end else begin
                pidx <= idx;
                pv   <= 1;
                idx  <= idx + 1'd1;
            end
        end
        SPR: begin
            // fetcher: one tile ahead of the drawer
            if( !fdone && !have ) begin
                if( !tvis ) begin   // nothing to draw in 0-511
                    gfx_cs <= 0;
                    wcnt   <= 0;
                    fc     <= fc + 1'd1;
                end else begin
                    gfx_cs <= 1;
                    if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                    else if( gfx_ok ) begin
                        gfx_cs <= 0;
                        wcnt   <= 0;
                        nd     <= gfx_data;
                        ntx    <= tx;
                        have   <= 1;
                        fc     <= fc + 1'd1;
                    end
                end
            end
            // drawer
            if( drawing ) begin
                px   <= px + 1'd1;
                wpos <= wpos + 1'd1;
                if( px==7 ) drawing <= 0;
            end
            if( have && (!drawing || px==7) ) begin
                pd      <= nd;
                wpos    <= ntx;
                px      <= 0;
                drawing <= 1;
                have    <= 0;
            end
            if( fdone && !have && (!drawing || px==7) && !(have && (!drawing || px==7)) ) begin
                if( !drawing || px==7 ) begin
                    drawing <= 0;
                    st      <= SCAN;
                end
            end
        end
        default: st <= IDLE;
    endcase
end

wire we = drawing && !wpos[9] && pen!=0;

jtframe_dual_ram #(.DW(9),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { col, pen } ),
    .addr0  ( { lbuf, wpos[8:0] } ),
    .we0    ( we        ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 9'd0      ),
    .addr1  ( clearing ? { rd_addr[9], ccnt[8:0] } : rd_addr ),
    .we1    ( clearing  ),
    .q1     ( pxl       )
);

endmodule
