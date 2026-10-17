/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * YS-1300 sound (MAME nmg5.cpp): Z80 at 4 MHz, INT from the YM3812, NMI pulsed on each sound latch write.
 *   nmg5: 0000-dfff ROM, e000-e7ff RAM.   pclubys (pc): 0000-f7ff ROM, f800-ffff RAM.
 *   I/O: 00 OKI bank (bit 0, 256 kB), 10-11 YM3812, 18 sound latch, 1c OKI M6295 (1 MHz, pin 7 high). */

module jtnmg5_sound(
    input              rst,
    input              clk,
    input              cen_snd,
    input              cen_oki,
    input              pc,
    input       [ 7:0] latch,
    input              snd_wr,
    output      [15:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [18:0] oki_addr,
    input       [ 7:0] oki_data,
    input              oki_ok,
    output signed [15:0] fm,
    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, fm_dout, oki_dout;
reg  [ 7:0] din;
reg         ram_cs, rstn, wr_l, bank, nmi_n;
reg  [ 7:0] nmi_cnt;
wire [17:0] oki_a;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, irq_n;
wire        mem    = !mreq_n && rfsh_n;
wire        io     = !iorq_n && m1_n;
wire        fm_cs  = io && A[7:1]==7'h08;
wire        lat_cs = io && A[7:0]==8'h18;
wire        oki_cs = io && A[7:0]==8'h1c;
wire        oki_wrn= !(oki_cs && !wr_n);

assign rom_addr = A;
assign oki_addr = { bank, oki_a };

always @(posedge clk) rstn <= ~rst;

always @* begin
    ram_cs = mem && (pc ? A[15:11]==5'b11111 : A[15:11]==5'b11100);
    rom_cs = mem && (pc ? A < 16'hf800 : A < 16'he000);
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : fm_cs ? fm_dout : lat_cs ? latch : oki_cs ? oki_dout : 8'hff;
end

always @(posedge clk) begin
    wr_l <= wr_n;
    if( rst ) begin
        bank <= 0; nmi_n <= 1; nmi_cnt <= 0;
    end else begin
        if( io && !wr_n && wr_l && A[7:0]==0 ) bank <= dout[0];
        // NMI pulse
        if( snd_wr ) begin nmi_n <= 0; nmi_cnt <= 0; end
        else if( !nmi_n ) begin
            nmi_cnt <= nmi_cnt + 1'd1;
            if( &nmi_cnt ) nmi_n <= 1;
        end
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen_snd     ),
    .cpu_cen    (             ),
    .int_n      ( irq_n       ),
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
    .irq_n      ( irq_n       ),
    .snd        ( fm          ),
    .sample     (             )
);

jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst           ),
    .clk      ( clk           ),
    .cen      ( cen_oki       ),
    .ss       ( 1'b1          ),
    .wrn      ( oki_wrn       ),
    .din      ( dout          ),
    .dout     ( oki_dout      ),
    .rom_addr ( oki_a         ),
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
