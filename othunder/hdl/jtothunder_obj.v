/* SPDX-License-Identifier: GPL-3.0-or-later
   Operation Thunderbolt sprites (TC0320OBR, TC0020VAR, TC0050VDZ), after MAME othunder_v.cpp.
   Each 64x64 sprite is 4x8 chunks of 16x8 pixels; the sprite map ROM gives the chunk tile codes.
   Sprites zoom down to 1/64 in each direction. Sprites are drawn one line ahead into a double line
   buffer, last entry first, so entry 0 ends up in front (as MAME's pdrawgfx with its priority mask).

   Sprite RAM, four words per entry:
   0: 15-9 zoom Y, 8-0 Y          1: 15 priority (1 = behind BG layer), 14 flip X, 8-0 X
   2: 15-8 colour, 6-0 zoom X     3: 15 flip Y, 12-0 sprite number (0 = unused)            */

module jtothunder_obj(
    input             rst,
    input             clk,

    input             start,
    input      [ 8:0] vrender,
    input             wr_bank,
    input             rd_bank,
    input      [ 8:0] rd_x,
    input             pxl_cen,

    // CPU
    input      [10:1] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input             cpu_rnw,
    input             obj_cs,
    output     [15:0] cpu_din,

    // sprite map ROM, 16-bit entries
    output reg [18:2] map_addr,
    output reg        map_cs,
    input             map_ok,
    input      [31:0] map_data,

    // 16x8 tiles, one 16-bit word per plane: planes 0-1 here and planes 2-3 in another SDRAM bank,
    // so both halves of a row arrive together
    output reg [19:2] rom_addr,
    output reg        rom_cs,
    input             rom_ok,
    input      [31:0] rom_data,
    output reg [19:2] rom2_addr,
    output reg        rom2_cs,
    input             rom2_ok,
    input      [31:0] rom2_data,

    output reg [12:0] pxl         // {priority, colour, pen}
);

// The scan reads word 0 of one entry per clock and only stops for sprites on this line.
// Chunk fetches (sprite map + one tile row read from each of two SDRAM banks) run while the previous
// chunk is drawn at two pixels per clock (even and odd x in separate line buffers);
// chunks fully outside the 320 pixel window are skipped and each 32-bit map read serves two chunks.
localparam [3:0] IDLE=0, SCAN=1, H1=2, H2=3, H3=4, H4=5, FINDJ=6, CHK=7, CHUNK=8,
                 MAPW=9, T0W0=10, T0W=11, HAND=14, NEXT=15;

reg  [ 3:0] st;
reg  [ 7:0] sidx, tag1, tag2, hidx;
reg         v1, v2, sdone;
reg  [ 9:0] oaddr;
wire [15:0] odata;
reg  [15:0] w0r, w1, w2;
reg  [10:0] dy;
reg  [ 9:0] xsig;
reg  [ 7:0] zoomy, zoomx;
reg  [10:0] yacc, ynext;
reg  [ 2:0] jrow, srow;
reg  [ 4:0] zy, ry;
reg  [ 1:0] kc;
reg  [ 9:0] xacc, xnext;
reg  [ 5:0] zx;
reg  [12:0] tilenum;
reg  [21:0] stepx;
reg  [24:0] syacc;
reg         flipx, flipy, oprio;
reg  [ 7:0] ocol;
reg  [10:0] curx;
reg  [16:0] map_tag;
reg         map_vld;
reg  [31:0] map_q;
reg  [15:0] f0, f1, f2, f3;
reg  [ 1:0] hs, got;

// drawer
reg         d_busy, d_flipx, d_prio;
reg  [ 7:0] d_col;
reg  [ 5:0] d_zx, icnt;
reg  [21:0] d_stepx;
reg  [25:0] sxacc;
reg  [ 8:0] wx;
reg  [15:0] pl0, pl1, pl2, pl3;
// two pixels per clock: pixel A at wx and pixel B at wx+1 go to different (even/odd x) buffers
wire [25:0] sxnx = d_flipx ? sxacc - {4'd0,d_stepx} : sxacc + {4'd0,d_stepx};
wire [ 3:0] sxa  = sxacc[19:16], sxb = sxnx[19:16];
wire [ 3:0] pena = { pl0[~sxa], pl1[~sxa], pl2[~sxa], pl3[~sxa] };
wire [ 3:0] penb = { pl0[~sxb], pl1[~sxb], pl2[~sxb], pl3[~sxb] };
wire        wea  = d_busy && pena!=0;
wire        web  = d_busy && penb!=0 && icnt+1'd1 != d_zx;
wire [ 8:0] wxb  = wx + 1'd1;
wire [ 3:0] pen_e = wx[0] ? penb : pena,  pen_o = wx[0] ? pena : penb;
wire        we_e  = wx[0] ? web  : wea,   we_o  = wx[0] ? wea  : web;
wire [ 7:0] ax_e  = wx[0] ? wxb[8:1] : wx[8:1];
wire [ 7:0] ax_o  = wx[8:1];
wire [12:0] q1, q_e, q_o;
assign q1 = rd_x[0] ? q_o : q_e;
reg  [ 2:0] ecnt;
wire        erase = ecnt==3;

// word 0 visibility test
wire [ 9:0] ys0   = {1'b0, w0r[8:0]} + 10'd3;
wire [10:0] ysig0 = {1'b0, ys0} - ((ys0 > 10'h140) ? 11'h200 : 11'd0);
wire [10:0] dy0   = {2'd0, vrender} - ysig0;
wire [ 7:0] zy0   = { 1'b0, w0r[15:9] } + 8'd1;
wire        hit0  = v2 && !dy0[10] && dy0 < {3'd0, zy0};
wire [ 5:0] cz    = xnext[7:2] - xacc[7:2];
wire [11:0] xend  = { curx[10], curx } + { 6'd0, cz };
wire [16:0] mtag  = { tilenum, jrow, kc[1]^flipx };
wire [14:0] mcode = (kc[0]^flipx) ? map_q[30:16] : map_q[14:0];

`ifdef SIMULATION
integer short_lines=0, c_map=0, c_rom=0, c_r1=0, c_r2=0, c_hand=0, c_scan=0, n_chunk=0;
always @(posedge clk) begin
    if( start ) begin
        if( st!=IDLE ) begin
            short_lines <= short_lines+1;
            $display("OBJ short line %0d (total %0d) map %0d rom %0d (r1 %0d r2 %0d) hand %0d scan %0d chunks %0d",
                vrender, short_lines+1, c_map, c_rom, c_r1, c_r2, c_hand, c_scan, n_chunk);
        end
        c_map<=0; c_rom<=0; c_r1<=0; c_r2<=0; c_hand<=0; c_scan<=0; n_chunk<=0;
    end else begin
        if( st==MAPW ) c_map <= c_map+1;
        if( st==T0W  ) c_rom <= c_rom+1;
        if( st==T0W && !got[0] ) c_r1 <= c_r1+1;
        if( st==T0W && !got[1] ) c_r2 <= c_r2+1;
        if( st==HAND ) c_hand <= c_hand+1;
        if( st==SCAN ) c_scan <= c_scan+1;
        if( st==HAND && !d_busy ) n_chunk <= n_chunk+1;
    end
end
`endif

function [21:0] step16( input [5:0] n );   // (16<<16)/n
    case( n )
         1: step16=22'd1048576;  2: step16=22'd524288;   3: step16=22'd349525;   4: step16=22'd262144;
         5: step16=22'd209715;   6: step16=22'd174762;   7: step16=22'd149796;   8: step16=22'd131072;
         9: step16=22'd116508;  10: step16=22'd104857;  11: step16=22'd95325;   12: step16=22'd87381;
        13: step16=22'd80659;   14: step16=22'd74898;   15: step16=22'd69905;   16: step16=22'd65536;
        17: step16=22'd61680;   18: step16=22'd58254;   19: step16=22'd55188;   20: step16=22'd52428;
        21: step16=22'd49932;   22: step16=22'd47662;   23: step16=22'd45590;   24: step16=22'd43690;
        25: step16=22'd41943;   26: step16=22'd40329;   27: step16=22'd38836;   28: step16=22'd37449;
        29: step16=22'd36157;   30: step16=22'd34952;   31: step16=22'd33825;   32: step16=22'd32768;
        default: step16=22'd0;
    endcase
endfunction

function [19:0] step8( input [4:0] n );    // (8<<16)/n
    case( n )
         1: step8=20'd524288;  2: step8=20'd262144;  3: step8=20'd174762;  4: step8=20'd131072;
         5: step8=20'd104857;  6: step8=20'd87381;   7: step8=20'd74898;   8: step8=20'd65536;
         9: step8=20'd58254;  10: step8=20'd52428;  11: step8=20'd47662;  12: step8=20'd43690;
        13: step8=20'd40329;  14: step8=20'd37449;  15: step8=20'd34952;  16: step8=20'd32768;
        default: step8=20'd0;
    endcase
endfunction

always @* begin
    ynext = yacc + {3'd0, zoomy};
    xnext = xacc + {2'd0, zoomx};
    curx  = { xsig[9], xsig } + { 3'd0, xacc[9:2] };
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st <= IDLE; map_cs <= 0; rom_cs <= 0; rom2_cs <= 0; d_busy <= 0; v1 <= 0; v2 <= 0; map_vld <= 0;
    end else begin
        // pipeline of the scan: address at E, data at E+2, registered at E+2, tested at E+3
        if( st==SCAN ) begin
            oaddr <= { sidx, 2'd0 };
            tag1  <= sidx;
            v1    <= !sdone;
            if( sidx==0 ) sdone <= 1;
            if( !sdone ) sidx <= sidx - 1'd1;
            w0r   <= odata;
            tag2  <= tag1;
            v2    <= v1;
        end
        // drawer
        if( d_busy ) begin
            wx    <= wx + 2'd2;
            icnt  <= icnt + 2'd2;
            sxacc <= d_flipx ? sxnx - {4'd0,d_stepx} : sxnx + {4'd0,d_stepx};
            if( icnt+2'd2 >= d_zx ) d_busy <= 0;
        end
        if( start ) begin
            sidx  <= 8'd191;
            sdone <= 0;
            v1 <= 0; v2 <= 0;
            st  <= SCAN;
            map_cs <= 0;
            rom_cs <= 0;
            rom2_cs <= 0;
            d_busy <= 0;
            map_vld <= 0;
        end else case( st )
            IDLE:;
            SCAN: begin
                if( hit0 ) begin
                    hidx  <= tag2;
                    oaddr <= { tag2, 2'd1 };
                    zoomy <= zy0;
                    dy    <= dy0;
                    v1 <= 0; v2 <= 0;
                    st <= H1;
                end else if( sdone && !v1 && !v2 ) st <= IDLE;
            end
            H1: begin oaddr <= { hidx, 2'd2 }; st <= H2; end
            H2: begin oaddr <= { hidx, 2'd3 }; w1 <= odata; st <= H3; end
            H3: begin w2 <= odata; st <= H4; end
            H4: begin
                tilenum <= odata[12:0];
                flipy   <= odata[15];
                yacc    <= 0;
                jrow    <= 0;
                if( odata[12:0]==0 ) begin
                    // back to the scan after this entry
                    sidx  <= hidx - 1'd1;
                    sdone <= hidx==0;
                    st    <= SCAN;
                end else st <= FINDJ;
            end
            FINDJ: begin
                // chunk row j covers [ (j*zoomy)>>3, ((j+1)*zoomy)>>3 )
                if( dy < {3'd0, ynext[10:3]} || jrow==7 ) begin
                    zy    <= ynext[7:3] - yacc[7:3];
                    ry    <= dy[4:0] - yacc[7:3];
                    hs    <= 0;
                    st    <= CHK;
                end else begin
                    yacc <= ynext;
                    jrow <= jrow + 1'd1;
                end
            end
            CHK: begin  // a few clocks to work out the tile row
                hs <= hs + 1'd1;
                case( hs )
                    0: begin
                        flipx  <= w1[14];
                        oprio  <= w1[15];
                        xsig   <= {1'b0, w1[8:0]} - (w1[8:0] > 9'h140 ? 10'h200 : 10'd0);
                        ocol   <= w2[15:8];
                        zoomx  <= { 1'b0, w2[6:0] } + 8'd1;
                        xacc   <= 0;
                        kc     <= 0;
                        if( flipy ) begin
                            jrow <= ~jrow;
                            ry   <= zy - 5'd1 - ry;
                        end
                    end
                    1: syacc <= ry * step8(zy);
                    default: begin
                        srow <= syacc[18:16];
                        st   <= CHUNK;
                    end
                endcase
            end
            CHUNK: begin
                zx    <= cz;
                stepx <= step16( cz );
                if( cz==0 || !curx[10] && curx>=11'd320 || xend[11] || xend==0 ) st <= NEXT;
                else if( map_vld && map_tag==mtag ) st <= T0W0;
                else begin
                    map_addr <= mtag;
                    map_tag  <= mtag;
                    map_vld  <= 0;
                    map_cs   <= 1;
                    hs       <= 0;
                    st <= MAPW;
                end
            end
            MAPW: begin
                hs <= 1;
                if( map_ok && hs==1 ) begin
                    map_cs  <= 0;
                    map_q   <= map_data;
                    map_vld <= 1;
                    st <= T0W0;
                end
            end
            T0W0: begin
                rom_addr  <= { mcode, srow };
                rom2_addr <= { mcode, srow };
                rom_cs    <= 1;
                rom2_cs   <= 1;
                got       <= 0;
                st <= T0W;
                hs <= 0;
            end
            T0W: begin
                hs <= 1;
                if( hs==1 ) begin
                    if( rom_ok  && !got[0] ) begin { f1, f0 } <= rom_data;  got[0] <= 1; rom_cs  <= 0; end
                    if( rom2_ok && !got[1] ) begin { f3, f2 } <= rom2_data; got[1] <= 1; rom2_cs <= 0; end
                    if( got==3 ) st <= HAND;
                end
            end
            HAND: if( !d_busy ) begin
                { pl3, pl2, pl1, pl0 } <= { f3, f2, f1, f0 };
                wx      <= curx[8:0];
                d_zx    <= zx;
                d_stepx <= stepx;
                d_flipx <= flipx;
                d_col   <= ocol;
                d_prio  <= oprio;
                icnt    <= 0;
                sxacc   <= flipx ? ({20'd0,zx}-26'd1)*stepx : 26'd0;
                d_busy  <= 1;
                st      <= NEXT;
            end
            NEXT: begin
                // next chunk of this sprite, or back to the scan
                if( kc!=3 ) begin
                    kc   <= kc + 1'd1;
                    xacc <= xnext;
                    st   <= CHUNK;
                end else begin
                    sidx  <= hidx - 1'd1;
                    sdone <= hidx==0;
                    st    <= SCAN;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

// line buffer read out, cleared behind the read
always @(posedge clk) begin
    ecnt <= pxl_cen ? 3'd0 : (ecnt==7 ? ecnt : ecnt + 1'd1);
    if( ecnt==2 ) pxl <= q1;
end

jtframe_dual_ram16 #(.AW(10)) u_ram(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( cpu_addr ),
    .we0    ( {2{obj_cs & ~cpu_rnw}} & ~cpu_dsn ), .q0 ( cpu_din ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( oaddr    ), .we1 ( 2'b0 ), .q1 ( odata )
);

jtframe_dual_ram #(.DW(13),.AW(9)) u_even(
    .clk0   ( clk                    ),
    .data0  ( { d_prio, d_col, pen_e } ),
    .addr0  ( { wr_bank, ax_e }      ),
    .we0    ( we_e                   ),
    .q0     (                        ),
    .clk1   ( clk                    ),
    .data1  ( 13'd0                  ),
    .addr1  ( { rd_bank, rd_x[8:1] } ),
    .we1    ( erase & ~rd_x[0]       ),
    .q1     ( q_e                    )
);

jtframe_dual_ram #(.DW(13),.AW(9)) u_odd(
    .clk0   ( clk                    ),
    .data0  ( { d_prio, d_col, pen_o } ),
    .addr0  ( { wr_bank, ax_o }      ),
    .we0    ( we_o                   ),
    .q0     (                        ),
    .clk1   ( clk                    ),
    .data1  ( 13'd0                  ),
    .addr1  ( { rd_bank, rd_x[8:1] } ),
    .we1    ( erase &  rd_x[0]       ),
    .q1     ( q_o                    )
);

endmodule
