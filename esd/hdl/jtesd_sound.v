/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * ESD 16-bit sound (MAME esd16.cpp): Z80 at 4 MHz (3.5 MHz on Jumping Pop), INT while a sound latch byte is pending,
 *   NMI pulsed at 32 x 60 Hz. 0000-7fff ROM, 8000-bfff ROM bank (16 kB pages), f800-ffff RAM.
 *   I/O: 00-01 YM3812 (write only), 02 OKI M6295 (1 MHz / 875 kHz, pin 7 high), 03 sound latch, 05 ROM bank. */

module jtesd_sound(
    input              rst,
    input              clk,
    input              cen_snd,
    input              cen_oki,
    input       [ 7:0] latch,
    input              snd_wr,
    output      [17:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [18:0] oki_addr,
    input       [ 7:0] oki_data,
    input              oki_ok,
    output signed [15:0] fm,
    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, oki_dout;
reg  [ 7:0] din;
reg         ram_cs, rstn, wr_l, pend, nmi_n;
reg  [ 3:0] bank;
reg  [15:0] nmi_cnt;
wire [17:0] oki_a;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
wire        mem    = !mreq_n && rfsh_n;
wire        io     = !iorq_n && m1_n;
wire        fm_cs  = io && A[7:1]==7'h00;
wire        oki_cs = io && A[7:0]==8'h02;
wire        lat_cs = io && A[7:0]==8'h03;
wire        oki_wrn= !(oki_cs && !wr_n);

assign rom_addr = A[15] ? { bank, A[13:0] } : { 3'd0, A[14:0] };
assign oki_addr = { 1'b0, oki_a };

always @(posedge clk) rstn <= ~rst;

always @* begin
    ram_cs = mem && A[15:11]==5'b11111;
    rom_cs = mem && A[15:14]!=2'b11;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : lat_cs ? latch : oki_cs ? oki_dout : 8'hff;
end

// NMI at 1920 Hz (48 MHz / 25000), a short pulse
always @(posedge clk) begin
    wr_l <= wr_n;
    if( rst ) begin
        bank <= 0; pend <= 0; nmi_n <= 1; nmi_cnt <= 0;
    end else begin
        if( io && !wr_n && wr_l && A[7:0]==8'h05 ) bank <= dout[3:0];
        if( snd_wr ) pend <= 1;
        else if( lat_cs && !rd_n ) pend <= 0;
        nmi_cnt <= nmi_cnt==16'd24999 ? 16'd0 : nmi_cnt + 1'd1;
        if( nmi_cnt==0 ) nmi_n <= 0;
        if( nmi_cnt==16'd480 ) nmi_n <= 1;
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen_snd     ),
    .cpu_cen    (             ),
    .int_n      ( ~pend       ),
    .nmi_n      ( nmi_n       ),
    .busrq_n    ( 1'b1        ),
    .m1_n       ( m1_n        ),
    .mreq_n     ( mreq_n      ),
    .iorq_n     ( iorq_n      ),
    .rd_n       ( rd_n        ),
    .wr_n       ( wr_n        ),
    .rfsh_n     ( rfsh_n      ),
    .halt_n     (             ),
    .busak_n    (             ),
    .A          ( A           ),
    .cpu_din    ( din         ),
    .cpu_dout   ( dout        ),
    .ram_dout   ( ram_dout    ),
    .ram_cs     ( ram_cs      ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( rom_ok      )
);

jtopl2 u_fm(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen        ( cen_snd     ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm_cs      ),
    .wr_n       ( wr_n        ),
    .dout       (             ),
    .irq_n      (             ),
    .snd        ( fm          ),
    .sample     (             )
);

jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst           ),
    .clk      ( clk           ),
    .cen      ( cen_oki       ),
    .ss       ( 1'b1          ),
    .wrn      ( oki_wrn       ),
    .din      ( dout          ),
    .dout     ( oki_dout      ),
    .rom_addr ( oki_a         ),
    .rom_data ( oki_data      ),
    .rom_ok   ( oki_ok        ),
    .sound    ( pcm           ),
    .sample   (               )
);
`else
initial rom_cs=0;
assign rom_addr=0, oki_addr=0, fm=0, pcm=0;
`endif
endmodule
