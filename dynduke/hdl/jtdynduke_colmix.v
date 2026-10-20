/* SPDX-License-Identifier: GPL-3.0-or-later
   Dynamite Duke layer mixing (MAME dynduke.cpp screen_update), bottom to top: background (opaque, black when
   disabled), foreground (pen 15 transparent), text (pen 15 transparent); sprites by priority:
   3 = under the text only, 2 = also under the foreground, 0/1 = also under background pixels with bit 5 set.
   Palette 2048 x xBGR_444: background 0x000 + { bit 4, colour, pen }, foreground 0x200, sprites 0x300, text 0x500. */

module jtdynduke_colmix(
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 7:0] ctrl,        // bit 0 background off, 1 foreground off, 2 text off, 3 sprites off
    input       [ 9:0] bg,          // { pri, extra, colour, pen }
    input       [ 9:0] fg,          // { 2'b0, colour, pen }
    input       [ 9:0] txt,
    input       [10:0] obj,         // { pri, colour, pen }
    output reg  [11:1] pal_addr,
    input       [15:0] pal_data,
    output reg  [ 3:0] red, green, blue
);

wire bg_on  = !ctrl[0] && gfx_en[0];
wire fg_op  = !ctrl[1] && gfx_en[1] && fg[3:0]!=4'hf;
wire txt_op = !ctrl[2] && gfx_en[2] && txt[3:0]!=4'hf;
wire obj_op = !ctrl[3] && gfx_en[3] && obj[3:0]!=4'hf;
wire bg_pri = bg_on && bg[9];
reg  [10:0] idx;
reg         black, black_l;
reg         obj_show;

always @* begin
    case( obj[10:9] )
        2'd3:    obj_show = obj_op;
        2'd2:    obj_show = obj_op && !fg_op;
        default: obj_show = obj_op && !fg_op && !bg_pri;
    endcase
    black = 0;
    if( txt_op )        idx = { 3'b101, txt[7:0] };
    else if( obj_show ) idx = { 2'b01, obj[8:0] } + 11'h100;    // 0x300 + { colour[4:0], pen }
    else if( fg_op )    idx = { 3'b010, fg[7:0] };
    else begin
        idx   = { 2'b00, bg[8:0] };
        black = !bg_on;
    end
end

always @(posedge clk) if( pxl_cen ) begin
    pal_addr <= idx;
    black_l  <= black;
    red      <= black_l ? 4'd0 : pal_data[ 3:0];
    green    <= black_l ? 4'd0 : pal_data[ 7:4];
    blue     <= black_l ? 4'd0 : pal_data[11:8];
end

endmodule
