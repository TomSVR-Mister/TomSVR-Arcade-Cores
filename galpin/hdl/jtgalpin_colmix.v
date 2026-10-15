/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gals Pinball colour mixer (MAME galspnbl.cpp):
 *   back to front: 15-bit RGB bitmap, sprites with priority 0, fg tilemap, sprites with priority 1
 *   palette: 1024 x xBGR_444; sprites use 0-255, tiles 512-767 */

module jtgalpin_colmix(
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [15:0] bg_data,
    input       [ 7:0] fg_pxl,
    input       [ 8:0] obj_pxl,
    output reg  [10:1] pal_addr,
    input       [15:0] pal_data,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

wire obj_op = gfx_en[3] && obj_pxl[3:0]!=0;
wire fg_op  = gfx_en[0] && fg_pxl[3:0]!=0;
wire sel_obj= obj_op && (obj_pxl[8] || !fg_op);
reg  use_pal;
reg  [14:0] bg_rgb;     // {G,R,B} as stored, 5 bits each

always @(posedge clk) if( pxl_cen ) begin
    pal_addr <= sel_obj ? { 2'b00, obj_pxl[7:0] } : { 2'b10, fg_pxl };
    use_pal  <= sel_obj || fg_op;
    bg_rgb   <= gfx_en[1] ? bg_data[15:1] : 15'd0;
    if( use_pal ) begin
        red   <= { pal_data[ 3:0], pal_data[ 3] };
        green <= { pal_data[ 7:4], pal_data[ 7] };
        blue  <= { pal_data[11:8], pal_data[11] };
    end else begin
        red   <= bg_rgb[ 9: 5];
        green <= bg_rgb[14:10];
        blue  <= bg_rgb[ 4: 0];
    end
end

endmodule
