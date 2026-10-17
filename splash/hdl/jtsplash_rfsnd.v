/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * The Return of Lady Frog sound (MAME splash.cpp, roldfrog): Z80 at 3 MHz in interrupt mode 0 + YM2203.
 *   0000-6fff ROM, 7000-7fff RAM, 8000-ffff ROM bank (region offset 0x10000 + bank * 0x8000).
 *   I/O: 10-11 YM2203, 20-23 read 0xff, 31 bank, 37 vblank IRQ acknowledge, 40 sound latch acknowledge, 70 sound latch.
 *   INT vector 0xc7 | (YM IRQ ? 0x08 : 0) | (vblank IRQ ? 0x18 : 0). NMI while the sound latch is pending. */

module jtsplash_rfsnd(
    input              rst,
    input              clk,
    input              cen,
    input              lvbl,
    input       [ 7:0] main_dout,
    input              snd_wr,
    output      [17:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,

    output signed [15:0] fm,
    output      [ 9:0] psg
);
`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] dout, ram_dout, fm_dout;
reg  [ 7:0] din, latch;
reg  [ 3:0] bank;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, ym_irq_n;
reg         ram_cs, rstn, pending, vbl_irq, lvbl_l, wr_l;
wire        mem   = !mreq_n && rfsh_n;
wire        io    = !iorq_n && m1_n;
wire        inta  = !iorq_n && !m1_n;
wire        fm_cs = io && A[7:1]==7'h08;
wire        int_n = ym_irq_n && !vbl_irq;
wire [ 3:0] bk2   = bank + 4'd2;

assign rom_addr = A[15] ? { bk2[2:0], A[14:0] } : { 2'd0, A };

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && (A[15] || A[15:12] < 4'h7);
    ram_cs = mem && A[15:12]==4'h7;
end

always @(posedge clk) begin
    din <= inta   ? { 3'b110, !vbl_irq ? 2'b01 : 2'b11, 3'b111 } :
           rom_cs ? rom_data : ram_cs ? ram_dout :
           fm_cs  ? fm_dout  : (io && A[7:0]==8'h70) ? latch : 8'hff;
end

always @(posedge clk) begin
    wr_l   <= wr_n;
    lvbl_l <= lvbl;
    if( rst ) begin
        pending <= 0;
        latch   <= 0;
        bank    <= 0;
        vbl_irq <= 0;
    end else begin
        if( snd_wr ) begin
            latch   <= main_dout;
            pending <= 1;
        end
        if( !lvbl && lvbl_l ) vbl_irq <= 1;
        if( io && !wr_n && wr_l ) begin
            case( A[7:0] )
                8'h31: bank    <= dout[3:0];
                8'h37: vbl_irq <= 0;
                8'h40: pending <= 0;
                default:;
            endcase
        end
    end
end

jtframe_sysz80 #(.RAM_AW(12)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen         ),
    .cpu_cen    (             ),
    .int_n      ( int_n       ),
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
    .cen        ( cen         ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm_cs      ),
    .wr_n       ( wr_n        ),
    .dout       ( fm_dout     ),
    .irq_n      ( ym_irq_n    ),
    .IOA_in     ( 8'hff       ),
    .IOB_in     ( 8'hff       ),
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
`else
initial rom_cs=0;
assign rom_addr=0, fm=0, psg=0;
`endif
endmodule
