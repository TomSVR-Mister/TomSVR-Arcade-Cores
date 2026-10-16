/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Gaelco Splash! main board (MAME splash.cpp, splash config): 68000 at 12 MHz, IRQ 6 at vblank (hold).
 *   000000-3fffff ROM          800000-83ffff pixel layer (low byte)   840000-840007 DSW1, DSW2, P1, P2
 *   84000a coin latch (ignored) 84000f sound latch                    880000-8817ff video RAM
 *   881800-881803 scroll Y      881804-881fff RAM                      8c0000-8c0fff palette
 *   900000-900fff sprites       ffc000-ffffff RAM
 * Built on JTFRAME by Jose Tejada (jotego). */

module jtsplash_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,

    input       [ 7:0] p1, p2,
    input       [15:0] dipsw,

    output      [15:0] cpu_dout,
    // SDRAM ROM
    output      [21:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    // BRAM
    output      [13:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [12:1] vram_addr,
    output      [ 1:0] vram_we,
    input       [15:0] vram_dout,
    output      [11:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [11:1] objram_addr,
    output      [ 1:0] objram_we,
    input       [15:0] objram_dout,
    output      [17:1] pix_addr,
    output             pix_we,
    input       [ 7:0] pix_dout,
    // video registers
    output reg  [15:0] scr0, scr1,
    // sound latch
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
reg         wram_cs, vram_cs, pal_cs, objram_cs, pix_cs, io_cs;
wire        io_wr = io_cs && !wr_n;

assign dsn        = { uds_n, lds_n };
assign bus_n      = as_n | (lds_n & uds_n);
assign wen        = {2{~wr_n}} & ~dsn;
assign rom_addr   = A[21:1];
assign wram_addr  = A[13:1];
assign vram_addr  = A[12:1];
assign pal_addr   = A[11:1];
assign objram_addr= A[11:1];
assign pix_addr   = A[17:1];
assign wram_we    = wram_cs   ? wen : 2'b00;
assign vram_we    = vram_cs   ? wen : 2'b00;
assign pal_we     = pal_cs    ? wen : 2'b00;
assign objram_we  = objram_cs ? wen : 2'b00;
assign pix_we     = pix_cs && wen[0];
assign int_ack    = fc == 3'b111 && !as_n;
assign vpa_n      = !int_ack;
assign ipl_n      = irq_n ? 3'b111 : 3'b001;     // level 6
assign bus_busy   = rom_cs && !rom_ok;

always @* begin
    rom_cs    = 0;
    pix_cs    = 0;
    io_cs     = 0;
    vram_cs   = 0;
    pal_cs    = 0;
    objram_cs = 0;
    wram_cs   = 0;
    if( !bus_n ) begin
        rom_cs    = A[23:22] == 0;                  // 000000-3fffff
        pix_cs    = A[23:18] == 6'b1000_00;         // 800000-83ffff
        io_cs     = A[23:4]  == 20'h84000;          // 840000-84000f
        vram_cs   = A[23:13] == 11'h440;            // 880000-881fff
        pal_cs    = A[23:12] == 12'h8c0;            // 8c0000-8c0fff
        objram_cs = A[23:12] == 12'h900;            // 900000-900fff
        wram_cs   = A[23:14] == 10'h3ff;            // ffc000-ffffff
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs    ? rom_data    :
               pix_cs    ? { 8'hff, pix_dout } :
               vram_cs   ? vram_dout   :
               pal_cs    ? pal_dout    :
               objram_cs ? objram_dout :
               wram_cs   ? wram_dout   :
               io_cs     ? ( A[3:1]==0 ? { 8'hff, dipsw[ 7:0] } :
                             A[3:1]==1 ? { 8'hff, dipsw[15:8] } :
                             A[3:1]==2 ? { 8'hff, p1 } :
                             A[3:1]==3 ? { 8'hff, p2 } : 16'hffff ) :
               16'h0000;
end

// scroll registers (881800, 881802) and sound latch (84000f)
always @(posedge clk) begin
    snd_wr <= 0;
    if( rst ) begin
        scr0 <= 0; scr1 <= 0;
    end else begin
        if( vram_cs && !wr_n && A[12:1]==12'hc00 ) begin
            if( !uds_n ) scr0[15:8] <= cpu_dout[15:8];
            if( !lds_n ) scr0[ 7:0] <= cpu_dout[ 7:0];
        end
        if( vram_cs && !wr_n && A[12:1]==12'hc01 ) begin
            if( !uds_n ) scr1[15:8] <= cpu_dout[15:8];
            if( !lds_n ) scr1[ 7:0] <= cpu_dout[ 7:0];
        end
        if( io_wr && A[3:1]==7 && !lds_n ) snd_wr <= 1;
    end
end

// IRQ 6 asserted at the start of vblank, cleared on acknowledge
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
initial begin rom_cs=0; scr0=0; scr1=0; snd_wr=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, vram_addr=0, vram_we=0, pal_addr=0, pal_we=0,
       objram_addr=0, objram_we=0, pix_addr=0, pix_we=0;
`endif

endmodule
