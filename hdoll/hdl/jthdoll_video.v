/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Honey Doll video (MAME snowbros_v.cpp screen_update_honeydol): sprites only, over palette entry 0xf0.
 *   6 MHz pixel clock, 400x262 (57.3 Hz). Visible 256x224 = MAME rows 16-239.
 *   512 entries of 8 words. Each entry holds two sprites, drawn in this order (later ones on top):
 *     high bytes: 16x16x8   x = w4, y = w5, colour = w3 & 3 (x 256), tile = { w7 & 3f, w6 }, w7 bit 7 flip x, bit 6 flip y
 *     low bytes:  16x16x4   x = w4, y = w5, colour = ((w3 >> 4) & 3f) ^ 3f (x 16), tile = { w7 & 3f, w6 }, flips as above
 *   Pen 0 transparent. Palette: 1024 words xBGR_555.
 * Graphics in SDRAM:
 *   8 bpp: the two ROM halves byte-interleaved (first half = pen bits 7-4), quadrants TL, TR, BL, BR of 32 bytes per half;
 *          8 pixels = two 32-bit words at { tile, y[3], x[3], y[2:0], word }
 *   4 bpp: the ROM as is, 32-bit word (8 pixels) at { tile, y[3], x[3], y[2:0] } (gfx_8x8x4_row_2x2_group_packed_msb) */

module jthdoll_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,

    // CPU writes to the sprite RAM
    input       [12:1] cpu_addr,
    input       [15:0] cpu_dout,
    input       [ 1:0] oram_we,
    output reg  [10:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [20:2] o8_addr,
    output reg         o8_cs,
    input       [31:0] o8_data,
    input              o8_ok,
    output      [18:2] o4_addr,
    output reg         o4_cs,
    input       [31:0] o4_data,
    input              o4_ok,

    output reg  [ 8:0] vdump,
    output             hs_start,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd399, HS_START=9'd300, HS_END=9'd332;
localparam [8:0] VTOTAL=9'd261, VB_END=9'd16, VB_START=9'd240, VS_START=9'd248, VS_END=9'd251;

reg  [ 8:0] hdump=0, vrender=1;
reg         lhbl, lvbl, hs_l;
reg  [ 3:0] hbl_sh, vbl_sh;
initial vdump = 0;

assign LHBL     = hbl_sh[1];
assign LVBL     = vbl_sh[1];
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

// ---------------- sprite line renderer ----------------
// Words 3-7 of every entry are mirrored into five 512x16 RAMs (written along with the CPU's sprite RAM),
// so a whole entry is read in one clock while scanning for the sprites on the next line.
localparam [2:0] IDLE=0, SCAN=1, FETCH=2, FWAIT=3, DRAW=4, NEXT=5;
reg  [ 2:0] st;
reg  [ 7:0] line;
reg  [ 8:0] ent, he;
reg  [ 9:0] t1, t2;           // { valid, entry } of the reads in flight
reg         lbuf, issue;
reg         h8, h4, m8;
reg  [ 3:0] dy8, dy4;
reg  [15:0] c3, c4, c6, c7;
reg  [ 1:0] wcnt;
reg         sh, wsel;
reg  [31:0] wa, wb;
reg  [ 2:0] px;
// fetch caches (unused sprites usually share one blank tile)
reg  [19:0] k8; reg [31:0] k8a, k8b; reg k8v;
reg  [18:0] k4; reg [31:0] k4a;      reg k4v;
wire [15:0] q3, q4, q5, q6, q7;
wire [ 8:0] d8 = { 1'b0, line } - { 1'b0, q5[15:8] };
wire [ 8:0] d4 = { 1'b0, line } - { 1'b0, q5[ 7:0] };
wire        y8 = d8[8:4] == 0, y4 = d4[8:4] == 0;
wire        fx   = m8 ? c7[15] : c7[7];
wire        fy   = m8 ? c7[14] : c7[6];
wire [ 3:0] row  = (m8 ? dy8 : dy4) ^ {4{fy}};
wire        th   = sh ^ fx;
wire [ 7:0] sx   = m8 ? c4[15:8] : c4[7:0];
wire [ 2:0] pxf  = px ^ {3{fx}};
wire [ 8:0] wx   = { 1'b0, sx } + { 5'd0, sh, px };
wire [31:0] w8   = pxf[2] ? wb : wa;
wire [ 7:0] fb   = w8[ {pxf[1],4'd0} +: 8 ];
wire [ 7:0] sb   = w8[ {pxf[1],4'd8} +: 8 ];
wire [ 7:0] pen8 = pxf[0] ? { fb[3:0], sb[3:0] } : { fb[7:4], sb[7:4] };
wire [ 3:0] pen4 = wa[ { pxf[2:1], ~pxf[0], 2'd0 } +: 4 ];
wire [ 9:0] widx = m8 ? { c3[9:8], pen8 } : { c3[9:4] ^ 6'h3f, pen4 };
wire        wop  = m8 ? pen8 != 0 : pen4 != 0;
wire [ 9:0] lq;
// rows known to be blank (both halves), checked while scanning so parked sprites cost one clock
reg  [16:0] b8key; reg b8v;
reg  [15:0] b4key; reg b4v;
reg         z0, z1;             // half 0 / half 1 of the current row were blank
wire [ 3:0] srow8 = d8[3:0] ^ {4{q7[14]}};
wire [ 3:0] srow4 = d4[3:0] ^ {4{q7[6]}};
wire        skip8 = !y8 || (b8v && b8key == { q7[12:8], q6[15:8], srow8 });
wire        skip4 = !y4 || (b4v && b4key == { q7[3:0],  q6[7:0],  srow4 });
wire [19:0] key8 = { c7[12:8], c6[15:8], row, th, 2'd0 };
wire [18:0] key4 = { 1'b0, c7[3:0], c6[7:0], row, th };

assign o8_addr = { c7[12:8], c6[15:8], row[3], th, row[2:0], wsel };
assign o4_addr = { c7[3:0],  c6[7:0],  row[3], th, row[2:0] };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; o8_cs <= 0; o4_cs <= 0; k8v <= 0; k4v <= 0; b8v <= 0; b4v <= 0;
    end else case( st )
        IDLE: if( hs_start ) begin
            line <= vrender[7:0]; lbuf <= vrender[0]; ent <= 0; issue <= !vrender[8]; t1 <= 0; t2 <= 0;
            st <= vrender[8] ? IDLE : SCAN;
        end
        SCAN: begin     // one entry per clock
            t1 <= { issue, ent };
            t2 <= t1;
            if( issue ) begin
                ent <= ent + 1'd1;
                if( &ent ) issue <= 0;
            end
            if( t2[9] && (y8 || y4) && !(skip8 && skip4) ) begin
                he <= t2[8:0]; h8 <= y8; h4 <= y4; m8 <= y8; dy8 <= d8[3:0]; dy4 <= d4[3:0];
                c3 <= q3; c4 <= q4; c6 <= q6; c7 <= q7; sh <= 0;
                ent <= t2[8:0] + 1'd1; issue <= t2[8:0] != 9'h1ff;
                st <= FETCH;
            end else if( t2[9] && t2[8:0]==9'h1ff ) st <= IDLE;
            else if( !t2[9] && !t1[9] && !issue ) st <= IDLE;
        end
        FETCH: begin
            wcnt <= 0; wsel <= 0; px <= 0;
            if( m8 && k8v && k8 == key8 ) begin
                wa <= k8a; wb <= k8b;
                if( k8a==0 && k8b==0 ) begin px <= 7; st <= DRAW; end else st <= DRAW;
            end else if( !m8 && k4v && k4 == key4 ) begin
                wa <= k4a;
                if( k4a==0 ) begin px <= 7; st <= DRAW; end else st <= DRAW;
            end else st <= FWAIT;
        end
        FWAIT: begin
            if( m8 ) o8_cs <= 1; else o4_cs <= 1;
            if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
            else if( m8 ? o8_ok : o4_ok ) begin
                o8_cs <= 0; o4_cs <= 0;
                if( m8 ) begin
                    if( !wsel ) begin wa <= o8_data; wsel <= 1; wcnt <= 0; end
                    else begin
                        wb <= o8_data; px <= 0; st <= DRAW;
                        k8 <= key8; k8a <= wa; k8b <= o8_data; k8v <= 1;
                        if( wa==0 && o8_data==0 ) px <= 7;
                    end
                end else begin
                    wa <= o4_data; px <= 0; st <= DRAW;
                    k4 <= key4; k4a <= o4_data; k4v <= 1;
                    if( o4_data==0 ) px <= 7;
                end
            end
        end
        DRAW: begin
            px <= px + 1'd1;
            if( px==7 ) begin
                if( !sh ) begin
                    z0 <= m8 ? (wa==0 && wb==0) : wa==0;
                    sh <= 1; st <= FETCH;
                end else begin
                    if( m8 ) begin
                        if( z0 && wa==0 && wb==0 ) begin b8key <= { c7[12:8], c6[15:8], row }; b8v <= 1; end
                    end else begin
                        if( z0 && wa==0 ) begin b4key <= { c7[3:0], c6[7:0], row }; b4v <= 1; end
                    end
                    if( m8 && h4 ) begin m8 <= 0; sh <= 0; st <= FETCH; end
                    else st <= NEXT;
                end
            end
        end
        NEXT: begin
            t1 <= 0; t2 <= 0;
            st <= issue ? SCAN : IDLE;
        end
        default: st <= IDLE;
    endcase
end

// entry word copies, written with the CPU's sprite RAM (byte enables per word)
jtframe_dual_ram16 #(.AW(9)) u_w3(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[12:4] ), .we0( cpu_addr[3:1]==3'd3 ? oram_we : 2'b00 ), .q0(),
    .clk1( clk ), .data1( 16'd0 ), .addr1( ent ), .we1( 2'b00 ), .q1( q3 ) );
jtframe_dual_ram16 #(.AW(9)) u_w4(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[12:4] ), .we0( cpu_addr[3:1]==3'd4 ? oram_we : 2'b00 ), .q0(),
    .clk1( clk ), .data1( 16'd0 ), .addr1( ent ), .we1( 2'b00 ), .q1( q4 ) );
jtframe_dual_ram16 #(.AW(9)) u_w5(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[12:4] ), .we0( cpu_addr[3:1]==3'd5 ? oram_we : 2'b00 ), .q0(),
    .clk1( clk ), .data1( 16'd0 ), .addr1( ent ), .we1( 2'b00 ), .q1( q5 ) );
jtframe_dual_ram16 #(.AW(9)) u_w6(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[12:4] ), .we0( cpu_addr[3:1]==3'd6 ? oram_we : 2'b00 ), .q0(),
    .clk1( clk ), .data1( 16'd0 ), .addr1( ent ), .we1( 2'b00 ), .q1( q6 ) );
jtframe_dual_ram16 #(.AW(9)) u_w7(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[12:4] ), .we0( cpu_addr[3:1]==3'd7 ? oram_we : 2'b00 ), .q0(),
    .clk1( clk ), .data1( 16'd0 ), .addr1( ent ), .we1( 2'b00 ), .q1( q7 ) );


jtframe_dual_ram #(.DW(10),.AW(9)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( widx      ),
    .addr0  ( { lbuf, wx[7:0] } ),
    .we0    ( st==DRAW && wop && !wx[8] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 10'h0f0   ),
    .addr1  ( { vdump[0], hdump[7:0] } ),
    .we1    ( pxl_cen && !hdump[8] ),
    .q1     ( lq        )
);

always @(posedge clk) if( pxl_cen ) begin
    pal_video_addr <= gfx_en[3] ? lq : 10'h0f0;
    red   <= pal_video_dout[ 4: 0];
    green <= pal_video_dout[ 9: 5];
    blue  <= pal_video_dout[14:10];
end

endmodule
