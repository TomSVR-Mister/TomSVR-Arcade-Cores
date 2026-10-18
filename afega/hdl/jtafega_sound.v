/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Afega sound (MAME nmk16.cpp afega_sound_cpu): Z80 at 4 MHz.
 *   0000-efff ROM   f000-f7ff RAM   f800 sound latch   f808-f809 YM2151 (4 MHz)   f80a OKI M6295 (1 MHz, pin 7 high)
 *   INT = sound latch pending OR YM2151 IRQ. The latch read clears the pending flag.
 * dol (Dolmen, MAME ssmissin_sound_map): 0000-7fff ROM   8000-87ff RAM   9000 OKI bank   9800 OKI   a000 sound latch,
 *   no YM2151. OKI 20000-3ffff banked in 128 kB steps (4 banks of the 512 kB sample ROM).
 * oki_addr is the byte address in SDRAM bank 0: the samples at 90000 (Dolmen: the first 256 kB of the sample space at
 *   90000, the rest at 40000, after its 256 kB program). */

module jtafega_sound(
    input              rst,
    input              clk,
    input              cen_4,
    input              cen_2,
    input              cen_1,
    input              dol,
    input       [ 7:0] latch,
    input              snd_wr,
    output      [15:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [19:0] oki_addr,
    input       [ 7:0] oki_data,
    input              oki_ok,
    output signed [15:0] opm_l,
    output signed [15:0] opm_r,
    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, oki_dout, opm_dout;
reg  [ 7:0] din;
reg         ram_cs, rstn, pend;
reg  [ 1:0] bank;
wire [17:0] oki_a;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, opm_irqn;
wire        mem    = !mreq_n && rfsh_n;
wire        hi     = mem && A[15:4] == 12'hf80;
wire        lat_cs = dol ? mem && A[15:11] == 5'b10100 : hi && A[3:0] == 4'h0;
wire        opm_cs = !dol && hi && A[3:1] == 3'b100;
wire        oki_cs = dol ? mem && A[15:11] == 5'b10011 : hi && A[3:0] == 4'ha;
wire        bnk_cs = dol && mem && A[15:11] == 5'b10010;
wire [18:0] oki_e  = oki_a[17] ? { bank, oki_a[16:0] } : { 2'b00, oki_a[16:0] };
wire        oki_wrn= !(oki_cs && !wr_n);

assign rom_addr = A;
assign oki_addr = !dol ? 20'h90000 + { 2'd0, oki_a } : oki_e[18] ? { 1'b0, oki_e } : 20'h90000 + { 3'd0, oki_e[16:0] };

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = dol ? mem && !A[15] : mem && A[15:12] != 4'hf;
    ram_cs = dol ? mem && A[15:11] == 5'b10000 : mem && A[15:11] == 5'b11110;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : lat_cs ? latch : opm_cs ? opm_dout : oki_cs ? oki_dout : 8'hff;
end

always @(posedge clk) begin
    if( rst ) begin pend <= 0; bank <= 0; end
    else begin
        if( bnk_cs && !wr_n ) bank <= dout[1:0];
        if( snd_wr ) pend <= 1;
        else if( lat_cs && !rd_n ) pend <= 0;
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen_4       ),
    .cpu_cen    (             ),
    .int_n      ( ~pend & opm_irqn ),
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

jt51 u_opm(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen        ( cen_4       ),
    .cen_p1     ( cen_2       ),
    .cs_n       ( ~opm_cs     ),
    .wr_n       ( wr_n        ),
    .a0         ( A[0]        ),
    .din        ( dout        ),
    .dout       ( opm_dout    ),
    .ct1        (             ),
    .ct2        (             ),
    .irq_n      ( opm_irqn    ),
    .sample     (             ),
    .left       (             ),
    .right      (             ),
    .xleft      ( opm_l       ),
    .xright     ( opm_r       )
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
assign rom_addr=0, oki_addr=0, opm_l=0, opm_r=0, pcm=0;
`endif
endmodule
