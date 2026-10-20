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

    // 16x8 tiles, one 16-bit word per plane, 64-bit rows
    output reg [20:2] rom_addr,
    output reg        rom_cs,
    input             rom_ok,
    input      [31:0] rom_data,

    output reg [12:0] pxl         // {priority, colour, pen}
);

localparam [4:0] IDLE=0, RD0=1, RD1=2, RD2=3, RD3=4, RD4=5, RD5=6, CHK=7, FINDJ=8, CHUNK=9,
                 MAPW0=10, MAPW=11, T0W0=12, T0W=13, T1W0=14, T1W=15, DRAW=16, NEXT=17;

reg  [ 4:0] st;
reg  [ 7:0] idx;
reg  [ 9:0] oaddr;
wire [15:0] odata;
reg  [15:0] w0, w1, w2;
reg  [ 9:0] ysig, dy, xsig;
reg  [ 7:0] zoomy, zoomx;
reg  [10:0] yacc, ynext;
reg  [ 2:0] jrow, srow;
reg  [ 4:0] zy, ry;
reg  [ 1:0] kc;
reg  [ 9:0] xacc, xnext;
reg  [ 5:0] zx;
reg  [ 5:0] icnt;
reg  [12:0] tilenum;
reg  [14:0] code;
reg  [31:0] planes01;
reg  [15:0] pl0, pl1, pl2, pl3;
reg  [ 8:0] wx;
reg         flipx, flipy, oprio;
reg  [ 7:0] ocol;
reg  [25:0] sxacc;
reg  [21:0] stepx;
reg  [19:0] stepy;
reg  [24:0] syacc;
wire [ 3:0] sx = sxacc[19:16];
wire [ 3:0] pen = { pl0[~sx], pl1[~sx], pl2[~sx], pl3[~sx] };
wire        we = st==DRAW && pen!=0;
wire [12:0] q1;
reg  [ 2:0] ecnt;
wire        erase = ecnt==3;

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
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st <= IDLE; map_cs <= 0; rom_cs <= 0;
    end else begin
        if( start ) begin
            idx <= 8'd191;
            st  <= RD0;
            map_cs <= 0;
            rom_cs <= 0;
        end else case( st )
            IDLE:;
            RD0: begin oaddr <= { idx, 2'd0 }; st <= RD1; end
            RD1: begin oaddr <= { idx, 2'd1 }; st <= RD2; end
            RD2: begin   // word 0 available
                w0    <= odata;
                ysig  <= {1'b0, odata[8:0]} + 10'd3 - ((({1'b0,odata[8:0]} + 10'd3) > 10'h140) ? 10'h200 : 10'd0);
                zoomy <= { 1'b0, odata[15:9] } + 8'd1;
                oaddr <= { idx, 2'd2 };
                st    <= RD3;
            end
            RD3: begin
                w1    <= odata;
                dy    <= {1'b0, vrender} - ysig;
                oaddr <= { idx, 2'd3 };
                st    <= RD4;
            end
            RD4: begin
                w2 <= odata;
                st <= RD5;
            end
            RD5: begin
                tilenum <= odata[12:0];
                flipy   <= odata[15];
                // visible on this line?
                if( odata[12:0]==0 || dy[9] || dy >= {2'd0,zoomy} ) st <= NEXT;
                else begin
                    yacc <= 0;
                    jrow <= 0;
                    st   <= FINDJ;
                end
            end
            FINDJ: begin
                // chunk row j covers [ (j*zoomy)>>3, ((j+1)*zoomy)>>3 )
                if( dy < {2'd0, ynext[10:3]} || jrow==7 ) begin
                    zy    <= ynext[7:3] - yacc[7:3];
                    ry    <= dy[4:0] - yacc[7:3];
                    st    <= CHK;
                end else begin
                    yacc <= ynext;
                    jrow <= jrow + 1'd1;
                end
            end
            CHK: begin
                stepy  <= step8(zy);
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
                st <= CHUNK;
            end
            CHUNK: begin
                syacc <= ry * stepy;
                zx    <= xnext[7:2] - xacc[7:2];
                wx    <= xsig[8:0] + {1'd0, xacc[9:2]};
                // map entry for chunk column px, row py
                map_addr <= { tilenum, jrow, kc[1]^flipx };
                map_cs   <= 1;
                st <= MAPW0;
            end
            MAPW0: begin
                srow  <= syacc[18:16];
                stepx <= step16(zx);
                st <= zx==0 ? NEXT : MAPW;
                if( zx==0 ) map_cs <= 0;
            end
            MAPW: if( map_ok ) begin
                map_cs   <= 0;
                code     <= (kc[0]^flipx) ? map_data[30:16] : map_data[14:0];
                rom_addr <= { ((kc[0]^flipx) ? map_data[30:16] : map_data[14:0]), srow, 1'b0 };
                rom_cs   <= 1;
                st <= T0W0;
            end
            T0W0: st <= T0W;
            T0W: if( rom_ok ) begin
                { pl1, pl0 } <= rom_data;
                rom_addr[2] <= 1;
                st <= T1W0;
            end
            T1W0: st <= T1W;
            T1W: if( rom_ok ) begin
                rom_cs <= 0;
                { pl3, pl2 } <= rom_data;
                icnt  <= 0;
                sxacc <= flipx ? ({20'd0,zx}-26'd1)*stepx : 26'd0;
                st <= DRAW;
            end
            DRAW: begin
                wx    <= wx + 1'd1;
                icnt  <= icnt + 1'd1;
                sxacc <= flipx ? sxacc - stepx : sxacc + stepx;
                if( icnt+1'd1 == zx ) st <= NEXT;
            end
            NEXT: begin
                // next chunk of this sprite, or the next sprite
                if( kc!=3 && !(tilenum==0 || dy[9] || dy >= {2'd0,zoomy}) ) begin
                    kc   <= kc + 1'd1;
                    xacc <= xnext;
                    st   <= CHUNK;
                end else begin
                    idx <= idx - 1'd1;
                    st  <= idx==0 ? IDLE : RD0;
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

jtframe_dual_ram #(.DW(13),.AW(10)) u_buf(
    .clk0   ( clk                   ),
    .data0  ( { oprio, ocol, pen }  ),
    .addr0  ( { wr_bank, wx }       ),
    .we0    ( we                    ),
    .q0     (                       ),
    .clk1   ( clk                   ),
    .data1  ( 13'd0                 ),
    .addr1  ( { rd_bank, rd_x }     ),
    .we1    ( erase                 ),
    .q1     ( q1                    )
);

endmodule
