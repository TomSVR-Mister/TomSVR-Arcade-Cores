/* SPDX-License-Identifier: GPL-3.0-or-later
   Chequered Flag sound board: Z80 at 3.58 MHz, YM2151 (IRQ to NMI), two K007232 with bank and
   volume latches. Memory map and volume wiring from MAME chqflag.cpp; based on jotego's jtajax_sound */

module jtchqflag_sound(
    input           rst,
    input           clk,
    input           cen_fm,
    input           cen_fm2,
    // communication with main CPU
    input   [ 7:0]  snd_latch, snd_latch2,
    input           snd_irq,
    // ROM
    output  [14:0]  rom_addr,
    output  reg     rom_cs,
    input   [ 7:0]  rom_data,
    input           rom_ok,
    // 007232 #1
    output   [18:0] pcm1a_addr, pcm1b_addr,
    input    [ 7:0] pcm1a_dout, pcm1b_dout,
    output          pcm1a_cs,   pcm1b_cs,
    input           pcm1a_ok,   pcm1b_ok,
    // 007232 #2
    output   [18:0] pcm2a_addr, pcm2b_addr,
    input    [ 7:0] pcm2a_dout, pcm2b_dout,
    output          pcm2a_cs,   pcm2b_cs,
    input           pcm2a_ok,   pcm2b_ok,
    // Sound output
    output signed [15:0] fm_l, fm_r,
    output reg signed [10:0] pcm1_l, pcm1_r, pcm2,
    // Debug
    input    [ 7:0] debug_bus,
    output   [ 7:0] st_dout
);
`ifndef NOSOUND
wire        [ 7:0] cpu_dout, ram_dout, fm_dout;
wire        [15:0] A;
reg         [ 7:0] cpu_din, bank, vol1a, vol1b, vol2;
wire               m1_n, mreq_n, rd_n, wr_n, iorq_n, rfsh_n, fm_irqn, cpu_cen;
reg                ram_cs, bank_cs, dac1_cs, ext_cs, dac2_cs, fm_cs, l1_cs, l2_cs, mem_acc, pend, l2_l;
wire signed [10:0] s1a, s1b, s2a, s2b;

assign rom_addr = A[14:0];
assign st_dout  = bank;
assign pcm1a_addr[18:17] = bank[5:4];
assign pcm1b_addr[18:17] = bank[7:6];
assign pcm2a_addr[18:17] = bank[1:0];
assign pcm2b_addr[18:17] = bank[3:2];

always @(*) begin
    mem_acc = !mreq_n && rfsh_n;
    rom_cs  = mem_acc && !A[15];
    ram_cs  = mem_acc && A[15:12]==4'h8 && A[11]==0;
    bank_cs = mem_acc && A[15:12]==4'h9;
    dac1_cs = mem_acc && A[15:12]==4'ha && !A[4];
    ext_cs  = mem_acc && A[15:12]==4'ha &&  A[4];
    dac2_cs = mem_acc && A[15:12]==4'hb;
    fm_cs   = mem_acc && A[15:12]==4'hc;
    l1_cs   = mem_acc && A[15:12]==4'hd;
    l2_cs   = mem_acc && A[15:12]==4'he;
    case(1'b1)
        rom_cs:  cpu_din = rom_data;
        ram_cs:  cpu_din = ram_dout;
        fm_cs:   cpu_din = fm_dout;
        l1_cs:   cpu_din = snd_latch;
        l2_cs:   cpu_din = snd_latch2;
        default: cpu_din = 8'hff;
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        bank  <= 0;
        vol1a <= 0;
        vol1b <= 0;
        vol2  <= 0;
        pend  <= 0;
    end else begin
        l2_l <= l2_cs & ~rd_n;
        if( snd_irq ) pend <= 1;
        if( l2_cs && !rd_n && !l2_l ) pend <= 0;   // reading the second latch acknowledges it
        if( !wr_n ) begin
            if( bank_cs ) bank <= cpu_dout;
            if( dac1_cs && A[3:0]==4'hc ) vol1a <= cpu_dout;
            if( ext_cs  && A[3:0]==4'hc ) vol1b <= cpu_dout;
            if( dac2_cs && A[3:0]==4'hc ) vol2  <= cpu_dout;
        end
    end
end

// Volume wiring (MAME guesses): chip 1 channel A/B, low nibble left, high nibble right, half gain;
// chip 2 channel A uses the high nibble, channel B the low one, both to both speakers
reg signed [12:0] l1, r1, m2;
always @(posedge clk) begin
    l1 <= s1a*$signed({1'b0,vol1a[3:0]}) + s1b*$signed({1'b0,vol1b[3:0]});
    r1 <= s1a*$signed({1'b0,vol1a[7:4]}) + s1b*$signed({1'b0,vol1b[7:4]});
    m2 <= s2a*$signed({1'b0,vol2[7:4]})  + s2b*$signed({1'b0,vol2[3:0]});
    pcm1_l <= l1[12:2];
    pcm1_r <= r1[12:2];
    pcm2   <= m2[11:1];
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .cpu_cen    ( cpu_cen   ),
    .int_n      ( ~pend     ),
    .nmi_n      ( fm_irqn   ),
    .busrq_n    ( 1'b1      ),
    .m1_n       ( m1_n      ),
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

jt51 u_jt51(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .cen_p1     ( cen_fm2   ),
    .cs_n       ( !fm_cs    ),
    .wr_n       ( wr_n      ),
    .a0         ( A[0]      ),
    .din        ( cpu_dout  ),
    .dout       ( fm_dout   ),
    .ct1        (           ),
    .ct2        (           ),
    .irq_n      ( fm_irqn   ),
    .sample     (           ),
    .left       (           ),
    .right      (           ),
    .xleft      ( fm_l      ),
    .xright     ( fm_r      )
);

jt007232 #(.NOGAIN(1)) u_pcm1(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .addr       ( A[3:0]    ),
    .dacs       ( dac1_cs   ),
    .cen_q      (           ),
    .cen_e      (           ),
    .wr_n       ( wr_n      ),
    .din        ( cpu_dout  ),
    .swap_gains ( 1'b0      ),
    .roma_addr  ( pcm1a_addr[16:0] ),
    .roma_dout  ( pcm1a_dout ),
    .roma_cs    ( pcm1a_cs   ),
    .roma_ok    ( pcm1a_ok   ),
    .romb_addr  ( pcm1b_addr[16:0] ),
    .romb_dout  ( pcm1b_dout ),
    .romb_cs    ( pcm1b_cs   ),
    .romb_ok    ( pcm1b_ok   ),
    .snda       ( s1a       ),
    .sndb       ( s1b       ),
    .snd        (           ),
    .debug_bus  ( debug_bus ),
    .st_dout    (           )
);

jt007232 #(.NOGAIN(1)) u_pcm2(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .addr       ( A[3:0]    ),
    .dacs       ( dac2_cs   ),
    .cen_q      (           ),
    .cen_e      (           ),
    .wr_n       ( wr_n      ),
    .din        ( cpu_dout  ),
    .swap_gains ( 1'b0      ),
    .roma_addr  ( pcm2a_addr[16:0] ),
    .roma_dout  ( pcm2a_dout ),
    .roma_cs    ( pcm2a_cs   ),
    .roma_ok    ( pcm2a_ok   ),
    .romb_addr  ( pcm2b_addr[16:0] ),
    .romb_dout  ( pcm2b_dout ),
    .romb_cs    ( pcm2b_cs   ),
    .romb_ok    ( pcm2b_ok   ),
    .snda       ( s2a       ),
    .sndb       ( s2b       ),
    .snd        (           ),
    .debug_bus  ( debug_bus ),
    .st_dout    (           )
);
`else
initial rom_cs = 0;
assign rom_addr=0, pcm1a_cs=0, pcm1b_cs=0, pcm2a_cs=0, pcm2b_cs=0, pcm1a_addr=0, pcm1b_addr=0,
       pcm2a_addr=0, pcm2b_addr=0, fm_l=0, fm_r=0, st_dout=0;
initial begin pcm1_l=0; pcm1_r=0; pcm2=0; end
`endif
endmodule
