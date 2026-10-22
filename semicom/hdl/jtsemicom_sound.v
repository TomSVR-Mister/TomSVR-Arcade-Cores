/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SemiCom sound (MAME snowbros.cpp hyperpac_sound_map): Z80 at 4 MHz.
 *   0000-cfff ROM   d000-d7ff RAM   f000-f001 YM2151 (4 MHz, IRQ to INT)   f002 OKI M6295 (1 MHz, pin 7 high)
 *   f008 sound latch (polled, no NMI) */

module jtsemicom_sound(
    input              rst,
    input              clk,
    input              cen_4,
    input              cen_2,
    input              cen_1,
    input       [ 7:0] latch,
    output      [15:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [17:0] oki_addr,
    input       [ 7:0] oki_data,
    input              oki_ok,
    output signed [15:0] fm_l, fm_r,
    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, oki_dout, fm_dout;
reg  [ 7:0] din;
reg         ram_cs, rstn;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, fm_irqn;
wire        mem    = !mreq_n && rfsh_n;
wire        fm_cs  = mem && A[15:1]==15'h7800;
wire        oki_cs = mem && A==16'hf002;
wire        lat_cs = mem && A==16'hf008;
wire        oki_wrn= !(oki_cs && !wr_n);

assign rom_addr = A;

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && A < 16'hd000;
    ram_cs = mem && A[15:11]==5'b11010;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : oki_cs ? oki_dout : lat_cs ? latch : fm_cs ? fm_dout : 8'hff;
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen_4       ),
    .cpu_cen    (             ),
    .int_n      ( fm_irqn     ),
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
    .cs_n       ( ~fm_cs      ),
    .wr_n       ( wr_n        ),
    .a0         ( A[0]        ),
    .din        ( dout        ),
    .dout       ( fm_dout     ),
    .ct1        (             ),
    .ct2        (             ),
    .irq_n      ( fm_irqn     ),
    .sample     (             ),
    .left       (             ),
    .right      (             ),
    .xleft      ( fm_l        ),
    .xright     ( fm_r        )
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
assign rom_addr=0, oki_addr=0, fm_l=0, fm_r=0, pcm=0;
`endif
endmodule
