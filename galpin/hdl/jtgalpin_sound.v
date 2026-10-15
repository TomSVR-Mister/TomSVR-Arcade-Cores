/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gals Pinball sound board: Z80 + YM3812 + OKI M6295.
 * Adapted from jtgaiden_sound.v (Jose Tejada, jotego): same Tecmo-style
 * decoding, with a YM3812 in place of the two YM2203. */

module jtgalpin_sound(
    input                rst,
    input                clk,
    input                cen4,
    input                cen1,

    input       [ 7:0]   cmd,
    input                nmirq,
    // ROM
    output      [15:0]   rom_addr,
    output  reg          rom_cs,
    input       [ 7:0]   rom_data,
    input                rom_ok,
    // ADPCM ROM
    output        [17:0] pcm_addr,
    output               pcm_cs,
    input         [ 7:0] pcm_data,
    input                pcm_ok,
    // Sound
    output signed [15:0] fm,
    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, fm_dout, oki_dout, ram_dout;
reg  [ 7:0] din;
wire        rd_n, wr_n, nmi_n, mreq_n, rfsh_n, oki_wrn, m1_n, iorq_n, int_n;
reg         ram_cs, fm_cs, oki_cs, cmd_cs, rstn;

assign pcm_cs   = 1;
assign oki_wrn  = ~oki_cs | wr_n;
assign rom_addr = A;

always @(posedge clk) rstn <= ~rst;

// 0000-efff ROM, f000-f7ff RAM, f800 OKI, f810-f811 YM3812, fc20 sound latch
always @* begin
    rom_cs = 0;
    ram_cs = 0;
    oki_cs = 0;
    fm_cs  = 0;
    cmd_cs = 0;
    if( !mreq_n && rfsh_n ) begin
        rom_cs = A[15:12]!=4'hf;
        ram_cs = A[15:12]==4'hf && !A[11];
        oki_cs = A[15:12]==4'hf &&  A[11:10]==2 && A[5:4]==0;
        fm_cs  = A[15:12]==4'hf &&  A[11:10]==2 && A[5:4]==1;
        cmd_cs = A[15:12]==4'hf &&  A[11:10]==3 && A[5];
    end
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data :
           ram_cs ? ram_dout :
           oki_cs ? oki_dout :
           fm_cs  ? fm_dout  :
           cmd_cs ? cmd      : 8'hff;
end

jtframe_edge #(.QSET(0)) u_edge(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .edgeof ( nmirq     ),
    .clr    ( cmd_cs    ),
    .q      ( nmi_n     )
);

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen4        ),
    .cpu_cen    (             ),
    .int_n      ( int_n       ),
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
    .cen        ( cen4        ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm_cs      ),
    .wr_n       ( wr_n        ),
    .dout       ( fm_dout     ),
    .irq_n      ( int_n       ),
    .snd        ( fm          ),
    .sample     (             )
);

jt6295 #(.INTERPOL(0)) u_adpcm(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen1      ),
    .ss         ( 1'b1      ),
    .wrn        ( oki_wrn   ),
    .din        ( dout      ),
    .dout       ( oki_dout  ),
    .rom_addr   ( pcm_addr  ),
    .rom_data   ( pcm_data  ),
    .rom_ok     ( pcm_ok    ),
    .sound      ( pcm       ),
    .sample     (           )
);
`else
initial rom_cs=0;
assign  rom_addr=0, pcm_addr=0, pcm_cs=0, fm=0, pcm=0;
`endif
endmodule
