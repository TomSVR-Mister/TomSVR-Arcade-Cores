/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Funny Bubble sound (MAME funybubl.cpp sound_map): Z80 at 4 MHz, INT while a sound latch byte is pending
 * (the latch read clears it).
 *   0000-7fff ROM   8000-87ff RAM   9000 OKI bank   9800 OKI M6295 (1 MHz, pin 7 high)   a000 sound latch
 *   OKI 00000-1ffff fixed, 20000-3ffff banked: sample ROM 20000 + bank * 20000. */

module jtfunybubl_sound(
    input              rst,
    input              clk,
    input              cen_4,
    input              cen_1,
    input       [ 7:0] latch,
    input              snd_wr,
    output      [14:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [18:0] oki_addr,
    input       [ 7:0] oki_data,
    input              oki_ok,
    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, oki_dout;
wire [17:0] oki_a;
reg  [ 7:0] din;
reg         ram_cs, rstn, pend, bank;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
wire        mem    = !mreq_n && rfsh_n;
wire        bnk_cs = mem && A[15:11] == 5'b10010;
wire        oki_cs = mem && A[15:11] == 5'b10011;
wire        lat_cs = mem && A[15:11] == 5'b10100;
wire        oki_wrn= !(oki_cs && !wr_n);

assign rom_addr = A[14:0];
assign oki_addr = oki_a[17] ? { 1'b0, bank, oki_a[16:0] } + 19'h20000 : { 2'd0, oki_a[16:0] };

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && !A[15];
    ram_cs = mem && A[15:11] == 5'b10000;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : lat_cs ? latch : oki_cs ? oki_dout : 8'hff;
end

always @(posedge clk) begin
    if( rst ) begin pend <= 0; bank <= 0; end
    else begin
        if( bnk_cs && !wr_n ) bank <= dout[0];
        if( snd_wr ) pend <= 1;
        else if( lat_cs && !rd_n ) pend <= 0;
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen_4       ),
    .cpu_cen    (             ),
    .int_n      ( ~pend       ),
    .nmi_n      ( 1'b1        ),
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

jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst           ),
    .clk      ( clk           ),
    .cen      ( cen_1         ),
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
assign rom_addr=0, oki_addr=0, pcm=0;
`endif
endmodule
