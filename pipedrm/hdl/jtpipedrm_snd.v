/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Pipe Dream sound (MAME vsystem/pipedrm.cpp sound_map / pipedrm_state::sound_portmap): Z80 at 14.318181/4 MHz and
 * a YM2610 at 8 MHz. Structure and the YM2610 write hold follow jtpspike_snd.v by Andrea Bogazzi (jotego/jtcores,
 * GPL-3), the same Video System sound board family.
 *   0000-77ff ROM   7800-7fff RAM   8000-ffff ROM bank (2 x 32 kB from sub 10000)
 *   I/O 04 W bank   16 R sound latch   17 W latch acknowledge   18-1b YM2610
 *   NMI while a latch byte is pending. INT = YM2610 IRQ, plus the "fake CRTC" interrupt MAME raises on this CPU at
 *   every vertical blank once the game has written GGA register 0b (fromance_gga_data_w, HOLD_LINE).
 * Hatris (hatris_state::sound_portmap): 00-03 (mirror 08) YM2608 (jtpipedrm_opna), 04 R sound latch, 05 R latch
 * pending / W acknowledge, no NMI (MAME: the game polls), no ROM bank. */
module jtpipedrm_snd(
    input                rst,
    input                clk,
    input                cen,        // 3.58 MHz
    input                fm_cen,     // 8 MHz, held while an ADPCM byte is fetched
    input                hatris,

    input      [ 7:0]    snd_latch,
    input                snd_wr,
    output reg           snd_pending,
    input                lvbl,
    input                crtc_irq_en,

    output     [16:0]    rom_addr,
    output               rom_cs,
    input      [ 7:0]    rom_data,
    input                rom_ok,

    output     [18:0]    pcma_addr,
    output               pcma_cs,
    input      [ 7:0]    pcma_data,
    output     [18:0]    pcmb_addr,
    output               pcmb_cs,
    input      [ 7:0]    pcmb_data,

    output signed [15:0] fm,
    output        [ 9:0] psg
);

`ifndef NOSOUND
wire [15:0] A;
wire [ 7:0] cpu_dout, fm_dout, ram_dout;
reg  [ 7:0] cpu_din;
reg         bank, crtc_irq, lvbl_l;
wire        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n, ym_irq_n;
wire        mem_acc  = ~mreq_n & rfsh_n;
wire        io_acc   = ~iorq_n & m1_n;
wire        ram_cs   = mem_acc & A[15:11]==5'b01111;
wire        bank_cs  = io_acc & A[7:0]==8'h04 & ~hatris;
wire        latch_rd = io_acc & (hatris ? A[7:0]==8'h04 : A[7:0]==8'h16) & ~rd_n;
wire        pend_rd  = io_acc & hatris & A[7:0]==8'h05 & ~rd_n;
wire        latch_ack= io_acc & (hatris ? A[7:0]==8'h05 : A[7:0]==8'h17) & ~wr_n;
wire        fm_cs    = io_acc & ~hatris & A[7:2]==6'b0001_10;   // 18-1b
wire        opna_cs  = io_acc &  hatris & A[7:4]==4'h0 & ~A[2]; // 00-03, 08-0b
wire        opna_irq_n, opna_ready;
wire [ 7:0] opna_dout;
wire signed [15:0] opna_l, opna_r;
wire [ 9:0] opna_psg, jt10_psg;
wire [19:0] opna_aaddr;
wire [23:0] opna_baddr;
wire        opna_aroe_n, opna_broe_n;
wire signed [15:0] fm_l, fm_r;
wire [19:0] adpcma_addr;
wire [23:0] adpcmb_addr;
wire [ 4:0] adpcma_bank;
wire        adpcma_roe_n, adpcmb_roe_n;
reg  [ 6:0] busy_cnt;
reg         fmwr_l;
wire        fm_wr   = (fm_cs | opna_cs) & ~wr_n;
wire        fm_busy = busy_cnt!=0;

assign rom_cs   = mem_acc & ~ram_cs;
assign rom_addr = A[15] ? { 1'b1, bank, A[14:0] } : { 2'd0, A[14:0] };
assign fm       = hatris ? (opna_l>>>1) + (opna_r>>>1) : (fm_l>>>1) + (fm_r>>>1);
assign psg      = hatris ? opna_psg : jt10_psg;

always @* begin
    cpu_din = 8'hff;
    case( 1'b1 )
        ram_cs:   cpu_din = ram_dout;
        rom_cs:   cpu_din = rom_data;
        latch_rd: cpu_din = snd_latch;
        pend_rd:  cpu_din = { 7'd0, snd_pending };
        fm_cs:    cpu_din = fm_dout;
        opna_cs:  cpu_din = opna_dout;
        default:;
    endcase
end

always @(posedge clk) begin
    lvbl_l <= lvbl;
    if( rst ) begin
        bank        <= 0;
        snd_pending <= 0;
        crtc_irq    <= 0;
    end else begin
        if( bank_cs && !wr_n ) bank <= cpu_dout[0];
        if( latch_ack ) snd_pending <= 0;
        if( snd_wr ) snd_pending <= 1;      // a main CPU write wins over a simultaneous acknowledge
        if( !lvbl && lvbl_l && crtc_irq_en ) crtc_irq <= 1;
        if( !m1_n && !iorq_n ) crtc_irq <= 0;
    end
end

// jt10 only takes ADPCM-A start/end writes when the channel's slot passes (up to 9 us later); the driver does
// not poll BUSY, so hold the CPU for one rotation after every port B data write (see jtpspike_snd.v)
always @(posedge clk) begin
    if( rst ) begin
        busy_cnt <= 0;
        fmwr_l   <= 0;
    end else begin
        fmwr_l <= fm_wr;
        if( fmwr_l && !fm_wr && (hatris ? A[0] : A[1:0]==2'b11) )
            busy_cnt <= 7'd96;                       // 12 us at 8 MHz
        else if( fm_cen && busy_cnt!=0 )
            busy_cnt <= busy_cnt-7'd1;
    end
end

jtframe_z80_devwait u_cpu(
    .rst_n      ( ~rst & (~hatris | opna_ready) ),
    .clk        ( clk       ),
    .cen        ( cen       ),
    .cpu_cen    (           ),
    .int_n      ( (hatris ? opna_irq_n : ym_irq_n) & ~crtc_irq ),
    .nmi_n      ( ~snd_pending | hatris ),
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
    .din        ( cpu_din   ),
    .dout       ( cpu_dout  ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    ),
    .dev_busy   ( fm_busy   )
);

jtframe_ram #(.AW(11)) u_ram(
    .clk        ( clk       ),
    .cen        ( 1'b1      ),
    .addr       ( A[10:0]   ),
    .data       ( cpu_dout  ),
    .we         ( ram_cs & ~wr_n ),
    .q          ( ram_dout  )
);

assign pcma_cs   = hatris ? ~opna_aroe_n : ~adpcma_roe_n;
assign pcma_addr = hatris ? opna_aaddr[18:0] : adpcma_addr[18:0];
assign pcmb_cs   = hatris ? ~opna_broe_n : ~adpcmb_roe_n;
assign pcmb_addr = hatris ? opna_baddr[18:0] : adpcmb_addr[18:0];

jt10 u_jt10(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( fm_cen    ),
    .din        ( cpu_dout  ),
    .addr       ( A[1:0]    ),
    .cs_n       ( ~fm_cs    ),
    .wr_n       ( wr_n      ),
    .dout       ( fm_dout   ),
    .irq_n      ( ym_irq_n  ),

    .adpcma_addr ( adpcma_addr  ),
    .adpcma_bank ( adpcma_bank  ),
    .adpcma_roe_n( adpcma_roe_n ),
    .adpcma_data ( pcma_data    ),
    .adpcmb_addr ( adpcmb_addr  ),
    .adpcmb_roe_n( adpcmb_roe_n ),
    .adpcmb_data ( pcmb_data    ),

    .psg_A      (           ),
    .psg_B      (           ),
    .psg_C      (           ),
    .fm_left    ( fm_l      ),
    .fm_right   ( fm_r      ),
    .psg_snd    ( jt10_psg  ),
    .snd_right  (           ),
    .snd_left   (           ),
    .snd_sample (           ),
    .ch_enable  ( 6'h3f     )
);
jtpipedrm_opna u_opna(
    .rst          ( rst          ),
    .clk          ( clk          ),
    .cen          ( fm_cen       ),
    .din          ( cpu_dout     ),
    .addr         ( A[1:0]       ),
    .cs_n         ( ~opna_cs     ),
    .wr_n         ( wr_n         ),
    .dout         ( opna_dout    ),
    .irq_n        ( opna_irq_n   ),
    .ready        ( opna_ready   ),
    .adpcma_addr  ( opna_aaddr   ),
    .adpcma_bank  (              ),
    .adpcma_roe_n ( opna_aroe_n  ),
    .adpcma_data  ( pcma_data    ),
    .adpcmb_addr  ( opna_baddr   ),
    .adpcmb_roe_n ( opna_broe_n  ),
    .adpcmb_data  ( pcmb_data    ),
    .fm_left      ( opna_l       ),
    .fm_right     ( opna_r       ),
    .psg_snd      ( opna_psg     )
);
`else
initial snd_pending = 0;
assign rom_addr=0, rom_cs=0, pcma_addr=0, pcma_cs=0, pcmb_addr=0, pcmb_cs=0, fm=0, psg=0;
`endif
endmodule
