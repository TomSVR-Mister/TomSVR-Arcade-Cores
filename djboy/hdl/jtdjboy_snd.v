/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DJ Boy / Air Buster sound CPU (MAME djboy.cpp soundcpu_am/soundcpu_port_am, airbustr.cpp sound_map/sound_io_map):
 * Z80 at 6 MHz, NMI while the sound latch holds an unread command, INT from the YM2203 (3 MHz).
 *   0000-7fff ROM   8000-bfff ROM bank (16 kB pages, port 00)   c000-dfff RAM
 *   DJ Boy:     I/O 02-03 YM2203   04 sound latch   06 OKI left   07 OKI right (both 1.5 MHz, same samples)
 *   Air Buster: I/O 02-03 YM2203 (ports A/B = DSW1/DSW2)   04 OKI (3 MHz)   06 latch in / reply latch out */
module jtdjboy_snd(
    input              rst,
    input              clk,
    input              cen,         // 6 MHz
    input              cen_fm,      // 3 MHz
    input              cen_oki,     // 1.5 MHz (DJ Boy) / 3 MHz (Air Buster)
    input              abus,
    input       [ 7:0] dsw1, dsw2,
    input       [ 7:0] latch,
    input              pending,
    output reg         latch_rd,
    output reg  [ 7:0] reply,       // Air Buster: latch back to the sub CPU
    output reg         reply_wr,
    // ROM
    output      [16:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [17:0] oki0_addr,
    input       [ 7:0] oki0_data,
    input              oki0_ok,
    output      [17:0] oki1_addr,
    input       [ 7:0] oki1_data,
    input              oki1_ok,
    // sound
    output signed [15:0] fm,
    output        [ 9:0] psg,
    output signed [13:0] pcm_l,
    output signed [13:0] pcm_r
);

wire [15:0] A;
wire [ 7:0] dout, ram_dout, fm_dout, oki0_dout, oki1_dout;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, fm_irqn;
wire signed [13:0] snd0, snd1;
reg  [ 7:0] din;
reg  [ 2:0] bank;
reg         ram_cs, rstn, iow_l, ior_l;
wire        mem    = !mreq_n && rfsh_n;
wire        io     = !iorq_n && m1_n;
wire        fm_cs  = io && A[7:1]==7'h01;
wire        oki0_cs= io && A[7:0]==(abus ? 8'h04 : 8'h06);
wire        oki1_cs= io && !abus && A[7:0]==8'h07;
wire        lat_cs = io && A[7:0]==(abus ? 8'h06 : 8'h04);

assign rom_addr = A[15] ? { bank, A[13:0] } : { 2'd0, A[14:0] };
assign pcm_l    = snd0;
assign pcm_r    = abus ? snd0 : snd1;

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && A[15:14]!=2'b11;
    ram_cs = mem && A[15:13]==3'b110;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout :
           fm_cs  ? fm_dout  : oki0_cs ? oki0_dout : oki1_cs ? oki1_dout :
           lat_cs ? latch    : 8'hff;
end

always @(posedge clk) begin
    iow_l    <= io && !wr_n;
    ior_l    <= io && !rd_n;
    latch_rd <= 0;
    reply_wr <= 0;
    if( rst ) begin
        bank <= 0; reply <= 0;
    end else begin
        if( io && !wr_n && !iow_l ) begin
            if( A[7:0]==0 ) bank <= dout[2:0];
            if( lat_cs && abus ) begin reply <= dout; reply_wr <= 1; end
        end
        if( lat_cs && !rd_n && !ior_l ) latch_rd <= 1;
    end
end

jtframe_sysz80 #(.RAM_AW(13)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen         ),
    .cpu_cen    (             ),
    .int_n      ( fm_irqn     ),
    .nmi_n      ( ~pending    ),
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

jt03 u_fm(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen        ( cen_fm      ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm_cs      ),
    .wr_n       ( wr_n        ),
    .dout       ( fm_dout     ),
    .irq_n      ( fm_irqn     ),
    .IOA_in     ( abus ? dsw1 : 8'hff ),
    .IOB_in     ( abus ? dsw2 : 8'hff ),
    .IOA_out    (             ),
    .IOB_out    (             ),
    .IOA_oe     (             ),
    .IOB_oe     (             ),
    .psg_A      (             ),
    .psg_B      (             ),
    .psg_C      (             ),
    .fm_snd     ( fm          ),
    .psg_snd    ( psg         ),
    .snd        (             ),
    .snd_sample (             ),
    .debug_view (             )
);

jt6295 #(.INTERPOL(0)) u_oki0(
    .rst      ( rst           ),
    .clk      ( clk           ),
    .cen      ( cen_oki       ),
    .ss       ( 1'b0          ),    // pin 7 low
    .wrn      ( ~(oki0_cs && !wr_n) ),
    .din      ( dout          ),
    .dout     ( oki0_dout     ),
    .rom_addr ( oki0_addr     ),
    .rom_data ( oki0_data     ),
    .rom_ok   ( oki0_ok       ),
    .sound    ( snd0          ),
    .sample   (               )
);

jt6295 #(.INTERPOL(0)) u_oki1(
    .rst      ( rst | abus    ),
    .clk      ( clk           ),
    .cen      ( cen_oki       ),
    .ss       ( 1'b0          ),
    .wrn      ( ~(oki1_cs && !wr_n) ),
    .din      ( dout          ),
    .dout     ( oki1_dout     ),
    .rom_addr ( oki1_addr     ),
    .rom_data ( oki1_data     ),
    .rom_ok   ( oki1_ok       ),
    .sound    ( snd1          ),
    .sample   (               )
);

endmodule
