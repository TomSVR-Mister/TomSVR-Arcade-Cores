/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Funny Bubble video (MAME funybubl.cpp screen_update). 6 MHz pixel clock, 384x262 (59.6 Hz).
 *   Visible 320x224 = MAME columns 96-415, rows 16-239 (coordinates below are MAME's).
 *   Tile map: 64x32 tiles of 8x8x8, 2 bytes per tile (code 14-0, colour bit 15), rows in order, no scroll,
 *     palette 100 + colour * 100, pen 0 transparent.
 *   Sprites: 128 entries, 32 bytes apart (bytes 0-3: code low, { bank 1000 (bit 7), x bit 8 (bit 5), code 11-8 },
 *     y, x), 16x16x8, palette 0, pen 255 transparent; entry 0 on top. x bit 8 only counts while x < e0.
 *   Both ROMs are stored inverted (MAME ROMREGION_INVERT): the pixels are inverted here.
 *   Palette: 768 colours of 4 bytes at c400, raw = b0 | b1 << 8 | b2 << 16: R raw[17:12], B raw[11:6], G raw[5:0].
 * Graphics in SDRAM:
 *   tiles: two 1 MB blocks (planes 7-4 = ROM eighths 3-0, planes 3-0 = eighths 7-4), each a 32-bit word per row
 *     (byte k = eighth k of the block, bit 7 leftmost): word at { block, code, y }
 *   sprites: the ROM quarters byte-interleaved, word at { code, x[3], y[3:0], x[2] } (64 bytes per sprite and quarter);
 *     quarter q byte, pixel n of 4 (bit 3-n): pen bit 2q+1 = bit 3-n, pen bit 2q = bit 7-n. */

module jtfunybubl_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,

    // CPU writes to the sprite RAM
    input       [11:0] cpu_addr,
    input       [ 7:0] cpu_dout,
    input              sram_we,

    output      [11:0] vram_video_addr,
    input       [ 7:0] vram_video_dout,
    output reg  [11:0] pal_video_addr,
    input       [ 7:0] pal_video_dout,

    output      [20:2] tile_addr,
    output reg         tile_cs,
    input       [31:0] tile_data,
    input              tile_ok,
    output      [20:2] spr_addr,
    output reg         spr_cs,
    input       [31:0] spr_data,
    input              spr_ok,

    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 7:0] red,
    output reg  [ 7:0] green,
    output reg  [ 7:0] blue
);

localparam [8:0] HTOTAL=9'd383, HS_START=9'd336, HS_END=9'd364;
localparam [8:0] VTOTAL=9'd261, VB_END=9'd16, VB_START=9'd240, VS_START=9'd246, VS_END=9'd249;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl, hs_l;
reg  [ 3:0] hbl_sh, vbl_sh;
wire [ 8:0] xdump = hdump + 9'd96;

assign LHBL     = hbl_sh[1];
assign LVBL     = vbl_sh[1];
wire   hs_start = pxl_cen && hdump==0 && !hs_l;

always @(posedge clk) if( pxl_cen ) hs_l <= hdump==0;

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    lhbl <= hdump==HTOTAL || hdump < 9'd319;
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
localparam [2:0] T_IDLE=0, T_RD=1, T_FETCH=2, T_FWAIT=3, T_WRITE=4;
reg  [ 2:0] tst;
reg  [ 7:0] tline;
reg  [ 5:0] tcol;
reg  [ 2:0] tcnt, tpx;
reg  [ 1:0] twc;
reg         tsel, tbsel, tlbuf;
reg  [15:0] tcode;
reg  [31:0] ta, tb;
wire [ 2:0] tbit = ~tpx;
wire [ 7:0] tpen = ~{ ta[24+tbit], ta[16+tbit], ta[8+tbit], ta[tbit], tb[24+tbit], tb[16+tbit], tb[8+tbit], tb[tbit] };
wire [ 8:0] tile_q;

assign vram_video_addr = { tline[7:3], tcol, tbsel };
assign tile_addr = { 1'b0, tsel, tcode[14:0], tline[2:0] };

always @(posedge clk) begin
    if( rst ) begin
        tst <= T_IDLE; tile_cs <= 0;
    end else begin
        case( tst )
            T_IDLE: if( hs_start && vrender < 9'd256 ) begin
                tline <= vrender[7:0];
                tlbuf <= vrender[0];
                tcol  <= 6'd12;
                twc   <= 0;
                tbsel <= 0;
                tst   <= T_RD;
            end
            T_RD: begin     // low byte, then high byte
                twc <= twc + 1'd1;
                if( twc==1 ) begin tcode[7:0]  <= vram_video_dout; tbsel <= 1; end
                if( twc==3 ) begin tcode[15:8] <= vram_video_dout; tbsel <= 0; tsel <= 0; tst <= T_FETCH; end
            end
            T_FETCH: begin twc <= 0; tst <= T_FWAIT; end
            T_FWAIT: begin
                tile_cs <= 1;
                if( twc!=3 ) twc <= twc + 1'd1;
                else if( tile_ok ) begin
                    tile_cs <= 0;
                    if( !tsel ) begin ta <= tile_data; tsel <= 1; tst <= T_FETCH; end
                    else begin tb <= tile_data; tpx <= 0; tst <= T_WRITE; end
                end
            end
            T_WRITE: begin
                tpx <= tpx + 1'd1;
                if( tpx==7 ) begin
                    tcol <= tcol + 1'd1;
                    twc  <= 0;
                    tst  <= tcol==6'd51 ? T_IDLE : T_RD;
                end
            end
            default: tst <= T_IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(9),.AW(10)) u_tbuf(
    .clk0   ( clk       ),
    .data0  ( { tcode[15], tpen } ),
    .addr0  ( { tlbuf, tcol, tpx } ),
    .we0    ( tst==T_WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 9'd0      ),
    .addr1  ( { vdump[0], xdump } ),
    .we1    ( 1'b0      ),
    .q1     ( tile_q    )
);

// ---------------- sprites ----------------
// bytes 0-3 of every entry, copied as the CPU writes them
localparam [2:0] S_IDLE=0, S_SCAN=1, S_EVAL=2, S_FETCH=3, S_FWAIT=4, S_DRAW=5;
reg  [ 2:0] sst;
reg  [ 7:0] sline;
reg  [ 6:0] sent;
reg  [ 1:0] swc;
reg         slbuf, sbsel, sxh;
reg  [12:0] scode;
reg  [ 3:0] sdy;
reg  [ 8:0] sx;
reg  [31:0] sa, sb;
reg  [ 2:0] spx;
wire [ 7:0] e0, e1, e2, e3;
wire [ 8:0] sdyw = { 1'b0, sline } - { 1'b0, e2 };
wire [31:0] sw   = spx[2] ? sb : sa;
wire [ 1:0] sn   = ~spx[1:0];      // bit 3-n with n = spx[1:0]
wire [ 7:0] spen = ~{ sw[24+sn], sw[28+sn], sw[16+sn], sw[20+sn], sw[8+sn], sw[12+sn], sw[sn], sw[4+sn] };
wire [ 9:0] swx  = { 1'b0, sx } + { 6'd0, sxh, spx };
wire [ 7:0] spr_q;
wire        swe  = cpu_addr[4:2]==0 && sram_we;

assign spr_addr = { scode, sxh, sdy, sbsel };

always @(posedge clk) begin
    if( rst ) begin
        sst <= S_IDLE; spr_cs <= 0;
    end else begin
        case( sst )
            S_IDLE: if( hs_start && vrender < 9'd256 ) begin
                sline <= vrender[7:0];
                slbuf <= vrender[0];
                sent  <= 7'd127;
                swc   <= 0;
                sst   <= S_SCAN;
            end
            S_SCAN: begin   // wait for the entry copies
                swc <= swc + 1'd1;
                if( swc==1 ) sst <= S_EVAL;
            end
            S_EVAL: begin
                swc <= 0;
                if( sdyw < 9'd16 ) begin
                    scode <= { e1[7], e1[3:0], e0 } ;
                    sx    <= { e1[5] && e3 < 8'he0, e3 };
                    sdy   <= sdyw[3:0];
                    sxh   <= 0;
                    sbsel <= 0;
                    sst   <= S_FETCH;
                end else begin
                    sent <= sent - 1'd1;
                    sst  <= sent==0 ? S_IDLE : S_SCAN;
                end
            end
            S_FETCH: begin swc <= 0; sst <= S_FWAIT; end
            S_FWAIT: begin
                spr_cs <= 1;
                if( swc!=3 ) swc <= swc + 1'd1;
                else if( spr_ok ) begin
                    spr_cs <= 0;
                    if( !sbsel ) begin sa <= spr_data; sbsel <= 1; sst <= S_FETCH; end
                    else begin sb <= spr_data; spx <= 0; sst <= S_DRAW; end
                end
            end
            S_DRAW: begin
                spx <= spx + 1'd1;
                if( spx==7 ) begin
                    sbsel <= 0;
                    swc   <= 0;
                    if( !sxh ) begin sxh <= 1; sst <= S_FETCH; end
                    else begin
                        sent <= sent - 1'd1;
                        sst  <= sent==0 ? S_IDLE : S_SCAN;
                    end
                end
            end
            default: sst <= S_IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(7)) u_e0( .clk0(clk), .data0(cpu_dout), .addr0(cpu_addr[11:5]), .we0(swe && cpu_addr[1:0]==0), .q0(),
    .clk1(clk), .data1(8'd0), .addr1(sent), .we1(1'b0), .q1(e0) );
jtframe_dual_ram #(.DW(8),.AW(7)) u_e1( .clk0(clk), .data0(cpu_dout), .addr0(cpu_addr[11:5]), .we0(swe && cpu_addr[1:0]==1), .q0(),
    .clk1(clk), .data1(8'd0), .addr1(sent), .we1(1'b0), .q1(e1) );
jtframe_dual_ram #(.DW(8),.AW(7)) u_e2( .clk0(clk), .data0(cpu_dout), .addr0(cpu_addr[11:5]), .we0(swe && cpu_addr[1:0]==2), .q0(),
    .clk1(clk), .data1(8'd0), .addr1(sent), .we1(1'b0), .q1(e2) );
jtframe_dual_ram #(.DW(8),.AW(7)) u_e3( .clk0(clk), .data0(cpu_dout), .addr0(cpu_addr[11:5]), .we0(swe && cpu_addr[1:0]==3), .q0(),
    .clk1(clk), .data1(8'd0), .addr1(sent), .we1(1'b0), .q1(e3) );

jtframe_dual_ram #(.DW(8),.AW(10)) u_sbuf(
    .clk0   ( clk       ),
    .data0  ( spen      ),
    .addr0  ( { slbuf, swx[8:0] } ),
    .we0    ( sst==S_DRAW && spen!=8'hff && !swx[9] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'hff     ),
    .addr1  ( { vdump[0], xdump } ),
    .we1    ( pxl_cen   ),
    .q1     ( spr_q     )
);

// ---------------- mixer and palette ----------------
reg  [ 9:0] pidx;
reg         pblk;
reg  [ 2:0] pcnt;
reg  [ 7:0] pb0, pb1, pb2;
wire        t_op = tile_q[7:0] != 0 && gfx_en[0];
wire        s_op = spr_q != 8'hff && gfx_en[3];

always @(posedge clk) begin
    if( pxl_cen ) begin
        pidx <= s_op ? { 2'b00, spr_q } : { tile_q[8], ~tile_q[8], tile_q[7:0] };
        pblk <= !s_op && !t_op;
        pcnt <= 0;
        red   <= pblk ? 8'd0 : { pb2[1:0], pb1[7:4], pb2[1:0] };
        green <= pblk ? 8'd0 : { pb0[5:0], pb0[5:4] };
        blue  <= pblk ? 8'd0 : { pb1[3:0], pb0[7:6], pb1[3:2] };
    end else if( pcnt != 3'd7 ) pcnt <= pcnt + 1'd1;
    pal_video_addr <= 12'h400 + { pidx, pcnt[1:0] };
    if( pcnt==2 ) pb0 <= pal_video_dout;
    if( pcnt==3 ) pb1 <= pal_video_dout;
    if( pcnt==4 ) pb2 <= pal_video_dout;
end

endmodule
