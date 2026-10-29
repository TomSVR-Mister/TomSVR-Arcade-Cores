/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Kaneko Pandora sprites (MAME kaneko/kan_pand.cpp), frame buffer version.
 *   MAME draws all 512 entries into a 256x256 frame buffer at the start of vblank and shows it during the next
 *   frame. Here the sprite RAM is copied to a shadow at line 240 (CPU sprite RAM accesses wait while the copy
 *   runs) and the frame is then drawn line by line from the shadow into a 256x256 frame buffer, well ahead of the
 *   display. The display clears each pixel after reading it unless clearing is off (Air Buster port 00 bit 5 = 0
 *   leaves sprite trails at the end of a level; MAME keeps two buffers, this keeps one).
 *   Entry of 8 bytes, bytes 0-2 unused:
 *     3: colour (bits 7-4), bit 2 = relative (add x/y to the previous entry's), bit 1 = y bit 8, bit 0 = x bit 8
 *     4: x   5: y   6: tile low   7: bit 7 flip x, bit 6 flip y, bits 5-0 tile high
 *   Later entries are drawn on top; pen 0 is transparent.
 * Graphics: gfx_8x8x4_row_2x2_group_packed_msb, 128 bytes per tile. Air Buster has 0x1200 tiles (MAME region
 *   0x100000 filled with zeros past them); those are drawn blank. */
module jtdjboy_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              hs_start,
    input       [ 8:0] vdump,
    input       [ 8:0] hdump,
    input              abus,
    input              clr,         // clear the frame buffer as it is shown
    // sprite RAM copy
    output reg  [11:0] ovid_addr,
    input       [ 7:0] ovid_dout,
    output             ocopy,

    output      [20:2] gfx_addr,
    output reg         gfx_cs,
    input       [31:0] gfx_data,
    input              gfx_ok,
    output      [ 7:0] pxl
);

localparam [8:0] VB_END=9'd16, VB_START=9'd240;

// ---------------- sprite RAM copy at the start of vblank ----------------
reg  [12:0] ccnt;           // bit 12 = done
reg  [11:0] cwa;
reg         cwv, go;

assign ocopy = !ccnt[12] || cwv;

always @(posedge clk) begin
    go <= 0;
    if( rst ) begin
        ccnt <= 13'h1000; cwv <= 0;
    end else begin
        if( hs_start && vdump==VB_START ) ccnt <= 0;
        else if( !ccnt[12] ) begin
            ccnt <= ccnt + 1'd1;
            if( &ccnt[11:0] ) go <= 1;
        end
        ovid_addr <= ccnt[11:0];
        cwa <= ovid_addr;
        cwv <= !ccnt[12];
    end
end

// ---------------- sprite renderer, lines 16-239 one after another ----------------
localparam [2:0] IDLE=0, SCAN=1, FETCH=2, FWAIT=3, DRAW=4, NEXT=5;
reg  [ 2:0] st;
reg  [ 8:0] line;
reg  [ 8:0] ent;
reg  [ 9:0] t1;               // { valid, entry } of the read in flight (BRAM data comes one clock later)
reg         issue;
reg  [ 8:0] cx, cy;           // position chain (relative entries add to it)
reg  [ 3:0] dy, col;
reg  [13:0] tile;
reg         fx, fy, half, blank;
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
wire [31:0] wsel = xx[3] ? wb : wa;
wire [ 3:0] pen  = wsel[ { xx[2:1], ~xx[0], 2'd0 } +: 4 ];
wire [ 8:0] wx   = sx + { 5'd0, px };
wire        tblank = abus && tile[12:0] >= 13'h1200;

assign gfx_addr = { tile, row[3], half, row[2:0] };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; gfx_cs <= 0; kv <= 0; bv <= 0;
    end else case( st )
        IDLE: if( go ) begin
            line <= VB_END; ent <= 0; t1 <= 0; cx <= 0; cy <= 0; issue <= 1; bv <= 0;
            st <= SCAN;
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
                end else if( t1[8:0]==9'h1ff ) st <= NEXT;
            end
        end
        FETCH: begin
            wcnt <= 0; half <= 0; px <= 0;
            if( tblank ) st <= NEXT;
            else if( kv && kkey == key ) begin
                wa <= ka; wb <= kb; st <= DRAW;
                if( ka==0 && kb==0 ) st <= NEXT;
            end else st <= FWAIT;
        end
        FWAIT: begin
            gfx_cs <= 1;
            if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
            else if( gfx_ok ) begin
                gfx_cs <= 0;
                wcnt   <= 0;
                if( !half ) begin wa <= gfx_data; half <= 1; end
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
            if( issue ) st <= SCAN;
            else if( line==VB_START-9'd1 ) st <= IDLE;
            else begin
                line <= line + 1'd1; ent <= 0; cx <= 0; cy <= 0; issue <= 1;
                st <= SCAN;
            end
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

// frame buffer: { colour, pen }, 0 = no sprite
jtframe_dual_ram #(.DW(8),.AW(16)) u_fb(
    .clk0   ( clk       ),
    .data0  ( { col, pen } ),
    .addr0  ( { line[7:0], wx[7:0] } ),
    .we0    ( st==DRAW && pen!=0 && !wx[8] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[7:0], hdump[7:0] } ),
    .we1    ( pxl_cen && clr && !hdump[8] && vdump>=VB_END && vdump<VB_START ),
    .q1     ( pxl       )
);

endmodule
