/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Honey Doll sound (MAME snowbros.cpp honeydol_sound_map): Z80 at 4 MHz.
 *   0000-7fff ROM   8000-87ff RAM   e010 OKI M6295 (1 MHz, pin 7 high)
 *   I/O 02-03 YM3812 (3 MHz, IRQ to INT)   I/O 04 sound latch; a pending latch byte drives NMI. */

module jthdoll_sound(
    input              rst,
    input              clk,
    input              cen_4,
    input              cen_3,
    input              cen_1,
    input       [ 7:0] latch,
    input              snd_wr,
    output      [14:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [17:0] oki_addr,
    input       [ 7:0] oki_data,
    input              oki_ok,
    output signed [15:0] fm,
    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, oki_dout, fm_dout;
reg  [ 7:0] din;
reg         ram_cs, rstn, pend;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, fm_irqn;
wire        mem    = !mreq_n && rfsh_n;
wire        io     = !iorq_n && m1_n;
wire        fm_cs  = io && A[7:1]==7'h01;
wire        lat_cs = io && A[7:0]==8'h04;
wire        oki_cs = mem && A==16'he010;
wire        oki_wrn= !(oki_cs && !wr_n);

assign rom_addr = A[14:0];

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && !A[15];
    ram_cs = mem && A[15:11]==5'b10000;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : oki_cs ? oki_dout : lat_cs ? latch : fm_cs ? fm_dout : 8'hff;
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
    .int_n      ( fm_irqn     ),
    .nmi_n      ( ~pend       ),
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
    .cen        ( cen_3       ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm_cs      ),
    .wr_n       ( wr_n        ),
    .dout       ( fm_dout     ),
    .irq_n      ( fm_irqn     ),
    .snd        ( fm          ),
    .sample     (             )
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
assign rom_addr=0, oki_addr=0, fm=0, pcm=0;
`endif
endmodule
