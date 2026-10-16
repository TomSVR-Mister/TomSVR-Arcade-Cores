/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 16 priorities (MAME yunsun16.cpp screen_update / draw_sprites):
 *   prio[3:2]==1: layer 0 at the back (drawn opaque, pen ff included), layer 1 in front
 *   prio[3:2]==2: layer 1 at the back, layer 0 in front
 *   prio[1:0]: 1 = sprites behind both layers, 2 = between them, 0/3 = on top
 *   palette 8192 x xRGB_555: sprites 0-511, tiles 0x1000 + colour*256 + pen */

module jtys16_colmix(
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [15:0] prio,
    input       [11:0] scr0,
    input       [11:0] scr1,
    input       [ 8:0] obj,
    output reg  [13:1] pal_addr,
    input       [15:0] pal_data,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

wire [11:0] bot = prio[3:2]==2 ? scr1 : scr0;
wire [11:0] top = prio[3:2]==2 ? scr0 : scr1;
wire        en_bot = prio[3:2]==2 ? gfx_en[1] : gfx_en[0];
wire        en_top = prio[3:2]==2 ? gfx_en[0] : gfx_en[1];
wire        layers = prio[3:2]==1 || prio[3:2]==2;
wire        bot_op = en_bot && bot[7:0]!=8'hff;
wire        top_op = en_top && top[7:0]!=8'hff;
wire [ 1:0] pmap   = top_op ? 2'd2 : bot_op ? 2'd1 : 2'd0;
wire        obj_op = gfx_en[3] && obj[3:0]!=4'hf;
reg         obj_vis, blank;

always @* begin
    case( prio[1:0] )
        1: obj_vis = obj_op && pmap==0;
        2: obj_vis = obj_op && pmap!=2;
        default: obj_vis = obj_op;
    endcase
end

always @(posedge clk) if( pxl_cen ) begin
    blank    <= !obj_vis && !(layers && en_bot);
    pal_addr <= obj_vis ? { 4'd0, obj } : { 1'b1, top_op ? top : bot };
    red      <= blank ? 5'd0 : pal_data[14:10];
    green    <= blank ? 5'd0 : pal_data[ 9: 5];
    blue     <= blank ? 5'd0 : pal_data[ 4: 0];
end

endmodule
