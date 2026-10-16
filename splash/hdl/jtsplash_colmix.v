/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Splash! layer order (MAME screen_update), bottom to top: pixel layer (opaque, palette 0x300 + value),
 * tilemap 1 (palette colour*16 + pen), sprites (0x100 + colour*16 + pen), tilemap 0 (colour*16 + pen).
 * Palette: 2048 words xRGB_555. */

module jtsplash_colmix(
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 7:0] tm0, tm1, obj, pix,
    output reg  [11:1] pal_addr,
    input       [15:0] pal_data,
    output reg  [ 4:0] red, green, blue
);

reg [9:0] idx;

always @* begin
    idx = gfx_en[0] ? { 2'b11, pix } : 10'd0;
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
