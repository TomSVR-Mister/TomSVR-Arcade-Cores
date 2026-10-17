/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * VISYS sprites (MAME oneshot.cpp, maddonna draw_sprites): up to 512 entries of 4 words, drawn in list order
 * (later entries on top). w0: bit 0 = end of list, bit 15 = visible. w1: first 8x8 tile.
 *   w2: X = (w2 >> 7) - 8, width = (w2 & 15) + 1 blocks.  w3: Y = (w3 >> 7) - 6, height = (w3 & 15) + 1 blocks.
 *   Block (bx, by) uses tile w1 + by * width + bx, colour 1, pen 0 transparent. X wraps at 512 (MAME draws X - 0x200 too).
 * Line buffer: written for line vrender, read for line vdump and cleared as it is read. */

module jtmadd_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output reg  [11:1] ram_addr,
    input       [15:0] ram_dout,

    output reg  [21:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output reg  [ 7:0] pxl
);

localparam [2:0] IDLE=0, SCAN=1, R1=2, R2=3, R3=4, FETCH=5, FWAIT=6, WRITE=7;

reg  [ 2:0] st;
reg  [ 8:0] line;
reg  [ 9:0] aidx;           // next entry to address (bit 9 = done)
reg  [ 8:0] pidx;
reg         pv, ph;
reg  [15:0] attr, tile;
reg  [ 3:0] by, bx, xsz;
reg  [ 2:0] row;
reg  [ 8:0] x;
reg         lbuf, wsel;
reg  [ 1:0] wcnt;
reg  [31:0] wa, wb;
reg  [ 2:0] px;
reg         start, hzero_l;
wire [ 9:0] ydiff = { 1'b0, line } - ({ 1'b0, ram_dout[15:7] } - 10'd5);   // MAME: Y - 6 (one more line measured)
wire [ 2:0] b = ~px;
wire [ 7:0] pen = { wa[b], wa[8+b], wa[16+b], wa[24+b], wb[b], wb[8+b], wb[16+b], wb[24+b] };
wire [ 7:0] q1;

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; pv <= 0; ph <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                line <= vrender;
                lbuf <= vrender[0];
                aidx <= 0; pv <= 0; ph <= 0;
                st   <= SCAN;
            end
            // w0 and w3 of each entry are requested on alternate clocks and checked two clocks later
            SCAN: begin
                ph <= ~ph;
                if( !ph ) begin
                    ram_addr <= { aidx[8:0], 2'd0 };
                    if( pv ) attr <= ram_dout;
                end else begin
                    ram_addr <= { aidx[8:0], 2'd3 };
                    pidx     <= aidx[8:0];
                    pv       <= !aidx[9];
                    if( !aidx[9] ) aidx <= aidx + 1'd1;
                    if( pv ) begin
                        if( attr[0] ) st <= IDLE;
                        else if( attr[15] && ydiff[9:7]==0 && ydiff[6:3] <= ram_dout[3:0] ) begin
                            by       <= ydiff[6:3];
                            row      <= ydiff[2:0];
                            ram_addr <= { pidx, 2'd1 };
                            pidx     <= pidx;
                            st       <= R1;
                        end
                    end else if( aidx[9] ) st <= IDLE;
                end
            end
            R1: begin ram_addr <= { pidx, 2'd2 }; st <= R2; end
            R2: begin tile <= ram_dout; st <= R3; end
            R3: begin
                xsz  <= ram_dout[3:0];
                x    <= ram_dout[15:7] - 9'd7;     // MAME: X - 8 (one more pixel measured)
                tile <= tile + by * ({ 1'b0, ram_dout[3:0] } + 5'd1);
                bx   <= 0;
                wsel <= 0;
                st   <= FETCH;
            end
            FETCH: begin
                rom_addr <= { tile, row, wsel };
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
                    x    <= x + 9'd8;
                    tile <= tile + 1'd1;
                    bx   <= bx + 1'd1;
                    if( bx==xsz ) begin
                        aidx <= { 1'b0, pidx } + 1'd1;
                        pv   <= 0;
                        ph   <= 0;
                        st   <= SCAN;
                    end else st <= FETCH;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

always @(posedge clk) if( pxl_cen ) pxl <= q1;

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( pen       ),
    .addr0  ( { lbuf, x + { 6'd0, px } } ),
    .we0    ( st==WRITE && pen!=0 ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( pxl_cen   ),      // the pixel is taken on the same edge, so it is cleared after being read
    .q1     ( q1        )
);

endmodule
