/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * VISYS sound (MAME oneshot.cpp): Z80 at 3.375 MHz, INT from the YM3812.
 *   0000-7fff ROM, 8000 sound latch (read and write, shared with the 68000), 8001-87ff RAM,
 *   e000-e001 YM3812, e010 OKI M6295 (no samples on these games: reads as idle). */

module jtmadd_sound(
    input              rst,
    input              clk,
    input              cen_snd,
    input       [ 7:0] main_dout,
    input              snd_wr,
    output reg  [ 7:0] latch,
    output      [15:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output signed [15:0] fm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, fm_dout;
reg  [ 7:0] din;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, irq_n;
reg         ram_cs, rstn, wr_l;
wire        mem    = !mreq_n && rfsh_n;
wire        lat_cs = mem && A[15:11]==5'b10000 && A[10:0]==0;
wire        fm_cs  = mem && A[15:4]==12'he00;
wire        oki_cs = mem && A[15:4]==12'he01;

assign rom_addr = { 1'b0, A[14:0] };

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && !A[15];
    ram_cs = mem && A[15:11]==5'b10000 && A[10:0]!=0;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : fm_cs ? fm_dout : lat_cs ? latch : oki_cs ? 8'h00 : 8'hff;
end

always @(posedge clk) begin
    wr_l <= wr_n;
    if( rst ) latch <= 0;
    else begin
        if( snd_wr ) latch <= main_dout;
        if( !wr_n && wr_l && lat_cs ) latch <= dout;
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen_snd     ),
    .cpu_cen    (             ),
    .int_n      ( irq_n       ),
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

jtopl2 u_fm(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen        ( cen_snd     ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm_cs      ),
    .wr_n       ( wr_n        ),
    .dout       ( fm_dout     ),
    .irq_n      ( irq_n       ),
    .snd        ( fm          ),
    .sample     (             )
);
`else
initial begin rom_cs=0; latch=0; end
assign rom_addr=0, fm=0;
`endif
endmodule
