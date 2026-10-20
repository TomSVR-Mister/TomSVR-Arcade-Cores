/*  This file is part of JTXEXEX.
    SPDX-License-Identifier: GPL-3.0-or-later
    Xexex colour mixing, following MAME's xexex.cpp screen_update with the K053251 priorities
    and the K054338 background colour, shadows and alpha level.

    Bottom to top: K054338 background colour; tile layers B, C, D and the K053250 (LVC) sorted by
    their K053251 priorities (a larger value is further back); sprites, which hide behind any opaque
    layer whose priority is smaller than the sprite's; layer B pixels with the alpha flag, blended
    when control bit 9 is clear; layer A on top.
    Palette: 2048 x xRGB_888, two words per colour. */

module jtxexex_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,

    // CPU interface
    input      [12:1] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input             cpu_we,
    input             pal_cs,     // 1B0000-1B1FFF
    input             k251_cs,    // 0CC000-0CC01F, low byte
    input             k338_cs,    // 0CA000-0CA01F
    output     [15:0] pal_dout,
    input             alpha_off,  // control2 bit 9

    // colour bases for the tile layers
    output     [ 6:0] cb_b, cb_c, cb_d,

    // pixels
    input      [11:0] lyra, lyrb, lyrc, lyrd,
    input      [ 8:0] lvc,
    input      [ 8:0] obj,       // { colour[4:0], pen }
    input      [ 4:0] obj_pri,
    input      [ 1:0] obj_shd,

    input      [ 7:0] gfx_en,    // 4 lvc, 5 sprites
    output reg [ 7:0] red, green, blue
);

reg  [ 5:0] k251[0:15];
reg  [15:0] k338[0:15];
wire [ 7:0] pal_r;
wire [15:0] pal_gb;
reg  [10:0] pal_addr;
wire        pal_we_r, pal_we_gb;
wire [ 7:0] cpu_r;
wire [15:0] cpu_gb;

always @(posedge clk, posedge rst) begin
    if( rst ) begin : clr
        integer k;
        for( k=0; k<16; k=k+1 ) begin k251[k] <= 0; k338[k] <= 0; end
    end else begin
        if( k251_cs && cpu_we && !cpu_dsn[0] ) k251[cpu_addr[4:1]] <= cpu_dout[5:0];
        if( k338_cs && cpu_we ) begin
            if( !cpu_dsn[1] ) k338[cpu_addr[4:1]][15:8] <= cpu_dout[15:8];
            if( !cpu_dsn[0] ) k338[cpu_addr[4:1]][ 7:0] <= cpu_dout[ 7:0];
        end
    end
end

// K053251 colour bases: register 9 gives CI0-CI2 in steps of 32 palettes, register 10 CI3-CI4 in steps of 16
wire [1:0] ci0 = k251[9][1:0], ci1 = k251[9][3:2], ci2 = k251[9][5:4];
assign cb_b = { ci2, 5'd0 };
assign cb_c = { k251[10][2:0], 4'd0 };
assign cb_d = { k251[10][5:3], 4'd0 };

// palette: even words hold red, odd words green and blue
assign pal_we_r  = pal_cs && cpu_we && !cpu_addr[1] && !cpu_dsn[0];
assign pal_we_gb = pal_cs && cpu_we &&  cpu_addr[1];
assign pal_dout  = cpu_addr[1] ? cpu_gb : { 8'd0, cpu_r };

jtframe_dual_ram #(.DW(8),.AW(11)) u_palr(
    .clk0   ( clk            ),
    .data0  ( cpu_dout[7:0]  ),
    .addr0  ( cpu_addr[12:2] ),
    .we0    ( pal_we_r       ),
    .q0     ( cpu_r          ),
    .clk1   ( clk            ),
    .data1  ( 8'd0           ),
    .addr1  ( pal_addr       ),
    .we1    ( 1'b0           ),
    .q1     ( pal_r          )
);

jtframe_dual_ram16 #(.AW(11)) u_palgb(
    .clk0   ( clk            ),
    .data0  ( cpu_dout       ),
    .addr0  ( cpu_addr[12:2] ),
    .we0    ( ~cpu_dsn & {2{pal_we_gb}} ),
    .q0     ( cpu_gb         ),
    .clk1   ( clk            ),
    .data1  ( 16'd0          ),
    .addr1  ( pal_addr       ),
    .we1    ( 2'b0           ),
    .q1     ( pal_gb         )
);

// ---------- priority resolution, one pixel per pxl_cen
wire [5:0] pri_b = k251[2], pri_c = k251[3], pri_d = k251[4], pri_lvc = k251[1];
wire       alpha_on = !alpha_off;
wire       op_b   = lyrb[3:0]!=0 && !(alpha_on && lyrb[11]);
wire       op_c   = lyrc[3:0]!=0;
wire       op_d   = lyrd[3:0]!=0;
wire       op_lvc = lvc[3:0]!=0 && gfx_en[4];
wire       op_obj = obj[3:0]!=0 && gfx_en[5];
wire       shd    = obj_shd!=0 && gfx_en[5];
wire [5:0] spr_pri = { obj_pri, 1'b0 };

reg [10:0] top_idx;
reg [ 5:0] top_pri;
reg        top_op;

// later entries in B, C, D, LVC order win ties
always @* begin
    top_op  = 0;
    top_pri = 6'h3f;
    top_idx = 0;
    if( op_b ) begin top_op=1; top_pri=pri_b; top_idx=lyrb[10:0]; end
    if( op_c   && (!top_op || pri_c   <= top_pri) ) begin top_op=1; top_pri=pri_c;   top_idx=lyrc[10:0]; end
    if( op_d   && (!top_op || pri_d   <= top_pri) ) begin top_op=1; top_pri=pri_d;   top_idx=lyrd[10:0]; end
    if( op_lvc && (!top_op || pri_lvc <= top_pri) ) begin top_op=1; top_pri=pri_lvc; top_idx={ci1,lvc}; end
end

wire spr_vis = !top_op || spr_pri <= top_pri;

// stage 1: register the decision
reg  [10:0] idx0, idx1, idx2;     // base colour, layer B alpha, layer A
reg         bg0, shd0, blend0, a0;
reg  [ 1:0] shdsel0;

always @(posedge clk) if( pxl_cen ) begin
    bg0     <= 0;
    idx0    <= top_idx;
    shd0    <= 0;
    if( op_obj && spr_vis ) idx0 <= { ci0, obj };
    else begin
        if( !top_op ) bg0 <= 1;
        shd0 <= shd && spr_vis;
    end
    shdsel0 <= obj_shd;
    idx1    <= lyrb[10:0];
    blend0  <= alpha_on && lyrb[11] && lyrb[3:0]!=0;
    idx2    <= lyra[10:0];
    a0      <= lyra[3:0]!=0;
end

// stage 2: three palette reads in the clocks after pxl_cen
reg [2:0] ph;
reg [23:0] c0, c1, c2;
always @(posedge clk) begin
    ph <= pxl_cen ? 3'd1 : (ph!=0 ? ph+3'd1 : 3'd0);
    case( ph )
        1: pal_addr <= idx0;
        2: pal_addr <= idx1;
        3: begin pal_addr <= idx2; c0 <= { pal_r, pal_gb }; end
        4: c1 <= { pal_r, pal_gb };
        5: c2 <= { pal_r, pal_gb };
        default:;
    endcase
end

// stage 3: combine at the next pxl_cen, before stage 1 moves on
wire [ 7:0] alpha_set = k338[13][7:0];      // pblend 1: low byte of PBLEND
wire [ 4:0] mixlv = alpha_set[4:0];
wire [ 7:0] alpha = alpha_set[5] ? ((mixlv!=0 && mixlv!=5'h1f) ? 8'h84 : {mixlv,mixlv[4:2]})
                                 : { mixlv, mixlv[4:2] };

function [7:0] shade(input [7:0] c, input [8:0] d);
    reg signed [10:0] s;
    begin
        s = $signed({3'd0,c}) + $signed({{2{d[8]}},d});
        shade = s < 0 ? 8'd0 : s > 255 ? 8'd255 : s[7:0];
    end
endfunction

function [7:0] mix(input [7:0] s, input [7:0] d, input [7:0] a);
    reg [16:0] m;
    begin
        m = s*a + d*(9'd256-{1'b0,a});
        mix = m[15:8];
    end
endfunction

wire [3:0] shbase = shdsel0==2 ? 4'd5 : shdsel0==3 ? 4'd8 : 4'd2;
wire [23:0] bgc  = { k338[0][7:0], k338[1] };
wire [23:0] lowc = bg0 ? bgc : c0;
wire [23:0] shdc = shd0 ? { shade(lowc[23:16], k338[shbase][8:0]), shade(lowc[15:8], k338[shbase+4'd1][8:0]),
                            shade(lowc[7:0], k338[shbase+4'd2][8:0]) } : lowc;
wire [23:0] blc  = blend0 && alpha!=0 ? { mix(c1[23:16],shdc[23:16],alpha), mix(c1[15:8],shdc[15:8],alpha),
                                          mix(c1[7:0],shdc[7:0],alpha) } : shdc;
wire [23:0] fin  = a0 ? c2 : blc;

// the stage 1 values are still those of the pixel whose colours were just read
always @(posedge clk) if( pxl_cen ) { red, green, blue } <= fin;

endmodule
