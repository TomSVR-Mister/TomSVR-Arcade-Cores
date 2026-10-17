/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * ESD 16-bit sprites (MAME decospr in bootleg mode, flipallx, with a priority callback): 256 entries of 4 words,
 *   drawn from the last entry to the first, so entry 0 ends on top.
 *   w0: { prio, flipy, flipx(inverted), flash, wide, height[1:0], Y[8:0] }   w1: tile   w2: { -, colour[4:0], X[8:0] }
 *   With soff (ESD 08-26-1999 PCB): X - 0x18, Y + 0x100 (9 bits).
 *   Bottom tile on MAME line 240 - Y (Y signed), i.e. our line 232 - Y; 1/2/4/8 tiles stacked upwards.
 *   Tile of the block bt rows from the top: flipy ? tile + n - bt : tile + bt (n = height - 1).
 *   wide: also tile - (n + 1) at X - 16. flash: hidden on odd frames. prio: under tilemap 1.
 * Graphics, 16x16: 32-bit bus = { plane pair 1 (2 bytes), plane pair 0 (2 bytes) }, 8-bit bus = 5th plane,
 *   both at { tile, left half, row }; leftmost pixel in the MSB.
 *   5 bpp pen: { plane 4, pair 0 byte 0, pair 0 byte 1, pair 1 byte 0, pair 1 byte 1 }
 *   Jumping Pop 4 bpp: { pair 1 byte 1, pair 1 byte 0, pair 0 byte 1, pair 0 byte 0 } */

module jtesd_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              jp,
    input              soff,
    input       [ 1:0] osize,       // 0: 32768 tiles, 1: 8192, 2: 16384
    input              odd,         // odd frame
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    output reg  [10:1] ram_addr,
    input       [15:0] ram_dout,

    output      [21:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,
    output      [19:0] p5_addr,
    output reg         p5_cs,
    input       [ 7:0] p5_data,
    input              p5_ok,

    output reg  [10:0] pxl          // { prio, colour[4:0], pen[4:0] }
);

localparam [2:0] IDLE=0, SCAN=1, R1=2, R2=3, R3=4, FETCH=5, FWAIT=6, WRITE=7;

reg  [ 2:0] st;
reg  [ 8:0] line;
reg  [ 8:0] aidx;           // counts down, bit 8 = done
reg  [ 7:0] p1_idx, p2_idx, hit;
reg         p1_v, p2_v;
reg  [15:0] w0;
reg  [15:0] tile;
reg  [ 4:0] col;
reg  [ 3:0] row;
reg  [ 2:0] nblk;           // height - 1 (0, 1, 3, 7)
reg  [ 8:0] x;
reg         lbuf, half, fx, wide, second;
reg  [ 1:0] wcnt;
reg  [31:0] wa;
reg  [ 7:0] w5;
reg  [ 2:0] px;
reg         start, hzero_l, got, got5;
// one-entry cache of the last graphics fetch: games park unused sprites on the same blank tile, and
// fetching it 200+ times would overrun the line time. Blank 8-pixel halves skip the pixel loop.
reg  [19:0] ckey;
reg  [31:0] cwa;
reg  [ 7:0] cw5;
reg         cvalid;
wire [10:0] q1;

// hit test on the Y word arriving from the RAM
wire [ 1:0] hsz   = ram_dout[10:9];
wire [ 2:0] n_nx  = hsz==0 ? 3'd0 : hsz==1 ? 3'd1 : hsz==2 ? 3'd3 : 3'd7;
wire [ 8:0] yv    = { ram_dout[8] ^ soff, ram_dout[7:0] };
wire [10:0] ys    = { {2{yv[8]}}, yv };                         // signed: >= 256 means negative
wire [10:0] top   = 11'd232 - ys - { 4'd0, n_nx, 4'd0 };
wire [10:0] d     = { 2'd0, line } - top;
wire        yhit  = !d[10] && d[9:4] <= { 3'd0, n_nx } && !(ram_dout[12] && odd);

wire [ 2:0] b  = fx ? px : ~px;
wire [ 4:0] pen = jp ? { 1'b0, wa[24+b], wa[16+b], wa[8+b], wa[b] } :
                       { w5[b], wa[b], wa[8+b], wa[16+b], wa[24+b] };
wire [14:0] tmask = osize==1 ? 15'h1fff : osize==2 ? 15'h3fff : 15'h7fff;
wire [14:0] tcode = tile[14:0] & tmask;

assign rom_addr = { tcode, ~(half ^ fx), row };
assign p5_addr  = { tcode, ~(half ^ fx), row };

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; p5_cs <= 0; p1_v <= 0; p2_v <= 0; cvalid <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                line <= vrender;
                lbuf <= vrender[0];
                aidx <= 9'd255; p1_v <= 0; p2_v <= 0;
                st   <= SCAN;
            end
            SCAN: begin
                ram_addr <= { aidx[7:0], 2'd0 };
                p1_idx   <= aidx[7:0];
                p1_v     <= !aidx[8];
                p2_idx   <= p1_idx;
                p2_v     <= p1_v;
                if( !aidx[8] ) aidx <= aidx - 1'd1;
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
                x      <= ram_dout[8:0] - (soff ? 9'h18 : 9'h0);
                col    <= ram_dout[13:9];
                fx     <= ~w0[13];
                wide   <= w0[11];
                second <= 0;
                half   <= 0;
                st     <= FETCH;
            end
            FETCH: begin
                if( cvalid && ckey==rom_addr ) begin
                    wa <= cwa; w5 <= cw5;
                    px <= (cwa==0 && (jp || cw5==0)) ? 3'd7 : 3'd0;
                    st <= WRITE;
                end else begin
                    rom_cs <= 1; p5_cs <= !jp; got <= 0; got5 <= jp;
                    wcnt   <= 0;
                    st     <= FWAIT;
                end
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else begin
                    if( rom_ok && rom_cs ) begin wa <= rom_data; rom_cs <= 0; got  <= 1; end
                    if( p5_ok  && p5_cs  ) begin w5 <= p5_data;  p5_cs  <= 0; got5 <= 1; end
                    if( (got || (rom_ok && rom_cs)) && (got5 || (p5_ok && p5_cs)) ) begin
                        px <= 0;
                        st <= WRITE;
                        ckey   <= rom_addr;
                        cvalid <= 1;
                        cwa    <= got  ? wa : rom_data;
                        cw5    <= got5 ? w5 : p5_data;
                        if( (got ? wa : rom_data)==0 && (jp || (got5 ? w5 : p5_data)==0) ) px <= 3'd7;
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
                        tile   <= tile - { 13'd0, nblk } - 16'd1;
                        x      <= x - 9'd16;
                        st     <= FETCH;
                    end else begin
                        aidx <= { 1'b0, hit } - 1'd1;
                        p1_v <= 0; p2_v <= 0;
                        st   <= hit==8'h00 ? IDLE : SCAN;
                    end
                end
            end
            default: st <= IDLE;
        endcase
    end
end

always @(posedge clk) if( pxl_cen ) pxl <= q1;

jtframe_dual_ram #(.DW(11),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { w0[15], col, pen } ),
    .addr0  ( { lbuf, x + { 5'd0, half, px } } ),
    .we0    ( st==WRITE && pen!=0 ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 11'd0     ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( pxl_cen   ),
    .q1     ( q1        )
);

endmodule
