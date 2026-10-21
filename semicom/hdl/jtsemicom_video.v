/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SemiCom video (MAME snowbros.cpp screen_update_snowbros + kan_pand.cpp): Kaneko Pandora sprites only.
 *   6 MHz pixel clock, 400x262 (57.3 Hz). Visible 256x224 = MAME rows 16-239.
 *   The Pandora draws all 512 sprites into a frame buffer at the start of vblank (line 240) and that buffer is
 *   shown during the next frame. Here the sprite RAM is copied to a shadow at line 240 and the next frame is
 *   rendered line by line from the shadow (same result). CPU sprite RAM accesses wait while the copy runs.
 *   Entry of 8 bytes, bytes 0-2 unused:
 *     3: colour (bits 7-4), bit 2 = relative (add x/y to the previous entry's), bit 1 = y bit 8, bit 0 = x bit 8
 *     4: x   5: y   6: tile low   7: bit 7 flip x, bit 6 flip y, bits 5-0 tile high
 *   Later entries are drawn on top; pen 0 is transparent; empty pixels show palette entry bg_pen (0xf0, Puzzle
 *   Break 0xc0). Palette: 256 words xBGR_555 (16 colours x 16).
 * Graphics in SDRAM: the ROM as is (MAME hyperpac_tilelayout), 128 bytes per 16x16 tile. Row y is two 32-bit words
 *   at { tile, y[2], half, y[3], y[0], y[1] }; pixel x is in word half = x[1], byte { x[2], x[3] }, high nibble
 *   when x[0] is set. */

module jtsemicom_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 7:0] bg_pen,

    // sprite RAM copy
    output reg  [11:0] ovid_addr,
    input       [ 7:0] ovid_dout,
    output             ocopy,
    output reg  [ 8:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [20:2] gfx_addr,
    output reg         gfx_cs,
    input       [31:0] gfx_data,
    input              gfx_ok,

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

// ---------------- sprite RAM copy at the start of vblank ----------------
reg  [12:0] ccnt;           // bit 12 = done
reg  [11:0] cwa;
reg         cwv;

assign ocopy = !ccnt[12] || cwv;

always @(posedge clk) begin
    if( rst ) begin
        ccnt <= 13'h1000; cwv <= 0;
    end else begin
        if( hs_start && vdump==VB_START ) ccnt <= 0;
        else if( !ccnt[12] ) ccnt <= ccnt + 1'd1;
        ovid_addr <= ccnt[11:0];
        cwa <= ovid_addr;
        cwv <= !ccnt[12];
    end
end

// ---------------- sprite line renderer ----------------
localparam [2:0] IDLE=0, SCAN=1, FETCH=2, FWAIT=3, DRAW=4, NEXT=5;
reg  [ 2:0] st;
reg  [ 8:0] line;
reg  [ 8:0] ent;
reg  [ 9:0] t1;               // { valid, entry } of the read in flight (BRAM data comes one clock later)
reg         lbuf, issue;
reg  [ 8:0] cx, cy;           // position chain (relative entries add to it)
reg  [ 3:0] dy, col;
reg  [13:0] tile;
reg         fx, fy, half;
reg  [ 1:0] wcnt;
reg  [31:0] wa, wb;
reg  [ 3:0] px;
reg  [ 8:0] sx;
// fetch cache (parked sprites usually share one blank tile) and the last row known to be blank
reg  [17:0] kkey; reg [31:0] ka, kb; reg kv;
reg  [17:0] bkey; reg bv;
wire [ 7:0] q3, q4, q5, q6, q7;
wire [ 8:0] dx_e = { q3[0], q4 }, dy_e = { q3[1], q5 };
wire [ 8:0] nx   = q3[2] ? cx + dx_e : dx_e;
wire [ 8:0] ny   = q3[2] ? cy + dy_e : dy_e;
wire [ 8:0] drow = line - ny;
wire        yhit = drow[8:4] == 0;
wire        xoff = nx >= 9'd256 && nx <= 9'h1f0;
wire [ 3:0] srow = drow[3:0] ^ {4{q7[6]}};
wire [17:0] skey = { q7[5:0], q6, srow };
wire        hit  = yhit && !xoff && !(bv && bkey == skey);
wire [ 3:0] row  = dy ^ {4{fy}};
wire [17:0] key  = { tile, row };
wire [ 3:0] xx   = px ^ {4{fx}};
wire [31:0] wsel = xx[1] ? wb : wa;
wire [ 3:0] pen  = wsel[ { xx[2], xx[3], xx[0], 2'd0 } +: 4 ];
wire [ 8:0] wx   = sx + { 5'd0, px };
wire [ 7:0] lq;

assign gfx_addr = { tile, row[2], half, row[3], row[0], row[1] };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; gfx_cs <= 0; kv <= 0; bv <= 0;
    end else case( st )
        IDLE: if( hs_start ) begin
            line <= vrender; lbuf <= vrender[0]; ent <= 0; t1 <= 0; cx <= 0; cy <= 0;
            issue <= vrender >= VB_END && vrender < VB_START;
            st <= vrender >= VB_END && vrender < VB_START ? SCAN : IDLE;
        end
        SCAN: begin     // one entry per clock
            t1 <= { issue, ent };
            if( issue ) begin
                ent <= ent + 1'd1;
                if( &ent ) issue <= 0;
            end
            if( t1[9] ) begin
                cx <= nx; cy <= ny;
                if( hit ) begin
                    dy <= drow[3:0]; col <= q3[7:4]; tile <= { q7[5:0], q6 }; fx <= q7[7]; fy <= q7[6]; sx <= nx;
                    ent <= t1[8:0] + 1'd1; issue <= t1[8:0] != 9'h1ff; t1 <= 0;
                    st <= FETCH;
                end else if( t1[8:0]==9'h1ff ) st <= IDLE;
            end
        end
        FETCH: begin
            wcnt <= 0; half <= 0; px <= 0;
            if( kv && kkey == key ) begin
                wa <= ka; wb <= kb; st <= DRAW;
                if( ka==0 && kb==0 ) st <= NEXT;
            end else st <= FWAIT;
        end
        FWAIT: begin
            gfx_cs <= 1;
            if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
            else if( gfx_ok ) begin
                gfx_cs <= 0;
                if( !half ) begin wa <= gfx_data; half <= 1; wcnt <= 0; end
                else begin
                    wb <= gfx_data; st <= DRAW;
                    kkey <= key; ka <= wa; kb <= gfx_data; kv <= 1;
                    if( wa==0 && gfx_data==0 ) begin
                        bkey <= key; bv <= 1; st <= NEXT;
                    end
                end
            end
        end
        DRAW: begin
            px <= px + 1'd1;
            if( px==15 ) st <= NEXT;
        end
        NEXT: begin
            t1 <= 0;
            st <= issue ? SCAN : IDLE;
        end
        default: st <= IDLE;
    endcase
end

// entry byte copies (bytes 3-7), written by the copy at the start of vblank
jtframe_dual_ram #(.AW(9)) u_b3(
    .clk0( clk ), .data0( ovid_dout ), .addr0( cwa[11:3] ), .we0( cwv && cwa[2:0]==3'd3 ), .q0(),
    .clk1( clk ), .data1( 8'd0 ), .addr1( ent ), .we1( 1'b0 ), .q1( q3 ) );
jtframe_dual_ram #(.AW(9)) u_b4(
    .clk0( clk ), .data0( ovid_dout ), .addr0( cwa[11:3] ), .we0( cwv && cwa[2:0]==3'd4 ), .q0(),
    .clk1( clk ), .data1( 8'd0 ), .addr1( ent ), .we1( 1'b0 ), .q1( q4 ) );
jtframe_dual_ram #(.AW(9)) u_b5(
    .clk0( clk ), .data0( ovid_dout ), .addr0( cwa[11:3] ), .we0( cwv && cwa[2:0]==3'd5 ), .q0(),
    .clk1( clk ), .data1( 8'd0 ), .addr1( ent ), .we1( 1'b0 ), .q1( q5 ) );
jtframe_dual_ram #(.AW(9)) u_b6(
    .clk0( clk ), .data0( ovid_dout ), .addr0( cwa[11:3] ), .we0( cwv && cwa[2:0]==3'd6 ), .q0(),
    .clk1( clk ), .data1( 8'd0 ), .addr1( ent ), .we1( 1'b0 ), .q1( q6 ) );
jtframe_dual_ram #(.AW(9)) u_b7(
    .clk0( clk ), .data0( ovid_dout ), .addr0( cwa[11:3] ), .we0( cwv && cwa[2:0]==3'd7 ), .q0(),
    .clk1( clk ), .data1( 8'd0 ), .addr1( ent ), .we1( 1'b0 ), .q1( q7 ) );

// line buffer: holds palette indexes; cleared to the background pen as it is read out
jtframe_dual_ram #(.DW(8),.AW(9)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { col, pen } ),
    .addr0  ( { lbuf, wx[7:0] } ),
    .we0    ( st==DRAW && pen!=0 && !wx[8] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( bg_pen    ),
    .addr1  ( { vdump[0], hdump[7:0] } ),
    .we1    ( pxl_cen && !hdump[8] ),
    .q1     ( lq        )
);

always @(posedge clk) if( pxl_cen ) begin
    pal_video_addr <= gfx_en[3] ? lq : bg_pen;
    red   <= pal_video_dout[ 4: 0];
    green <= pal_video_dout[ 9: 5];
    blue  <= pal_video_dout[14:10];
end

endmodule
