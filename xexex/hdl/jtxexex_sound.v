/*  This file is part of JTXEXEX.
    SPDX-License-Identifier: GPL-3.0-or-later
    Xexex sound board, from MAME's xexex.cpp: Z80 at 8 MHz, YM2151 at 4 MHz (jt51), K054539 PCM
    (jtxexex_k539) and the K054321 sound latches (jotego's jt054321 from JTRIDERS).
    Z80 map: 0000-7FFF ROM, 8000-BFFF bank (F800 bits 2:0), C000-DFFF RAM, E000-E22F K054539,
    EC00-EC01 YM2151, F000-F003 K054321. The K054539 sets the YM2151 volume in MAME through its
    analogue callback; here the YM2151 has a fixed gain. */

module jtxexex_sound(
    input                rst,
    input                clk,
    input                cen_8,
    input                cen_fm,
    input                cen_fm2,
    input                cen_pcm,    // 48 kHz

    // main CPU
    input                snd_irq,
    input                pair_we,
    input         [ 4:1] main_addr,
    input         [ 7:0] main_dout,
    output        [ 7:0] pair_dout,

    // ROM
    output        [16:0] rom_addr,
    output reg           rom_cs,
    input         [ 7:0] rom_data,
    input                rom_ok,
    // PCM ROM
    output        [21:0] pcm_addr,
    output               pcm_cs,
    input         [ 7:0] pcm_data,
    input                pcm_ok,

    output signed [15:0] fm_l, fm_r,
    output signed [15:0] k539_l, k539_r
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] cpu_dout, ram_dout, fm_dout, k39_dout, latch_dout;
wire        mreq_n, rd_n, wr_n, iorq_n, rfsh_n, int_n, latch_we;
wire [23:0] pcm_full;
reg  [ 7:0] cpu_din;
reg  [ 2:0] bank;
reg         ram_cs, k39_cs, fm_cs, k21_cs, bank_cs, mem_acc, k39_wl, k39_rl;

assign rom_addr = { A[15] ? bank : { 2'd0, A[14] }, A[13:0] };
assign pcm_addr = pcm_full[21:0];
assign latch_we = k21_cs & ~wr_n;

always @* begin
    mem_acc = !mreq_n && rfsh_n;
    rom_cs  = mem_acc && !(A[15] && A[14]);
    ram_cs  = mem_acc && A[15:13]==3'b110;      // C000
    k39_cs  = mem_acc && A[15:10]==6'b1110_00;  // E000
    fm_cs   = mem_acc && A[15:10]==6'b1110_11;  // EC00
    k21_cs  = mem_acc && A[15:10]==6'b1111_00;  // F000
    bank_cs = mem_acc && A[15:10]==6'b1111_10;  // F800
    cpu_din = rom_cs ? rom_data   :
              ram_cs ? ram_dout   :
              k39_cs ? k39_dout   :
              fm_cs  ? fm_dout    :
              k21_cs ? latch_dout : 8'hff;
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bank   <= 0;
        k39_wl <= 0;
        k39_rl <= 0;
    end else begin
        if( bank_cs && !wr_n ) bank <= cpu_dout[2:0];
        k39_wl <= k39_cs & ~wr_n;
        k39_rl <= k39_cs & ~rd_n;
    end
end

jt054321 u_54321(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .maddr      ( main_addr ),
    .mdout      ( main_dout ),
    .mdin       ( pair_dout ),
    .mwe        ( pair_we   ),
    .saddr      ( A[1:0]    ),
    .sdout      ( cpu_dout  ),
    .sdin       ( latch_dout),
    .swe        ( latch_we  ),
    .snd_on     ( snd_irq   ),
    .siorq_n    ( iorq_n    ),
    .int_n      ( int_n     )
);

jtframe_sysz80 #(.RAM_AW(13)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen_8     ),
    .cpu_cen    (           ),
    .int_n      ( int_n     ),
    .nmi_n      ( 1'b1      ),
    .busrq_n    ( 1'b1      ),
    .m1_n       (           ),
    .mreq_n     ( mreq_n    ),
    .iorq_n     ( iorq_n    ),
    .rd_n       ( rd_n      ),
    .wr_n       ( wr_n      ),
    .rfsh_n     ( rfsh_n    ),
    .halt_n     (           ),
    .busak_n    (           ),
    .A          ( A         ),
    .cpu_din    ( cpu_din   ),
    .cpu_dout   ( cpu_dout  ),
    .ram_dout   ( ram_dout  ),
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);

jt51 u_fm(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .cen_p1     ( cen_fm2   ),
    .cs_n       ( ~fm_cs    ),
    .wr_n       ( wr_n      ),
    .a0         ( A[0]      ),
    .din        ( cpu_dout  ),
    .dout       ( fm_dout   ),
    .ct1        (           ),
    .ct2        (           ),
    .irq_n      (           ),
    .sample     (           ),
    .left       (           ),
    .right      (           ),
    .xleft      ( fm_l      ),
    .xright     ( fm_r      )
);

jtxexex_k539 u_k539(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .sample     ( cen_pcm   ),
    .addr       ( A[9:0]    ),
    .din        ( cpu_dout  ),
    .dout       ( k39_dout  ),
    .cs         ( k39_cs    ),
    .wr         ( k39_cs & ~wr_n & ~k39_wl ),
    .rd         ( k39_cs & ~rd_n & ~k39_rl ),
    .rom_addr   ( pcm_full  ),
    .rom_cs     ( pcm_cs    ),
    .rom_data   ( pcm_data  ),
    .rom_ok     ( pcm_ok    ),
    .left       ( k539_l    ),
    .right      ( k539_r    )
);
`else
assign rom_addr=0, pcm_addr=0, pcm_cs=0, pair_dout=0, fm_l=0, fm_r=0, k539_l=0, k539_r=0;
initial rom_cs=0;
`endif
endmodule
