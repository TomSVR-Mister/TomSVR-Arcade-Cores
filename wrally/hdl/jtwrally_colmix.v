/*  This file is part of JTWRALLY.
    SPDX-License-Identifier: GPL-3.0-or-later
    Layer order from MAME wrally_state::screen_update:
    L1 opaque, L0 cat 0, L1 cat 1, L0 cat 1 pens 1-7, sprites (low), L0 cat 1 pens 8-15, sprites (high).
    Tile pixels are {category, colour[4:0], pen[3:0]}; palette index colour*16+pen.
    Sprite pixels: [12:10] shadow level, [9] shadow, [8] high priority, [7:0] colour*16+pen. */

module jtwrally_colmix(
    input             clk,
    input             pxl_cen,
    input      [ 3:0] gfx_en,
    input      [ 9:0] scr0, scr1,
    input      [12:0] obj,
    output reg [12:0] pal_addr,
    input      [15:0] pal_dout,
    output reg [ 3:0] red, green, blue
);

function [12:0] mix_obj(input [12:0] c, input [12:0] o);
    if( !o[9] )          mix_obj = { 3'd0, 2'b10, o[7:0] };
    else if( o[7:0]!=0 ) mix_obj = { o[12:10], 2'b10, o[7:0] };
    else                 mix_obj = { o[12:10], c[9:0] };
endfunction

reg [12:0] c;
wire       l0_on  = gfx_en[0] && scr0[3:0]!=0;
wire       l1_on  = gfx_en[1] && scr1[3:0]!=0;
wire       obj_on = gfx_en[3] && obj!=0;

always @* begin
    c = gfx_en[1] ? { 4'd0, scr1[8:0] } : 13'd0;
    if( l0_on && !scr0[9] ) c = { 4'd0, scr0[8:0] };
    if( l1_on &&  scr1[9] ) c = { 4'd0, scr1[8:0] };
    if( l0_on &&  scr0[9] && !scr0[3] ) c = { 4'd0, scr0[8:0] };
    if( obj_on && !obj[8] ) c = mix_obj( c, obj );
    if( l0_on &&  scr0[9] &&  scr0[3] ) c = { 4'd0, scr0[8:0] };
    if( obj_on &&  obj[8] ) c = mix_obj( c, obj );
end

always @(posedge clk) if( pxl_cen ) begin
    pal_addr <= c;
    // xBRG_444
    { blue, red, green } <= pal_dout[11:0];
end

endmodule
