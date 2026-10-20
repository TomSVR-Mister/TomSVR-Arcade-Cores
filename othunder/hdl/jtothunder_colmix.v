/* SPDX-License-Identifier: GPL-3.0-or-later
   Operation Thunderbolt colour mixer and TC0110PCR palette (4096 xRGB_555 entries), after MAME
   othunder_v.cpp screen_update: bottom BG layer opaque, the other BG layer, sprites, then text.
   Sprites with the priority bit set go behind the upper BG layer. */

module jtothunder_colmix(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             lhbl,
    input             lvbl,

    // TC0110PCR
    input      [ 2:1] cpu_addr,
    input      [15:0] cpu_dout,
    input             cpu_rnw,
    input             pcr_cs,
    output     [15:0] cpu_din,

    input      [ 3:0] layer_ctl,
    input      [11:0] bg0, bg1, txt,
    input      [12:0] obj,
    input      [ 3:0] gfx_en,

    output reg [ 4:0] red,
    output reg [ 4:0] green,
    output reg [ 4:0] blue
);

reg  [11:0] pcr_addr, idx;
reg         we_l;
wire [15:0] pal_q, ram_q;
wire        bot_bg1 = layer_ctl[3];
wire [11:0] bot = bot_bg1 ? bg1 : bg0;
wire [11:0] top = bot_bg1 ? bg0 : bg1;
wire        bot_en  = ~(bot_bg1 ? layer_ctl[1] : layer_ctl[0]) & (bot_bg1 ? gfx_en[1] : gfx_en[0]);
wire        top_op  = ~(bot_bg1 ? layer_ctl[0] : layer_ctl[1]) & (bot_bg1 ? gfx_en[0] : gfx_en[1]) & top[3:0]!=0;
wire        txt_op  = ~layer_ctl[2] & gfx_en[2] & txt[3:0]!=0;
wire        obj_op  = gfx_en[3] & obj[3:0]!=0;
wire        pal_we  = pcr_cs && !cpu_rnw && cpu_addr==1;

assign cpu_din = cpu_addr==1 ? ram_q : 16'hff;

always @(posedge clk, posedge rst) begin
    if( rst ) pcr_addr <= 0;
    else if( pcr_cs && !cpu_rnw && cpu_addr==0 ) pcr_addr <= cpu_dout[11:0];
end

always @(posedge clk) if( pxl_cen ) begin
    idx <= txt_op                      ? txt :
           obj_op && (!obj[12]|!top_op) ? obj[11:0] :
           top_op                      ? top :
           bot_en                      ? bot : 12'd0;
    red   <= (lhbl & lvbl) ? pal_q[14:10] : 5'd0;
    green <= (lhbl & lvbl) ? pal_q[ 9: 5] : 5'd0;
    blue  <= (lhbl & lvbl) ? pal_q[ 4: 0] : 5'd0;
end

jtframe_dual_ram16 #(.AW(12)) u_pal(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( pcr_addr ), .we0 ( {2{pal_we}} ), .q0 ( ram_q ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( idx      ), .we1 ( 2'b0 ),       .q1 ( pal_q )
);

endmodule
