/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 8-bit sound (MAME yunsung8.cpp): Z80 at 4 MHz, INT while the sound latch is pending.
 *   0000-7fff ROM, 8000-bfff ROM bank, e000 bank (bits 2:0) + MSM5205 reset (bit 5), e400 ADPCM byte,
 *   ec00-ec01 YM3812, f000-f7ff RAM, f800 sound latch.
 * MSM5205 at 400 kHz, /96, 4 bit. Each VCK toggles a selector: high nibble + NMI asserted, then low nibble + NMI released. */

module jtys8_sound(
    input              rst,
    input              clk,
    input              cen4,
    input              cen_adpcm,
    input       [ 7:0] main_dout,
    input              snd_wr,

    output      [16:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,

    output signed [15:0] fm,
    output signed [11:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout;
reg  [ 7:0] din, latch, adpcm;
reg  [ 2:0] bank;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg         ram_cs, rstn, pending, msm_rst, toggle, wr_l, lat_l;
wire        mem    = !mreq_n && rfsh_n;
wire        bnk_cs = mem && A[15:10]==6'b111000;   // e000
wire        dat_cs = mem && A[15:10]==6'b111001;   // e400
wire        fm_cs  = mem && A[15:10]==6'b111011;   // ec00
wire        lat_cs = mem && A[15:11]==5'b11111;    // f800
wire        msm_irq;

assign rom_addr = A[15] ? { bank, A[13:0] } : { 2'd0, A[14:0] };

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && (!A[15] || A[15:14]==2'b10);
    ram_cs = mem && A[15:11]==5'b11110;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : lat_cs ? latch : 8'hff;
end

always @(posedge clk) begin
    wr_l  <= wr_n;
    lat_l <= lat_cs && !rd_n;
    if( rst ) begin
        pending <= 0; latch <= 0; bank <= 0; adpcm <= 0; msm_rst <= 1; toggle <= 0;
    end else begin
        if( snd_wr ) begin latch <= main_dout; pending <= 1; end
        else if( lat_l && !(lat_cs && !rd_n) ) pending <= 0;
        if( !wr_n && wr_l ) begin
            if( bnk_cs ) begin bank <= dout[2:0]; msm_rst <= dout[5]; end
            if( dat_cs ) adpcm <= dout;
        end
        if( msm_irq ) toggle <= ~toggle;
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen4        ),
    .cpu_cen    (             ),
    .int_n      ( ~pending    ),
    .nmi_n      ( ~toggle     ),
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
    .dout       (             ),
    .irq_n      (             ),
    .snd        ( fm          ),
    .sample     (             )
);

jt5205 u_adpcm(
    .rst        ( rst | msm_rst ),
    .clk        ( clk         ),
    .cen        ( cen_adpcm   ),
    .sel        ( 2'd0        ),    // 400 kHz / 96
    .din        ( toggle ? adpcm[3:0] : adpcm[7:4] ),  // sampled with the strobe that flips toggle: new toggle 1 = high nibble
    .sound      ( pcm         ),
    .sample     (             ),
    .irq        ( msm_irq     ),
    .vclk_o     (             )
);
`else
initial rom_cs=0;
assign rom_addr=0, fm=0, pcm=0;
`endif
endmodule
