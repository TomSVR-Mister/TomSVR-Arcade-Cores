/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * YS-1300 sprites (MAME decospr, bootleg mode, flipallx, y offset 8): 256 entries of 4 words, drawn in list order.
 *   w0: { -, flipy, flipx(inverted), flash, wide, height[1:0], Y[8:0] }   w1: tile   w2: { -, colour[4:0], X[8:0] }
 *   Bottom tile at Y' = 240 - ((Y + 8) & 0x1ff, signed), X' = X (signed at 320); 1/2/4/8 tiles stacked upwards.
 *   Tile of the block bt rows from the top: flipy ? tile + n - bt : tile + bt (n = height - 1).
 *   wide: also tile - (n + 1) at X' - 16. flash: hidden on odd frames. Colour: 0x200 + colour * 32, pen 0 transparent.
 * Graphics, 16x16x5: 32-bit bus = planes 0-3 (one byte each), 8-bit bus = plane 4, both at { tile, left half, row }.
 *   Pen bits: 4: byte 2, 3: byte 3, 2: byte 1, 1: plane 4, 0: byte 0; leftmost pixel in the MSB. */

module jtnmg5_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              big,         // 16384 tiles, otherwise 8192
    input              odd,         // odd frame
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output reg  [10:1] ram_addr,
    input       [15:0] ram_dout,

    output      [20:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,
    output      [18:0] p5_addr,
    output reg         p5_cs,
    input       [ 7:0] p5_data,
    input              p5_ok,

    output reg  [ 8:0] pxl          // { colour[3:0], pen[4:0] }
);

localparam [2:0] IDLE=0, SCAN=1, R1=2, R2=3, R3=4, FETCH=5, FWAIT=6, WRITE=7;

reg  [ 2:0] st;
reg  [ 8:0] line;
reg  [ 8:0] aidx;           // bit 8 = done
reg  [ 7:0] p1_idx, p2_idx, hit;
reg         p1_v, p2_v;
reg  [15:0] w0;
reg  [15:0] tile;
reg  [ 3:0] col, row;
reg  [ 2:0] nblk;           // height - 1 (0, 1, 3, 7)
reg  [ 8:0] x;
reg         lbuf, half, fx, wide, second;
reg  [ 1:0] wcnt;
reg  [31:0] wa;
reg  [ 7:0] w5;
reg  [ 2:0] px;
reg         start, hzero_l, got, got5;
wire [ 8:0] q1;

// hit test on the Y word arriving from the RAM
wire [ 1:0] hsz   = ram_dout[10:9];
wire [ 2:0] n_nx  = hsz==0 ? 3'd0 : hsz==1 ? 3'd1 : hsz==2 ? 3'd3 : 3'd7;
wire [ 8:0] yv    = ram_dout[8:0] + 9'd8;
wire [10:0] ys    = { {2{yv[8]}}, yv };                         // signed: >= 256 means negative
wire [10:0] top   = 11'd240 - ys - { 4'd0, n_nx, 4'd0 };
wire [10:0] d     = { 2'd0, line } - top;
wire        yhit  = !d[10] && d[9:4] <= { 3'd0, n_nx } && !(ram_dout[12] && odd);

wire [ 2:0] b  = fx ? px : ~px;
wire [ 4:0] pen = { wa[16+b], wa[24+b], wa[8+b], w5[b], wa[b] };
wire [13:0] tmask = { big, 13'h1fff };

assign rom_addr = { tile[13:0] & tmask, ~(half ^ fx), row };
assign p5_addr  = { tile[13:0] & tmask, ~(half ^ fx), row };

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; p5_cs <= 0; p1_v <= 0; p2_v <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                line <= vrender;
                lbuf <= vrender[0];
                aidx <= 0; p1_v <= 0; p2_v <= 0;
                st   <= SCAN;
            end
            SCAN: begin
                ram_addr <= { aidx[7:0], 2'd0 };
                p1_idx   <= aidx[7:0];
                p1_v     <= !aidx[8];
                p2_idx   <= p1_idx;
                p2_v     <= p1_v;
                if( !aidx[8] ) aidx <= aidx + 1'd1;
                if( p2_v && yhit ) begin
                    w0       <= ram_dout;
                    nblk     <= n_nx;
                    row      <= d[3:0] ^ {4{ram_dout[14]}};
                    tile     <= ram_dout[14] ? { 13'd0, n_nx } - { 10'd0, d[9:4] } : { 10'd0, d[9:4] };  // offset, the code is added later
                    hit      <= p2_idx;
                    ram_addr <= { p2_idx, 2'd1 };
                    st       <= R1;
                end else if( !p2_v && !p1_v && aidx[8] ) begin
                    st <= IDLE;
                end
            end
            R1: begin ram_addr <= { hit, 2'd2 }; st <= R2; end
            R2: begin tile <= tile + ram_dout; st <= R3; end
            R3: begin
                x      <= ram_dout[8:0];
                col    <= ram_dout[12:9];
                fx     <= ~w0[13];
                wide   <= w0[11];
                second <= 0;
                half   <= 0;
                st     <= FETCH;
            end
            FETCH: begin
                rom_cs <= 1; p5_cs <= 1; got <= 0; got5 <= 0;
                wcnt   <= 0;
                st     <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else begin
                    if( rom_ok && rom_cs ) begin wa <= rom_data; rom_cs <= 0; got  <= 1; end
                    if( p5_ok  && p5_cs  ) begin w5 <= p5_data;  p5_cs  <= 0; got5 <= 1; end
                    if( (got || (rom_ok && rom_cs)) && (got5 || (p5_ok && p5_cs)) ) begin
                        px <= 0;
                        st <= WRITE;
                    end
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                if( px==7 ) begin
                    half <= ~half;
                    if( !half ) st <= FETCH;
                    else if( wide && !second ) begin
                        second <= 1;
                        tile   <= tile - { 12'd0, nblk } - 16'd1;
                        x      <= x - 9'd16;
                        st     <= FETCH;
                    end else begin
                        aidx <= { 1'b0, hit } + 1'd1;
                        p1_v <= 0; p2_v <= 0;
                        st   <= hit==8'hff ? IDLE : SCAN;
                    end
                end
            end
            default: st <= IDLE;
        endcase
    end
end

always @(posedge clk) if( pxl_cen ) pxl <= q1;

jtframe_dual_ram #(.DW(9),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { col, pen } ),
    .addr0  ( { lbuf, x + { 5'd0, half, px } } ),
    .we0    ( st==WRITE && pen!=0 ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 9'd0      ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( pxl_cen   ),
    .q1     ( q1        )
);

endmodule
