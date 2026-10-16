/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Paradise layer order (MAME screen_update_paradise), bottom to top:
 *   [sprites if prio.0], bg (4bpp, pen 15 clear), mid (pen ff clear), pixel layer (0 clear),
 *   prio.1 ? ([sprites if !prio.0], fg) : (fg, [sprites if !prio.0]);  prio.2 = 0 blanks the screen
 * Torus (mode 1): blank if !prio.1; [sprites if prio.0], mid, prio.2 ? ([sprites if !prio.0], fg) : (fg, [sprites if !prio.0])
 * Mad Ball (mode 2): bg, mid, fg, sprites (sprites at palette 500 + pen)
 * Palette indexes: fg 000+pen, sprites 100+pen, pixel 200+bank*16+15-v, mid 300+pen, bg 400+bank*16+pen */

module jtpara_colmix(
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 7:0] prio,
    input       [ 1:0] mode,        // 0 Paradise, 1 Torus, 2 Mad Ball
    input       [ 3:0] bg_bank,
    input       [ 3:0] pix_bank,
    input       [ 7:0] bg, mid, fg, obj,
    input       [ 3:0] pix,
    output reg  [10:0] pal_addr,
    input       [ 7:0] palr, palg, palb,
    output reg  [ 7:0] red, green, blue
);

wire bg_op  = gfx_en[0] && bg[3:0] != 4'hf;
wire mid_op = gfx_en[1] && mid != 8'hff;
wire pix_op = gfx_en[1] && pix != 4'h0;
wire fg_op  = gfx_en[2] && fg  != 8'hff;
wire obj_op = gfx_en[3] && obj != 8'hff;
reg  [10:0] idx;
reg         opaque, show;

always @* begin
    idx = 0; opaque = 0;
    if( prio[0] && obj_op ) begin idx = { 3'b001, obj }; opaque = 1; end
    if( bg_op  ) begin idx = { 3'b100, bg_bank[2:0], 1'b1, bg[3:0] }; opaque = 1; end
    if( mid_op ) begin idx = { 3'b011, mid }; opaque = 1; end
    if( pix_op ) begin idx = { 3'b010, pix_bank, ~pix }; opaque = 1; end
    if( prio[1] ) begin
        if( !prio[0] && obj_op ) begin idx = { 3'b001, obj }; opaque = 1; end
        if( fg_op ) begin idx = { 3'b000, fg }; opaque = 1; end
    end else begin
        if( fg_op ) begin idx = { 3'b000, fg }; opaque = 1; end
        if( !prio[0] && obj_op ) begin idx = { 3'b001, obj }; opaque = 1; end
    end
    if( !prio[2] ) opaque = 0;
    if( mode==1 ) begin
        idx = 0; opaque = 0;
        if( prio[0] && obj_op ) begin idx = { 3'b001, obj }; opaque = 1; end
        if( mid_op ) begin idx = { 3'b011, mid }; opaque = 1; end
        if( prio[2] ) begin
            if( !prio[0] && obj_op ) begin idx = { 3'b001, obj }; opaque = 1; end
            if( fg_op ) begin idx = { 3'b000, fg }; opaque = 1; end
        end else begin
            if( fg_op ) begin idx = { 3'b000, fg }; opaque = 1; end
            if( !prio[0] && obj_op ) begin idx = { 3'b001, obj }; opaque = 1; end
        end
        if( !prio[1] ) opaque = 0;
    end
    if( mode==2 ) begin
        idx = 0; opaque = 0;
        if( bg_op  ) begin idx = { 3'b100, bg_bank[2:0], 1'b1, bg[3:0] }; opaque = 1; end
        if( mid_op ) begin idx = { 3'b011, mid }; opaque = 1; end
        if( fg_op  ) begin idx = { 3'b000, fg }; opaque = 1; end
        if( obj_op ) begin idx = { 3'b101, obj }; opaque = 1; end
    end
end

always @(posedge clk) if( pxl_cen ) begin
    pal_addr <= idx;
    show     <= opaque;
    red      <= show ? palr : 8'd0;
    green    <= show ? palg : 8'd0;
    blue     <= show ? palb : 8'd0;
end

endmodule
