/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * OKI M6295 at 1 MHz (pin 7 high). Sample ROM 00000-1ffff fixed, 20000-3ffff banked in 128 kB pages */

module jtys16_sound(
    input              rst,
    input              clk,
    input              cen,
    input       [ 7:0] din,
    input              wrn,
    input       [ 1:0] bank,
    output      [ 7:0] dout,

    output             rom_cs,
    output      [18:0] rom_addr,
    input       [ 7:0] rom_data,
    input              rom_ok,

    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [17:0] raw_addr;

assign rom_cs   = 1'b1;
assign rom_addr = raw_addr[17] ? { bank, raw_addr[16:0] } : { 2'd0, raw_addr[16:0] };

jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst      ),
    .clk      ( clk      ),
    .cen      ( cen      ),
    .ss       ( 1'b1     ),
    .wrn      ( wrn      ),
    .din      ( din      ),
    .dout     ( dout     ),
    .rom_addr ( raw_addr ),
    .rom_data ( rom_data ),
    .rom_ok   ( rom_ok   ),
    .sound    ( pcm      ),
    .sample   (          )
);
`else
assign dout=8'hff, rom_cs=0, rom_addr=0, pcm=0;
`endif
endmodule
