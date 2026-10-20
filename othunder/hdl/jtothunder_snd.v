/* SPDX-License-Identifier: GPL-3.0-or-later
   Operation Thunderbolt sound: Z80 at 4 MHz, TC0140SYT, YM2610. The Z80 map is the same as Taito's
   P0-039A board, so this reuses jotego/Andrea Bogazzi's jttaitox_sup_snd (from jttaitox_snd).
   The TC0310FAM pan controls (e400) and the rotary stereo switch (ea00) are not modelled. */

module jtothunder_snd(
    input                rst,
    input                clk,
    input                cen8,
    input                snd_cen,

    input                main_cen,
    input                syt_cs,
    input                main_addr,  // 68k A1
    input         [ 3:0] main_dout,
    output        [ 3:0] main_din,
    input                main_rnw,

    output        [15:0] rom_addr,
    output               rom_cs,
    input                rom_ok,
    input         [ 7:0] rom_data,

    output        [18:0] adpcma_addr,
    output               adpcma_cs,
    input         [ 7:0] adpcma_data,
    output        [18:0] adpcmb_addr,
    output               adpcmb_cs,
    input         [ 7:0] adpcmb_data,

    output signed [15:0] sup_l, sup_r,
    output        [ 9:0] psg
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] z80_dout, ram_dout, din;
wire        mreq_n, rd_n, wr_n, iorq_n, m1_n, rfsh_n, cpu_cen;
wire        nmi_n, int_n, sup_rst, ram_cs;
reg         rst_n;

always @(posedge clk) rst_n <= ~(rst | sup_rst);

jtframe_sysz80 #(.RECOVERY(0), .RAM_AW(13)) u_z80(
    .rst_n      ( rst_n         ),
    .clk        ( clk           ),
    .cen        ( snd_cen       ),
    .cpu_cen    ( cpu_cen       ),
    .int_n      ( int_n         ),
    .nmi_n      ( nmi_n         ),
    .busrq_n    ( 1'b1          ),
    .m1_n       ( m1_n          ),
    .mreq_n     ( mreq_n        ),
    .iorq_n     ( iorq_n        ),
    .rd_n       ( rd_n          ),
    .wr_n       ( wr_n          ),
    .rfsh_n     ( rfsh_n        ),
    .halt_n     (               ),
    .busak_n    (               ),
    .A          ( A             ),
    .cpu_din    ( din           ),
    .cpu_dout   ( z80_dout      ),
    .ram_dout   ( ram_dout      ),
    .ram_cs     ( ram_cs        ),
    .rom_cs     ( rom_cs        ),
    .rom_ok     ( rom_ok        )
);

jttaitox_sup_snd u_sup(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen8       ( cen8          ),
    .main_cen   ( main_cen      ),
    .snd_cen    ( snd_cen       ),

    .main_cs    ( syt_cs        ),
    .main_addr  ( main_addr     ),
    .main_dout  ( main_dout     ),
    .main_din   ( main_din      ),
    .main_rnw   ( main_rnw      ),

    .A          ( A             ),
    .din        ( z80_dout      ),
    .mreq_n     ( mreq_n        ),
    .rfsh_n     ( rfsh_n        ),
    .wr_n       ( wr_n          ),
    .ram_dout   ( ram_dout      ),
    .cpu_din    ( din           ),
    .nmi_n      ( nmi_n         ),
    .int_n      ( int_n         ),
    .z80_rst    ( sup_rst       ),

    .rom_cs     ( rom_cs        ),
    .rom_addr   ( rom_addr      ),
    .ram_cs     ( ram_cs        ),
    .rom_data   ( rom_data      ),

    .adpcma_addr( adpcma_addr   ),
    .adpcma_cs  ( adpcma_cs     ),
    .adpcma_data( adpcma_data   ),
    .adpcmb_addr( adpcmb_addr   ),
    .adpcmb_cs  ( adpcmb_cs     ),
    .adpcmb_data( adpcmb_data   ),

    .fm_left    ( sup_l         ),
    .fm_right   ( sup_r         ),
    .psg        ( psg           )
);
`else
assign rom_addr=0, rom_cs=0, main_din=0, adpcma_addr=0, adpcma_cs=0, adpcmb_addr=0, adpcmb_cs=0,
       sup_l=0, sup_r=0, psg=0;
`endif
endmodule
