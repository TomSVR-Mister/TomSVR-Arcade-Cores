/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * VISYS main board (MAME oneshot.cpp, maddonna map): 68000 at 12 MHz, IRQ 4 at vblank (hold).
 *   000000-03ffff ROM     080000-087fff RAM      0c0000-0c07ff palette   120000-120fff sprites
 *   180000 mid, 181000 fg, 182000 bg video RAM   188000-18800f scroll (only scroll[1] = mid Y is used)
 *   190003 sound latch read, 190011 sound latch write, 190019 OKI bank (no samples on these games)
 *   19c020 DSW1, 19c024 DSW2, 19c02c credits, 19c030 P1, 19c034 P2 (active high)
 * Built on JTFRAME by Jose Tejada (jotego). */

module jtmadd_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,

    input       [ 7:0] p1, p2, credits,
    input       [15:0] dipsw,

    output      [15:0] cpu_dout,
    output      [17:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    output      [14:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [10:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [11:1] objram_addr,
    output      [ 1:0] objram_we,
    input       [15:0] objram_dout,
    output      [11:1] vmid_addr,
    output      [ 1:0] vmid_we,
    input       [15:0] vmid_dout,
    output      [11:1] vfg_addr,
    output      [ 1:0] vfg_we,
    input       [15:0] vfg_dout,
    output      [11:1] vbg_addr,
    output      [ 1:0] vbg_we,
    input       [15:0] vbg_dout,

    output reg  [15:0] scroll1,
    input       [ 7:0] snd_latch,
    output reg         snd_wr
);

`ifndef NOMAIN
wire [23:1] A;
wire [ 2:0] fc;
wire        as_n, lds_n, uds_n, wr_n, dtack_n, vpa_n, bus_n;
wire        cpu_cen, cpu_cenb, int_ack, bus_busy;
wire [ 1:0] dsn, wen;
wire [ 2:0] ipl_n;
reg  [15:0] cpu_din;
reg         irq_n;
reg         wram_cs, pal_cs, objram_cs, vmid_cs, vfg_cs, vbg_cs, scr_cs, snd_cs, io_cs;

assign dsn        = { uds_n, lds_n };
assign bus_n      = as_n | (lds_n & uds_n);
assign wen        = {2{~wr_n}} & ~dsn;
assign rom_addr   = A[17:1];
assign wram_addr  = A[14:1];
assign pal_addr   = A[10:1];
assign objram_addr= A[11:1];
assign vmid_addr  = A[11:1];
assign vfg_addr   = A[11:1];
assign vbg_addr   = A[11:1];
assign wram_we    = wram_cs   ? wen : 2'b00;
assign pal_we     = pal_cs    ? wen : 2'b00;
assign objram_we  = objram_cs ? wen : 2'b00;
assign vmid_we    = vmid_cs   ? wen : 2'b00;
assign vfg_we     = vfg_cs    ? wen : 2'b00;
assign vbg_we     = vbg_cs    ? wen : 2'b00;
assign int_ack    = fc == 3'b111 && !as_n;
assign vpa_n      = !int_ack;
assign ipl_n      = irq_n ? 3'b111 : 3'b011;     // level 4
assign bus_busy   = rom_cs && !rom_ok;

always @* begin
    rom_cs    = 0; wram_cs = 0; pal_cs = 0; objram_cs = 0;
    vmid_cs   = 0; vfg_cs  = 0; vbg_cs = 0; scr_cs    = 0; snd_cs = 0; io_cs = 0;
    if( !bus_n ) begin
        rom_cs    = A[23:18] == 0;                  // 000000-03ffff
        wram_cs   = A[23:15] == 9'h010;             // 080000-087fff
        pal_cs    = A[23:11] == 13'h0180;           // 0c0000-0c07ff
        objram_cs = A[23:12] == 12'h120;            // 120000-120fff
        vmid_cs   = A[23:12] == 12'h180;
        vfg_cs    = A[23:12] == 12'h181;
        vbg_cs    = A[23:12] == 12'h182;
        scr_cs    = A[23:12] == 12'h188;
        snd_cs    = A[23:12] == 12'h190;
        io_cs     = A[23:12] == 12'h19c;
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs    ? rom_data    :
               wram_cs   ? wram_dout   :
               pal_cs    ? pal_dout    :
               objram_cs ? objram_dout :
               vmid_cs   ? vmid_dout   :
               vfg_cs    ? vfg_dout    :
               vbg_cs    ? vbg_dout    :
               snd_cs    ? ( A[7:1]==7'h01 ? { 8'hff, snd_latch } : 16'h0000 ) :
               io_cs     ? ( A[7:1]==7'h10 ? { 8'h00, dipsw[ 7:0] } :
                             A[7:1]==7'h12 ? { 8'h00, dipsw[15:8] } :
                             A[7:1]==7'h16 ? { 8'h00, credits } :
                             A[7:1]==7'h18 ? { 8'h00, p1 } :
                             A[7:1]==7'h1a ? { 8'h00, p2 } : 16'h0000 ) :
               16'h0000;
end

reg wr_l;
always @(posedge clk) begin
    snd_wr <= 0;
    wr_l   <= !bus_n && !wr_n;
    if( rst ) begin
        scroll1 <= 0;
    end else begin
        if( scr_cs && !wr_n && A[3:1]==1 ) begin
            if( !uds_n ) scroll1[15:8] <= cpu_dout[15:8];
            if( !lds_n ) scroll1[ 7:0] <= cpu_dout[ 7:0];
        end
        if( snd_cs && !wr_n && !wr_l && A[7:1]==7'h08 && !lds_n ) snd_wr <= 1;
    end
end

// IRQ 4 asserted at the start of vblank, cleared on acknowledge
reg lvbl_l;
always @(posedge clk) begin
    lvbl_l <= lvbl;
    if( rst ) irq_n <= 1;
    else begin
        if( !lvbl && lvbl_l ) irq_n <= 0;
        if( int_ack ) irq_n <= 1;
    end
end

jtframe_m68k u_cpu(
    .clk     ( clk       ),
    .rst     ( rst       ),
    .cpu_cen ( cpu_cen   ),
    .cpu_cenb( cpu_cenb  ),
    .BERRn   ( 1'b1      ),
    .VPAn    ( vpa_n     ),
    .BGACKn  ( 1'b1      ),
    .HALTn   ( dip_pause ),
    .RESETn  (           ),
    .eab     ( A         ),
    .ASn     ( as_n      ),
    .LDSn    ( lds_n     ),
    .UDSn    ( uds_n     ),
    .eRWn    ( wr_n      ),
    .DTACKn  ( dtack_n   ),
    .iEdb    ( cpu_din   ),
    .oEdb    ( cpu_dout  ),
    .BRn     ( 1'b1      ),
    .BGn     (           ),
    .IPLn    ( ipl_n     ),
    .FC      ( fc        )
);

// 12 MHz from 48 MHz
jtframe_68kdtack_cen u_dtack(
    .rst       ( rst      ),
    .clk       ( clk      ),
    .cpu_cen   ( cpu_cen  ),
    .cpu_cenb  ( cpu_cenb ),
    .bus_cs    ( rom_cs   ),
    .bus_busy  ( bus_busy ),
    .bus_legit ( 1'b0     ),
    .bus_ack   ( 1'b0     ),
    .ASn       ( as_n     ),
    .DSn       ( dsn      ),
    .num       ( 4'd1     ),
    .den       ( 5'd4     ),
    .DTACKn    ( dtack_n  ),
    .wait2     ( 1'b0     ),
    .wait3     ( 1'b0     ),
    .fave      (          ),
    .fworst    (          )
);
`else
initial begin rom_cs=0; scroll1=0; snd_wr=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, pal_addr=0, pal_we=0, objram_addr=0, objram_we=0,
       vmid_addr=0, vmid_we=0, vfg_addr=0, vfg_we=0, vbg_addr=0, vbg_we=0;
`endif

endmodule
