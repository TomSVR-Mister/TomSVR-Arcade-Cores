/* SPDX-License-Identifier: GPL-3.0-or-later
   Bottom of the Ninth sound board: Z80 at 3.58 MHz and two K007232, memory map from MAME bottom9.cpp:
   0000-7fff ROM, 8000-87ff RAM, 9000 sample banks, a000 007232 #1, b000 007232 #2, d000 latch, f000 NMI enable.
   IRQ: written by the main CPU (1fc0), held until acknowledged. NMI: eight per frame while enabled, the line
   stays asserted until the program clears the enable bit. Register 12 of each K007232 sets the channel
   volumes (A: high nibble, B: low nibble). Based on TomSVR's jtchqflag_sound and jotego's jtajax_sound */

module jtbottom9_sound(
    input           rst,
    input           clk,
    input           cen_fm,
    input           nmi_tick,
    // communication with main CPU
    input   [ 7:0]  snd_latch,
    input           snd_irq,
    // ROM
    output  [14:0]  rom_addr,
    output  reg     rom_cs,
    input   [ 7:0]  rom_data,
    input           rom_ok,
    // 007232 #1
    output   [17:0] pcm1a_addr, pcm1b_addr,
    input    [ 7:0] pcm1a_dout, pcm1b_dout,
    output          pcm1a_cs,   pcm1b_cs,
    input           pcm1a_ok,   pcm1b_ok,
    // 007232 #2
    output   [17:0] pcm2a_addr, pcm2b_addr,
    input    [ 7:0] pcm2a_dout, pcm2b_dout,
    output          pcm2a_cs,   pcm2b_cs,
    input           pcm2a_ok,   pcm2b_ok,
    // Sound output
    output signed [10:0] pcm1, pcm2,
    // Debug
    input    [ 7:0] debug_bus,
    output   [ 7:0] st_dout
);
`ifndef NOSOUND
wire        [ 7:0] cpu_dout, ram_dout;
wire        [15:0] A;
reg         [ 7:0] cpu_din, bank;
wire               m1_n, mreq_n, rd_n, wr_n, iorq_n, rfsh_n, cpu_cen;
reg                ram_cs, bank_cs, dac1_cs, dac2_cs, latch_cs, nmien_cs, mem_acc, pend, nmien, nmi_line;

assign rom_addr = A[14:0];
assign st_dout  = bank;
assign pcm1a_addr[17] = bank[0];
assign pcm1b_addr[17] = bank[2];
assign pcm2a_addr[17] = bank[4];
assign pcm2b_addr[17] = bank[6];

always @(*) begin
    mem_acc  = !mreq_n && rfsh_n;
    rom_cs   = mem_acc && !A[15];
    ram_cs   = mem_acc && A[15:12]==4'h8 && !A[11];
    bank_cs  = mem_acc && A[15:12]==4'h9;
    dac1_cs  = mem_acc && A[15:12]==4'ha;
    dac2_cs  = mem_acc && A[15:12]==4'hb;
    latch_cs = mem_acc && A[15:12]==4'hd;
    nmien_cs = mem_acc && A[15:12]==4'hf;
    case(1'b1)
        rom_cs:   cpu_din = rom_data;
        ram_cs:   cpu_din = ram_dout;
        latch_cs: cpu_din = snd_latch;
        default:  cpu_din = 8'hff;
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        bank     <= 0;
        pend     <= 0;
        nmien    <= 0;
        nmi_line <= 0;
    end else begin
        if( snd_irq ) pend <= 1;
        if( !m1_n && !iorq_n ) pend <= 0;   // interrupt acknowledge
        if( nmi_tick && nmien ) nmi_line <= 1;
        if( !wr_n ) begin
            if( bank_cs ) bank <= cpu_dout;
            if( nmien_cs ) begin
                nmien <= cpu_dout[0];
                if( !cpu_dout[0] ) nmi_line <= 0;
            end
        end
    end
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .cpu_cen    ( cpu_cen   ),
    .int_n      ( ~pend     ),
    .nmi_n      ( ~nmi_line ),
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

jt007232 u_pcm1(
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
    .snda       (           ),
    .sndb       (           ),
    .snd        ( pcm1      ),
    .debug_bus  ( debug_bus ),
    .st_dout    (           )
);

jt007232 u_pcm2(
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
    .snda       (           ),
    .sndb       (           ),
    .snd        ( pcm2      ),
    .debug_bus  ( debug_bus ),
    .st_dout    (           )
);
`else
initial rom_cs = 0;
assign rom_addr=0, pcm1a_cs=0, pcm1b_cs=0, pcm2a_cs=0, pcm2b_cs=0, pcm1a_addr=0, pcm1b_addr=0,
       pcm2a_addr=0, pcm2b_addr=0, pcm1=0, pcm2=0, st_dout=0;
`endif
endmodule
