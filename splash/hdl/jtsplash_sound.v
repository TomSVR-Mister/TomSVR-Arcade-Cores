/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Splash! sound (MAME splash.cpp): Z80 at 3.75 MHz, NMI at 3840 Hz, INT while the sound latch is pending.
 *   0000-d7ff ROM, d800 ADPCM byte, e000 MSM5205 reset (bit 0 low = reset), e800 latch, f000-f001 YM3812,
 *   f800-ffff RAM. The MSM5205 (384 kHz, 8 kHz, 4 bit) plays the high nibble of the ADPCM byte, then the low one. */

module jtsplash_sound(
    input              rst,
    input              clk,
    input              cen_snd,
    input              cen_adpcm,
    // 68000 side
    input       [ 7:0] main_dout,
    input              snd_wr,
    // Z80 ROM
    output      [15:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,

    output signed [15:0] fm,
    output signed [11:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, fm_dout;
reg  [ 7:0] din, latch, adpcm;
reg  [ 3:0] nibble;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg         ram_cs, rstn, pending, msm_rst;
reg  [13:0] nmi_cnt;
reg         nmi_n;
wire        mem    = !mreq_n && rfsh_n;
wire        fm_cs  = mem && A[15:11]==5'b11110;     // f000-f7ff
wire        lat_cs = mem && A[15:11]==5'b11101;     // e800-efff
wire        dat_cs = mem && A[15:11]==5'b11011;     // d800-dfff
wire        ctl_cs = mem && A[15:11]==5'b11100;     // e000-e7ff
wire        msm_irq;

assign rom_addr = A;

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && A < 16'hd800;
    ram_cs = mem && A[15:11]==5'b11111;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : fm_cs ? fm_dout : lat_cs ? latch : 8'hff;
end

// sound latch: INT stays low until the Z80 reads it
reg lat_l;
always @(posedge clk) begin
    lat_l <= lat_cs && !rd_n;
    if( rst ) begin
        pending <= 0;
        latch   <= 0;
    end else begin
        if( snd_wr ) begin
            latch   <= main_dout;
            pending <= 1;
        end else if( lat_l && !(lat_cs && !rd_n) ) pending <= 0;
    end
end

// NMI at 3840 Hz (48 MHz / 12500)
always @(posedge clk) begin
    if( rst ) begin
        nmi_cnt <= 0;
        nmi_n   <= 1;
    end else begin
        nmi_cnt <= nmi_cnt == 14'd12499 ? 14'd0 : nmi_cnt + 1'd1;
        if( nmi_cnt == 0 )   nmi_n <= 0;
        if( nmi_cnt == 255 ) nmi_n <= 1;
    end
end

// ADPCM data and control
reg wr_l;
always @(posedge clk) begin
    wr_l <= wr_n;
    if( rst ) begin
        adpcm   <= 0;
        nibble  <= 0;
        msm_rst <= 1;
    end else begin
        if( !wr_n && wr_l && dat_cs ) adpcm <= dout;
        else if( msm_irq ) begin
            nibble <= adpcm[7:4];
            adpcm  <= { adpcm[3:0], 4'd0 };
        end
        if( !wr_n && wr_l && ctl_cs ) msm_rst <= ~dout[0];
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen_snd     ),
    .cpu_cen    (             ),
    .int_n      ( ~pending    ),
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
    .cen        ( cen_snd     ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm_cs      ),
    .wr_n       ( wr_n        ),
    .dout       ( fm_dout     ),
    .irq_n      (             ),
    .snd        ( fm          ),
    .sample     (             )
);

jt5205 u_adpcm(
    .rst        ( rst | msm_rst ),
    .clk        ( clk         ),
    .cen        ( cen_adpcm   ),
    .sel        ( 2'd2        ),    // 384 kHz / 48 = 8 kHz
    .din        ( nibble      ),
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
