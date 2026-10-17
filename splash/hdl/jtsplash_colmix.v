/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Splash! layer order (MAME screen_update), bottom to top: pixel layer (opaque, palette 0x300 + value),
 * tilemap 1 (palette colour*16 + pen), sprites (0x100 + colour*16 + pen), tilemap 0 (colour*16 + pen).
 * Palette: 2048 words xRGB_555.
 * Return of Lady Frog (rf): the pixel value goes through a bit swap and XOR chosen by the bitmap mode register (MAME draw_bitmap). */

module jtsplash_colmix(
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input              rf,
    input       [15:0] bmode,
    input       [ 7:0] tm0, tm1, obj, pix,
    output reg  [11:1] pal_addr,
    input       [15:0] pal_data,
    output reg  [ 4:0] red, green, blue
);

reg [9:0] idx;
reg [7:0] c, pv;

function [7:0] bsw( input [7:0] x, input [23:0] o );   // MAME bitswap<8>(x, 7, o[23:21], ... o[2:0])
    bsw = { x[7], x[o[20:18]], x[o[17:15]], x[o[14:12]], x[o[11:9]], x[o[8:6]], x[o[5:3]], x[o[2:0]] };
endfunction

always @* begin
    c  = pix;
    pv = pix;
    if( rf && bmode[15:11]==0 && bmode[7:0]==0 ) begin
        case( bmode[10:8] )
            3'd0: pv = c ^ 8'h7f;
            3'd1: pv = bsw( c, {3'd7, 3'd0, 3'd1, 3'd2, 3'd3, 3'd4, 3'd5, 3'd6} );
            3'd2: pv = c ^ 8'h55;
            3'd3: pv = bsw( c, {3'd7, 3'd4, 3'd6, 3'd5, 3'd1, 3'd0, 3'd3, 3'd2} ) ^ 8'h7f;
            3'd4: pv = bsw( c, {3'd7, 3'd3, 3'd2, 3'd1, 3'd0, 3'd6, 3'd5, 3'd4} );
            3'd5: pv = bsw( c, {3'd7, 3'd6, 3'd4, 3'd2, 3'd0, 3'd5, 3'd3, 3'd1} );
            3'd6: pv = bsw( c, {3'd7, 3'd0, 3'd6, 3'd5, 3'd4, 3'd3, 3'd2, 3'd1} ) ^ 8'h7f;
            3'd7: pv = bsw( c, {3'd7, 3'd4, 3'd3, 3'd2, 3'd1, 3'd0, 3'd6, 3'd5} ) ^ 8'h55;
        endcase
    end
end

always @* begin
    idx = gfx_en[0] ? { 2'b11, pv } : 10'd0;
    if( gfx_en[1] && tm1[3:0]!=0 ) idx = { 2'b00, tm1 };
    if( gfx_en[3] && obj[3:0]!=0 ) idx = { 2'b01, obj };
    if( gfx_en[2] && tm0[3:0]!=0 ) idx = { 2'b00, tm0 };
end

always @(posedge clk) if( pxl_cen ) begin
    pal_addr <= { 1'b0, idx };
    red      <= pal_data[14:10];
    green    <= pal_data[ 9: 5];
    blue     <= pal_data[ 4: 0];
end

endmodule
