/* SPDX-License-Identifier: GPL-3.0-or-later
   Dynamite Duke slave CPU (V30, 8 MHz), after MAME dynduke.cpp slave_map:
   00000-05fff RAM, 06000-067ff background map, 06800-06fff foreground map, 07000-07fff palette
   (2048 xBGR_444 entries), 08000-08fff RAM shared with the master, 0a000 tile banks, e0000-fffff ROM. */

module jtdynduke_sub(
    input             rst,
    input             clk,
    input             vint,

    output     [16:1] rom_addr,
    output            rom_cs,
    input      [15:0] rom_data,
    input             rom_ok,

    // shared RAM, held by the master module
    output     [11:1] sh_addr,
    output     [15:0] sh_dout,
    output     [ 1:0] sh_we,
    input      [15:0] sh_din,

    // video
    input      [10:1] bg_addr,
    output     [15:0] bg_data,
    input      [10:1] fg_addr,
    output     [15:0] fg_data,
    input      [11:1] pal_addr,
    output     [15:0] pal_data,
    output reg        bg_bank,
    output reg        fg_bank,

    input             dip_pause
);

wire [19:1] A;
wire [ 1:0] be;
wire [15:0] cpu_dout, ram_q, bg_q, fg_q, pal_q;
wire        mem_rd, mem_wr, int_ack, stall;
wire [19:0] ba = {A, 1'b0};
wire        mem_acc = mem_rd | mem_wr;
wire [ 1:0] we = {2{mem_wr}} & be;
reg  [15:0] cpu_din;
reg         ram_cs, bg_cs, fg_cs, pal_cs, sh_cs, bank_cs, int_req;

assign rom_cs   = mem_rd && ba[19:18]==2'b11;
assign rom_addr = A[16:1];          // only e0000-fffff holds ROM
assign stall    = (rom_cs & ~rom_ok) | ~dip_pause;
assign sh_addr  = A[11:1];
assign sh_dout  = cpu_dout;
assign sh_we    = sh_cs ? we : 2'b0;

always @* begin
    ram_cs  = mem_acc && ba[19:15]==0 && ba[14:13]!=2'b11;   // 00000-05fff
    bg_cs   = mem_acc && ba[19:11]==9'h00c;                   // 06000-067ff
    fg_cs   = mem_acc && ba[19:11]==9'h00d;                   // 06800-06fff
    pal_cs  = mem_acc && ba[19:12]==8'h07;
    sh_cs   = mem_acc && ba[19:12]==8'h08;
    bank_cs = mem_acc && ba[19:1]==19'h5000;                  // 0a000
    cpu_din = rom_cs ? rom_data :
              ram_cs ? ram_q    :
              bg_cs  ? bg_q     :
              fg_cs  ? fg_q     :
              pal_cs ? pal_q    :
              sh_cs  ? sh_din   : 16'hffff;
end

always @(posedge clk) begin
    if( rst ) begin
        bg_bank <= 0;
        fg_bank <= 0;
    end else if( mem_wr && bank_cs && be[0] ) begin
        bg_bank <= cpu_dout[0];
        fg_bank <= cpu_dout[4];
    end
end

always @(posedge clk) begin
    if( rst ) int_req <= 0;
    else if( vint ) int_req <= 1;
    else if( int_ack ) int_req <= 0;
end

jtframe_ram16 #(.AW(14)) u_ram(
    .clk    ( clk       ), .data ( cpu_dout ), .addr ( A[14:1] ), .we ( ram_cs ? we : 2'b0 ), .q ( ram_q )
);

jtframe_dual_ram16 #(.AW(10)) u_bg(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( A[10:1] ), .we0 ( bg_cs ? we : 2'b0 ), .q0 ( bg_q ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( bg_addr ), .we1 ( 2'b0 ),        .q1 ( bg_data )
);

jtframe_dual_ram16 #(.AW(10)) u_fg(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( A[10:1] ), .we0 ( fg_cs ? we : 2'b0 ), .q0 ( fg_q ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( fg_addr ), .we1 ( 2'b0 ),        .q1 ( fg_data )
);

jtframe_dual_ram16 #(.AW(11)) u_pal(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( A[11:1] ), .we0 ( pal_cs ? we : 2'b0 ), .q0 ( pal_q ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( pal_addr ), .we1 ( 2'b0 ),       .q1 ( pal_data )
);

jtdynduke_cpu u_cpu(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .stall      ( stall     ),
    .addr       ( A         ),
    .be         ( be        ),
    .dout       ( cpu_dout  ),
    .din        ( cpu_din   ),
    .mem_rd     ( mem_rd    ),
    .mem_wr     ( mem_wr    ),
    .io_rd      (           ),
    .io_wr      (           ),
    .int_req    ( int_req   ),
    .int_vector ( 8'h32     ),
    .int_ack    ( int_ack   )
);

endmodule
