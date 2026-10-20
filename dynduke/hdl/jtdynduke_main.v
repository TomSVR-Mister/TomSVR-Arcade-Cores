/* SPDX-License-Identifier: GPL-3.0-or-later
   Dynamite Duke master CPU (V30, 8 MHz), after MAME dynduke.cpp master_map:
   00000-06fff RAM, 07000-07fff sprite RAM, 08000-080ff scroll, 0a000-0afff RAM shared with the slave,
   0b000 inputs, 0b002 DIP switches, 0b006 video control, 0c000-0c7ff text RAM, 0d000 Seibu sound port,
   a0000-fffff ROM. The Double Dynamites (Japan) moves the I/O (masterj_map). */

module jtdynduke_main(
    input             rst,
    input             clk,
    input             dbldynj,
    input             vint,        // V-blank interrupt request

    output     [18:1] rom_addr,
    output            rom_cs,
    input      [15:0] rom_data,
    input             rom_ok,

    // shared RAM, slave side
    input      [11:1] sh_addr,
    input      [15:0] sh_din,
    input      [ 1:0] sh_we,
    output     [15:0] sh_dout,

    // sound
    output     [ 2:0] snd_addr,
    output     [ 7:0] snd_dout,
    output reg        snd_we,
    input      [ 7:0] snd_din,

    // video
    input      [10:1] txt_addr,
    output     [15:0] txt_data,
    input      [11:1] obj_addr,    // sprite RAM copy at V-blank
    output     [15:0] obj_data,
    output reg [ 7:0] ctrl,
    output reg [ 7:0] bgsy_hi, bgsy_lo, bgsx_hi, bgsx_lo,
                      fgsy_hi, fgsy_lo, fgsx_hi, fgsx_lo,

    input      [ 6:0] joystick1, joystick2,
    input      [ 1:0] cab_1p,
    input      [15:0] dipsw,
    input             dip_pause
);

wire [19:1] A;
wire [ 1:0] be;
wire [15:0] cpu_dout, ram_q, sh_q, txt_q, scr_q;
wire        mem_rd, mem_wr, int_ack, stall;
wire [19:0] ba = {A, 1'b0};
wire [19:0] roff = ba - 20'ha0000;
reg  [15:0] cpu_din;
reg         ram_cs, scr_cs, sh_cs, in0_cs, in1_cs, ctl_cs, txt_cs, snd_cs, int_req, wr_l;
wire        mem_acc = mem_rd | mem_wr;
wire [ 1:0] we = {2{mem_wr}} & be;

assign rom_cs   = mem_rd && ba >= 20'ha0000;
assign rom_addr = roff[18:1];               // a0000 -> 0
assign stall    = (rom_cs & ~rom_ok) | ~dip_pause;
assign snd_addr = A[3:1];
assign snd_dout = cpu_dout[7:0];

always @* begin
    ram_cs = mem_acc && ba[19:15]==0;
    scr_cs = mem_acc && ba[19:8]==(dbldynj ? 12'h0c0 : 12'h080);
    sh_cs  = mem_acc && ba[19:12]==(dbldynj ? 8'h0e : 8'h0a);
    txt_cs = mem_acc && ba[19:11]==(dbldynj ? 9'h010 : 9'h018);
    snd_cs = mem_acc && ba[19:4]==(dbldynj ? 16'h0900 : 16'h0d00);
    in0_cs = mem_acc && ba[19:1]==(dbldynj ? 19'h7800 : 19'h5800);
    in1_cs = mem_acc && ba[19:1]==(dbldynj ? 19'h7801 : 19'h5801);
    ctl_cs = mem_acc && ba[19:1]==(dbldynj ? 19'h7803 : 19'h5803);
    cpu_din = rom_cs ? rom_data :
              ram_cs ? ram_q    :
              sh_cs  ? sh_q     :
              txt_cs ? txt_q    :
              scr_cs ? scr_q    :
              snd_cs ? {8'hff, snd_din} :
              in0_cs ? { cab_1p[1], joystick2[6:4], joystick2[0], joystick2[1], joystick2[2], joystick2[3],
                         cab_1p[0], joystick1[6:4], joystick1[0], joystick1[1], joystick1[2], joystick1[3] } :
              in1_cs ? dipsw : 16'hffff;
end

// scroll registers MAME reads: words 01/02 BG Y, 09/0a BG X, 11/12 FG Y, 19/1a FG X (low bytes)
always @(posedge clk) begin
    wr_l   <= mem_wr;
    snd_we <= mem_wr && !wr_l && snd_cs && be[0];
    if( rst ) begin
        ctrl <= 0;
    end else if( mem_wr && be[0] ) begin
        if( ctl_cs ) ctrl <= cpu_dout[7:0];
        if( scr_cs ) case( A[7:1] )
            7'h01: bgsy_hi <= cpu_dout[7:0];
            7'h02: bgsy_lo <= cpu_dout[7:0];
            7'h09: bgsx_hi <= cpu_dout[7:0];
            7'h0a: bgsx_lo <= cpu_dout[7:0];
            7'h11: fgsy_hi <= cpu_dout[7:0];
            7'h12: fgsy_lo <= cpu_dout[7:0];
            7'h19: fgsx_hi <= cpu_dout[7:0];
            7'h1a: fgsx_lo <= cpu_dout[7:0];
            default:;
        endcase
    end
end

// V-blank IRQ, held until acknowledged (both CPUs use vector 0x32)
always @(posedge clk) begin
    if( rst ) int_req <= 0;
    else if( vint ) int_req <= 1;
    else if( int_ack ) int_req <= 0;
end

jtframe_dual_ram16 #(.AW(14)) u_ram(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( A[14:1] ), .we0 ( ram_cs ? we : 2'b0 ), .q0 ( ram_q ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( {3'b111, obj_addr} ), .we1 ( 2'b0 ), .q1 ( obj_data )
);

jtframe_dual_ram16 #(.AW(11)) u_share(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( A[11:1] ), .we0 ( sh_cs ? we : 2'b0 ), .q0 ( sh_q ),
    .clk1   ( clk       ), .data1 ( sh_din   ), .addr1 ( sh_addr ), .we1 ( sh_we ),          .q1 ( sh_dout )
);

jtframe_dual_ram16 #(.AW(10)) u_txt(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( A[10:1] ), .we0 ( txt_cs ? we : 2'b0 ), .q0 ( txt_q ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( txt_addr ), .we1 ( 2'b0 ),         .q1 ( txt_data )
);

jtframe_dual_ram16 #(.AW(7)) u_scr(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( A[7:1] ), .we0 ( scr_cs ? we : 2'b0 ), .q0 ( scr_q ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( 7'd0    ), .we1 ( 2'b0 ),          .q1 (  )
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
