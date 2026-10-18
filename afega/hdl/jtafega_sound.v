/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Afega sound (MAME nmk16.cpp afega_sound_cpu): Z80 at 4 MHz.
 *   0000-efff ROM   f000-f7ff RAM   f800 sound latch   f808-f809 YM2151 (4 MHz)   f80a OKI M6295 (1 MHz, pin 7 high)
 *   INT = sound latch pending OR YM2151 IRQ. The latch read clears the pending flag. */

module jtafega_sound(
    input              rst,
    input              clk,
    input              cen_4,
    input              cen_2,
    input              cen_1,
    input       [ 7:0] latch,
    input              snd_wr,
    output      [15:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [17:0] oki_addr,
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
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, opm_irqn;
wire        mem    = !mreq_n && rfsh_n;
wire        hi     = mem && A[15:4] == 12'hf80;
wire        lat_cs = hi && A[3:0] == 4'h0;
wire        opm_cs = hi && A[3:1] == 3'b100;
wire        oki_cs = hi && A[3:0] == 4'ha;
wire        oki_wrn= !(oki_cs && !wr_n);

assign rom_addr = A;

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && A[15:12] != 4'hf;
    ram_cs = mem && A[15:11] == 5'b11110;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : lat_cs ? latch : opm_cs ? opm_dout : oki_cs ? oki_dout : 8'hff;
end

always @(posedge clk) begin
    if( rst ) pend <= 0;
    else begin
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
    .rom_addr ( oki_addr      ),
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
