/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 16 sound (MAME yunsun16.cpp).
 *  YS-0211 boards (mb=0): OKI M6295 written by the 68000; sample ROM 00000-1ffff fixed,
 *                         20000-3ffff banked in 128 kB pages (800181).
 *  YS1302 board  (mb=1): Z80 at 4 MHz with YM3812 and OKI; the 68000 writes a sound latch at
 *                         800189 that raises the Z80 NMI (0x3a is ignored, as in MAME).
 *                         Z80: 0000-dfff ROM, e000-e7ff RAM; I/O 10-11 YM3812, 18 latch, 1c OKI. */

module jtys16_sound(
    input              rst,
    input              clk,
    input              cen4,
    input              cen_oki,
    input              mb,          // 1 = Magic Bubble YS1302 board
    // 68000 side
    input       [ 7:0] cpu_dout,
    input              snd_wr,      // byte write to 800189
    input       [ 1:0] bank,
    output      [ 7:0] oki_dout,
    // OKI ROM
    output             oki_cs,
    output      [18:0] oki_addr,
    input       [ 7:0] oki_data,
    input              oki_ok,
    // Z80 ROM
    output      [15:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,

    output signed [13:0] pcm,
    output signed [15:0] fm
);
`ifndef NOSOUND
wire [17:0] raw_addr;
wire [15:0] A;
wire [ 7:0] dout, ram_dout, fm_dout, oki_q;
reg  [ 7:0] din, latch;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, int_n, nmi_n;
reg         ram_cs, rstn, nmi_set;
wire        io     = !iorq_n && m1_n;
wire        fm_cs  = io && A[7:1]==7'h08;   // 10-11
wire        lat_cs = io && A[7:0]==8'h18;
wire        zoki   = io && A[7:0]==8'h1c;
wire        oki_wrn = mb ? !(zoki && !wr_n) : !snd_wr;
wire [ 7:0] oki_din = mb ? dout : cpu_dout;

assign oki_cs   = 1'b1;
assign oki_addr = !mb && raw_addr[17] ? { bank, raw_addr[16:0] } : { 1'b0, raw_addr };
assign oki_dout = oki_q;
assign rom_addr = A;

always @(posedge clk) rstn <= ~rst & mb;

always @* begin
    rom_cs = !mreq_n && rfsh_n && A[15:13]!=3'b111;
    ram_cs = !mreq_n && rfsh_n && A[15:11]==5'b11100;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : fm_cs ? fm_dout :
           lat_cs ? latch : zoki ? oki_q : 8'hff;
end

// sound latch and NMI
always @(posedge clk) begin
    nmi_set <= 0;
    if( mb && snd_wr && cpu_dout != 8'h3a ) begin
        latch   <= cpu_dout;
        nmi_set <= 1;
    end
end

jtframe_edge #(.QSET(0)) u_nmi(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .edgeof ( nmi_set   ),
    .clr    ( lat_cs    ),
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
    .rst        ( rst | ~mb   ),
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

jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst      ),
    .clk      ( clk      ),
    .cen      ( cen_oki  ),
    .ss       ( 1'b1     ),
    .wrn      ( oki_wrn  ),
    .din      ( oki_din  ),
    .dout     ( oki_q    ),
    .rom_addr ( raw_addr ),
    .rom_data ( oki_data ),
    .rom_ok   ( oki_ok   ),
    .sound    ( pcm      ),
    .sample   (          )
);
`else
initial rom_cs=0;
assign oki_dout=8'hff, oki_cs=0, oki_addr=0, rom_addr=0, pcm=0, fm=0;
`endif
endmodule
