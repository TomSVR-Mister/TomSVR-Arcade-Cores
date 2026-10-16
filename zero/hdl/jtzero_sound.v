/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Zero Zone sound (MAME zerozone.cpp): Z80 at 4 MHz, IRQ (vector ff) on each sound latch write, held until acknowledged.
 *   0000-7fff ROM, 8000-87ff RAM, 9800 OKI M6295 (1 MHz, pin 7 high), a000 sound latch */

module jtzero_sound(
    input              rst,
    input              clk,
    input              cen4,
    input              cen1,
    input       [ 7:0] main_dout,
    input              snd_wr,

    output      [14:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,

    output      [17:0] oki_addr,
    input       [ 7:0] oki_data,
    input              oki_ok,

    output signed [13:0] pcm
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, oki_dout;
reg  [ 7:0] din, latch;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg         ram_cs, rstn, int_n;
wire        mem    = !mreq_n && rfsh_n;
wire        oki_cs = mem && A[15:11]==5'b10011;     // 9800-9fff
wire        lat_cs = mem && A[15:13]==3'b101;       // a000-bfff

assign rom_addr = A[14:0];

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && !A[15];
    ram_cs = mem && A[15:11]==5'b10000;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : oki_cs ? oki_dout : lat_cs ? latch : 8'hff;
end

always @(posedge clk) begin
    if( rst ) begin
        int_n <= 1;
        latch <= 0;
    end else begin
        if( snd_wr ) begin
            latch <= main_dout;
            int_n <= 0;
        end else if( !m1_n && !iorq_n ) int_n <= 1;    // interrupt acknowledge
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen4        ),
    .cpu_cen    (             ),
    .int_n      ( int_n       ),
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

jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst      ),
    .clk      ( clk      ),
    .cen      ( cen1     ),
    .ss       ( 1'b1     ),
    .wrn      ( !(oki_cs && !wr_n) ),
    .din      ( dout     ),
    .dout     ( oki_dout ),
    .rom_addr ( oki_addr ),
    .rom_data ( oki_data ),
    .rom_ok   ( oki_ok   ),
    .sound    ( pcm      ),
    .sample   (          )
);
`else
initial rom_cs=0;
assign rom_addr=0, oki_addr=0, pcm=0;
`endif
endmodule
