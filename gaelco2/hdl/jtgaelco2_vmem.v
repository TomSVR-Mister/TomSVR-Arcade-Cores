/*  This file is part of JTGAELCO2.
    SPDX-License-Identifier: GPL-3.0-or-later
    Video RAM (32k words) and palette (4k words) on JTFRAME dual-port RAMs.
    The video side needs four independent read ports into VRAM (the two tilemap fetchers read
    32-bit even/odd word pairs, the line/row scroll reader, and the sprite engine at 96 MHz), so
    VRAM is kept in four copies, all written by the CPU. Read ports match the one-clock latency
    the jlrh GAE1 video modules expect. */

module jtgaelco2_vmem(
    input              clk,
    input              clk96,
    // CPU
    input      [15:1]  cpu_addr,
    input      [ 1:0]  cpu_dsn,     // active high {upper, lower}
    input              cpu_we,
    input      [15:0]  cpu_dout,
    input              vram_cs,
    input              pal_cs,
    output     [15:0]  vram_dout,
    output     [15:0]  pal_dout,
    // video
    input      [13:0]  tp0_idx,
    output     [31:0]  tp0_q,
    input      [13:0]  tp1_idx,
    output     [31:0]  tp1_q,
    input      [14:0]  wrd_a,
    output     [15:0]  wrd_q,
    input      [14:0]  spr_a,        // clk96
    output     [15:0]  spr_q,
    input      [11:0]  pal_a,
    output     [15:0]  pal_q
);

wire [ 1:0] vwe  = (vram_cs & cpu_we) ? cpu_dsn : 2'b00;
wire [ 1:0] vwe_e = cpu_addr[1] ? 2'b00 : vwe;   // even word of a pair
wire [ 1:0] vwe_o = cpu_addr[1] ? vwe : 2'b00;   // odd word of a pair
wire [ 1:0] pwe  = (pal_cs & cpu_we) ? cpu_dsn : 2'b00;
wire [15:0] t0e, t0o, t1e, t1o, se, so;
reg         spar;

assign tp0_q = { t0e, t0o };
assign tp1_q = { t1e, t1o };
assign spr_q = spar ? so : se;
always @(posedge clk96) spar <= spr_a[0];

// CPU port and the scroll-word reader
jtframe_dual_ram16 #(.AW(15)) u_vcpu(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr ), .we0( vwe ), .q0( vram_dout ),
    .clk1( clk ), .data1( 16'd0 ),    .addr1( wrd_a    ), .we1( 2'b0 ), .q1( wrd_q )
);

// tilemap 0 fetcher: even and odd words of each pair
jtframe_dual_ram16 #(.AW(14)) u_t0e(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[15:2] ), .we0( vwe_e ), .q0( ),
    .clk1( clk ), .data1( 16'd0 ),    .addr1( tp0_idx ),        .we1( 2'b0 ),  .q1( t0e )
);
jtframe_dual_ram16 #(.AW(14)) u_t0o(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[15:2] ), .we0( vwe_o ), .q0( ),
    .clk1( clk ), .data1( 16'd0 ),    .addr1( tp0_idx ),        .we1( 2'b0 ),  .q1( t0o )
);

// tilemap 1 fetcher
jtframe_dual_ram16 #(.AW(14)) u_t1e(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[15:2] ), .we0( vwe_e ), .q0( ),
    .clk1( clk ), .data1( 16'd0 ),    .addr1( tp1_idx ),        .we1( 2'b0 ),  .q1( t1e )
);
jtframe_dual_ram16 #(.AW(14)) u_t1o(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[15:2] ), .we0( vwe_o ), .q0( ),
    .clk1( clk ), .data1( 16'd0 ),    .addr1( tp1_idx ),        .we1( 2'b0 ),  .q1( t1o )
);

// sprite engine (96 MHz side)
jtframe_dual_ram16 #(.AW(14)) u_se(
    .clk0( clk   ), .data0( cpu_dout ), .addr0( cpu_addr[15:2] ), .we0( vwe_e ), .q0( ),
    .clk1( clk96 ), .data1( 16'd0 ),    .addr1( spr_a[14:1] ),     .we1( 2'b0 ),  .q1( se )
);
jtframe_dual_ram16 #(.AW(14)) u_so(
    .clk0( clk   ), .data0( cpu_dout ), .addr0( cpu_addr[15:2] ), .we0( vwe_o ), .q0( ),
    .clk1( clk96 ), .data1( 16'd0 ),    .addr1( spr_a[14:1] ),     .we1( 2'b0 ),  .q1( so )
);

// palette
jtframe_dual_ram16 #(.AW(12)) u_pal(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[12:1] ), .we0( pwe ),  .q0( pal_dout ),
    .clk1( clk ), .data1( 16'd0 ),    .addr1( pal_a ),          .we1( 2'b0 ), .q1( pal_q )
);

endmodule
