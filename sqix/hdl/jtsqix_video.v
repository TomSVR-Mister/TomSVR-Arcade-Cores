/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Super Qix video (MAME superqix_v.cpp): 6 MHz pixel clock, 384x262. Visible 256x224 = MAME rows 16-239.
 *   Tile map: 32x32 tiles of 8x8x4 at RAM 0800 (codes) / 0c00 (attributes { colour[3:0], group, chars, code[9:8] }).
 *     attr bit 2 set: character ROM (code < 1024), clear: background ROM, code + 1024 * tile bank.
 *     group 0 tiles are behind everything; group 1 tiles draw pens 1-15 in front of everything.
 *   Bitmap: 4 bpp, 128 bytes per row from MAME row 16, left pixel in the high nibble; pen 0 transparent. Two pages.
 *   Sprites: 64 entries of 4 bytes at RAM 0000: code[7:0], x, y, { colour[3:0], flipy, flipx, -, code[8] }, 16x16x4,
 *     later entries on top, pen 0 transparent.
 *   Palette: 256 bytes BBGGRRII (colour = { 2 bits, II }). Index colour * 16 + pen, bitmap colour 0.
 * Perestroika Girls graphics ROMs: bytes shuffled within each 16-byte block (MAME init_perestro):
 *   chars: bits 1/0 swapped, background tiles: bits 3-0 reversed, sprites: { j1, j0, j3, j2 }. */

module jtsqix_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 1:0] tbank,
    input              bpage,

    output      [12:0] ram_video_addr,
    input       [ 7:0] ram_video_dout,
    output      [ 9:0] spr_video_addr,
    input       [ 7:0] spr_video_dout,
    output      [14:0] bmp0_video_addr,
    input       [ 7:0] bmp0_video_dout,
    output      [14:0] bmp1_video_addr,
    input       [ 7:0] bmp1_video_dout,
    output reg  [ 9:0] pal_video_addr,
    input       [ 7:0] pal_video_dout,

    output      [17:0] gfx_addr,
    output reg         gfx_cs,
    input       [ 7:0] gfx_data,
    input              gfx_ok,
    output      [15:0] sprom_addr,
    output reg         sprom_cs,
    input       [ 7:0] sprom_data,
    input              sprom_ok,

    output reg  [ 8:0] vdump,
    output             hs_start,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 3:0] red,
    output reg  [ 3:0] green,
    output reg  [ 3:0] blue
);

localparam [8:0] HTOTAL=9'd383, HS_START=9'd300, HS_END=9'd332;
localparam [8:0] VTOTAL=9'd261, VB_END=9'd16, VB_START=9'd240, VS_START=9'd248, VS_END=9'd251;

reg  [ 8:0] hdump=0, vrender=1;
reg         lhbl, lvbl, hs_l;
reg  [ 3:0] hbl_sh, vbl_sh;
initial vdump = 0;

assign LHBL     = hbl_sh[2];
assign LVBL     = vbl_sh[2];
assign hs_start = pxl_cen && hdump==0 && !hs_l;

always @(posedge clk) if( pxl_cen ) hs_l <= hdump==0;

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    lhbl <= hdump==HTOTAL || hdump < 9'd255;
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[2:0], lhbl };
    vbl_sh <= { vbl_sh[2:0], lvbl };
end

// ---------------- tile map ----------------
localparam [2:0] T_IDLE=0, T_RD=1, T_FETCH=2, T_WAIT=3, T_DRAW=4;
reg  [ 2:0] tst;
reg  [ 7:0] ty;
reg  [ 4:0] tcol;
reg  [ 1:0] tk, twc, trd;
reg  [ 7:0] tcode, tattr;
reg  [31:0] tbits;
reg  [ 2:0] tpx;
reg         tlbuf;
wire [ 3:0] tj   = { ty[1:0], tk };
wire        tchr = tattr[2];
wire [ 3:0] tjr  = tchr ? { tj[3:2], tj[0], tj[1] } : { tj[0], tj[1], tj[2], tj[3] };
wire [11:0] tcd  = tchr ? { 2'b00, tattr[1:0], tcode } : { tbank, tattr[1:0], tcode };
wire [ 3:0] tpen = tbits[ 31 - { tpx, 2'd0 } -: 4 ];
wire [ 8:0] tq;

assign ram_video_addr = { 2'b01, trd[0], ty[7:3], tcol };   // 0800 + idx, 0c00 + idx
assign gfx_addr = tchr ? { 2'b00, tcd[10:0], ty[2], tjr } : { 1'b0, tcd, ty[2], tjr } + 18'h10000;   // chars 00000, tiles 10000

always @(posedge clk) begin
    if( rst ) begin
        tst <= T_IDLE; gfx_cs <= 0;
    end else case( tst )
        T_IDLE: if( hs_start ) begin
            ty <= vrender[7:0]; tlbuf <= vrender[0]; tcol <= 0; trd <= 0; twc <= 0; tst <= T_RD;
        end
        T_RD: begin     // code then attribute, one clock of BRAM latency each
            twc <= twc + 1'd1;
            if( twc==1 ) begin tcode <= ram_video_dout; trd <= 1; end
            if( twc==3 ) begin tattr <= ram_video_dout; trd <= 0; tk <= 0; tst <= T_FETCH; end
        end
        T_FETCH: begin twc <= 0; tst <= T_WAIT; end
        T_WAIT: begin
            gfx_cs <= 1;
            if( twc!=3 ) twc <= twc + 1'd1;
            else if( gfx_ok ) begin
                gfx_cs <= 0;
                tbits  <= { tbits[23:0], gfx_data };
                tk     <= tk + 1'd1;
                if( tk==3 ) begin tpx <= 0; tst <= T_DRAW; end
                else tst <= T_FETCH;
            end
        end
        T_DRAW: begin
            tpx <= tpx + 1'd1;
            if( tpx==7 ) begin
                tcol <= tcol + 1'd1;
                twc  <= 0;
                tst  <= tcol==31 ? T_IDLE : T_RD;
            end
        end
        default: tst <= T_IDLE;
    endcase
end

jtframe_dual_ram #(.DW(9),.AW(9)) u_tbuf(
    .clk0   ( clk       ),
    .data0  ( { tattr[3], tattr[7:4], tpen } ),
    .addr0  ( { tlbuf, tcol, tpx } ),
    .we0    ( tst==T_DRAW ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 9'd0      ),
    .addr1  ( { vdump[0], hdump[7:0] } ),
    .we1    ( 1'b0      ),
    .q1     ( tq        )
);

// ---------------- sprites ----------------
localparam [2:0] S_IDLE=0, S_Y=1, S_REST=2, S_FETCH=3, S_WAIT=4, S_DRAW=5, S_NEXT=6;
reg  [ 2:0] sst;
reg  [ 7:0] sy_line;
reg  [ 5:0] sent;
reg  [ 1:0] sb, swc, sk;
reg  [ 3:0] srow;
reg  [ 7:0] scode, sx, sattr;
reg  [31:0] sbits;
reg  [ 2:0] spx;
reg         shalf, slbuf;
wire [ 8:0] sdy  = { 1'b0, sy_line } - { 1'b0, spr_video_dout };
wire        sfx  = sattr[2];
wire        sth  = shalf ^ sfx;
wire [ 2:0] spxf = spx ^ {3{sfx}};
wire [ 3:0] spen = sbits[ 31 - { spxf, 2'd0 } -: 4 ];
wire [ 8:0] swx  = { 1'b0, sx } + { 5'd0, shalf, spx };
wire [ 7:0] sq;

assign spr_video_addr = { 2'b00, sent, sb };
// byte = tile * 128 + row[3] * 64 + half * 32 + row[2:0] * 4 + k, low nibble shuffled to { k1, k0, r1, r0 }
assign sprom_addr = { sattr[0], scode, srow[3], sth, srow[2], sk, srow[1:0] };

always @(posedge clk) begin
    if( rst ) begin
        sst <= S_IDLE; sprom_cs <= 0;
    end else case( sst )
        S_IDLE: if( hs_start ) begin
            sy_line <= vrender[7:0]; slbuf <= vrender[0]; sent <= 0; sb <= 2; swc <= 0; sst <= S_Y;
        end
        S_Y: begin      // byte 2 (y) arrives after one clock
            swc <= swc + 1'd1;
            if( swc==1 ) begin
                if( sdy[8:4]==0 && !vrender[8] ) begin
                    srow <= sdy[3:0];
                    sb   <= 0; swc <= 0; sst <= S_REST;
                end else sst <= S_NEXT;
            end
        end
        S_REST: begin   // bytes 0, 1, 3
            swc <= swc + 1'd1;
            case( swc )
                0: sb <= 1;
                1: begin scode <= spr_video_dout; sb <= 3; end
                2: sx <= spr_video_dout;
                3: begin
                    sattr <= spr_video_dout;
                    if( spr_video_dout[3] ) srow <= ~srow;     // flip y
                    shalf <= 0; sk <= 0; sst <= S_FETCH;
                end
            endcase
        end
        S_FETCH: begin swc <= 0; sst <= S_WAIT; end
        S_WAIT: begin
            sprom_cs <= 1;
            if( swc!=3 ) swc <= swc + 1'd1;
            else if( sprom_ok ) begin
                sprom_cs <= 0;
                sbits  <= { sbits[23:0], sprom_data };
                sk     <= sk + 1'd1;
                if( sk==3 ) begin spx <= 0; sst <= S_DRAW; end
                else sst <= S_FETCH;
            end
        end
        S_DRAW: begin
            spx <= spx + 1'd1;
            if( spx==7 ) begin
                if( !shalf ) begin shalf <= 1; sk <= 0; sst <= S_FETCH; end
                else sst <= S_NEXT;
            end
        end
        S_NEXT: begin
            sent <= sent + 1'd1;
            sb   <= 2; swc <= 0;
            sst  <= &sent ? S_IDLE : S_Y;
        end
        default: sst <= S_IDLE;
    endcase
end

jtframe_dual_ram #(.DW(8),.AW(9)) u_sbuf(
    .clk0   ( clk       ),
    .data0  ( { sattr[7:4], spen } ),
    .addr0  ( { slbuf, swx[7:0] } ),
    .we0    ( sst==S_DRAW && spen!=0 && !swx[8] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], hdump[7:0] } ),
    .we1    ( pxl_cen && !hdump[8] ),
    .q1     ( sq        )
);

// ---------------- bitmap ----------------
wire [ 7:0] brow = vdump[7:0] - 8'd16;
assign bmp0_video_addr = { brow, hdump[7:1] };
assign bmp1_video_addr = bmp0_video_addr;

// ---------------- mixer ----------------
reg  [ 8:0] tp;
reg  [ 7:0] sp;
reg  [ 3:0] bp;
reg  [ 7:0] idx;
wire [ 7:0] bbyte = bpage ? bmp1_video_dout : bmp0_video_dout;

always @* begin
    idx = gfx_en[0] ? tp[7:0] : 8'd0;
    if( gfx_en[2] && bp != 0 ) idx = { 4'd0, bp };
    if( gfx_en[3] && sp[3:0] != 0 ) idx = sp;
    if( gfx_en[1] && tp[8] && tp[3:0] != 0 ) idx = tp[7:0];
end

always @(posedge clk) if( pxl_cen ) begin
    tp <= tq;
    sp <= sq;
    bp <= hdump[0] ? bbyte[3:0] : bbyte[7:4];   // left (even) pixel in the high nibble
    pal_video_addr <= { 2'd0, idx };
    red   <= pal_video_dout[3:0];
    green <= { pal_video_dout[5:4], pal_video_dout[1:0] };
    blue  <= { pal_video_dout[7:6], pal_video_dout[1:0] };
end

endmodule
