/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Honey Doll main board (MAME snowbros.cpp honeydol_map): 68000 at 12 MHz.
 *   000000-03ffff ROM   100000-10ffff RAM   300001 sound latch   400000/500000/600000 IRQ 4/3/2 acknowledge
 *   900000 DSW1 + P1 (bit 15 vblank)   900002 DSW2 + P2   900004 SYSTEM   a00000-a007ff palette   b00000-b01fff sprites
 * IRQ 4 at line 32, IRQ 3 at line 128, IRQ 2 at line 240, each held until its acknowledge write. */

module jthdoll_main(
    input              rst,
    input              clk,
    input       [ 8:0] vdump,
    input              hs_start,
    input              lvbl,
    input              dip_pause,

    input       [15:0] in1, in2, sys,

    output      [15:0] cpu_dout,
    output      [17:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [10:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [12:1] oram_addr,
    output      [ 1:0] oram_we,
    input       [15:0] oram_dout,

    output reg  [ 7:0] snd_latch,
    output reg         snd_wr
);

`ifndef NOMAIN
wire [23:1] A;
wire [ 2:0] fc;
wire        as_n, lds_n, uds_n, wr_n, dtack_n, vpa_n, bus_n;
wire        cpu_cen, cpu_cenb, int_ack, bus_busy;
wire [ 1:0] dsn, wen;
reg  [ 2:0] ipl_n;
reg  [15:0] cpu_din;
reg         wram_cs, pal_cs, oram_cs, io_cs, lat_cs, ack_cs;
reg         irq2, irq3, irq4, wr_l;
wire [ 3:0] pg = A[23:20];

assign dsn       = { uds_n, lds_n };
assign bus_n     = as_n | (lds_n & uds_n);
assign wen       = {2{~wr_n}} & ~dsn;
assign rom_addr  = A[17:1];
assign wram_addr = A[15:1];
assign pal_addr  = A[10:1];
assign oram_addr = A[12:1];
assign wram_we   = wram_cs ? wen : 2'b00;
assign pal_we    = pal_cs  ? wen : 2'b00;
assign oram_we   = oram_cs ? wen : 2'b00;
assign int_ack   = fc == 3'b111 && !as_n;
assign vpa_n     = !int_ack;
assign bus_busy  = rom_cs && !rom_ok;

always @* begin
    rom_cs = 0; wram_cs = 0; pal_cs = 0; oram_cs = 0; io_cs = 0; lat_cs = 0; ack_cs = 0;
    if( !bus_n ) begin
        rom_cs  = pg == 4'h0 && A[19:18] == 0;
        wram_cs = pg == 4'h1 && A[19:16] == 0;
        lat_cs  = pg == 4'h3;
        ack_cs  = pg == 4'h4 || pg == 4'h5 || pg == 4'h6;
        io_cs   = pg == 4'h9;
        pal_cs  = pg == 4'ha && A[19:11] == 0;
        oram_cs = pg == 4'hb && A[19:13] == 0;
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs  ? rom_data  :
               wram_cs ? wram_dout :
               pal_cs  ? pal_dout  :
               oram_cs ? oram_dout :
               io_cs   ? ( A[2:1]==0 ? in1 : A[2:1]==1 ? in2 : sys ) :
               16'd0;
end

always @(posedge clk) begin
    snd_wr <= 0;
    wr_l   <= !wr_n && !bus_n;
    if( rst ) begin
        irq2 <= 0; irq3 <= 0; irq4 <= 0; snd_latch <= 0;
    end else begin
        if( hs_start && dip_pause ) begin
            if( vdump == 9'd32  ) irq4 <= 1;
            if( vdump == 9'd128 ) irq3 <= 1;
            if( vdump == 9'd240 ) irq2 <= 1;
        end
        if( ack_cs && !wr_n ) case( pg )
            4'h4: irq4 <= 0;
            4'h5: irq3 <= 0;
            default: irq2 <= 0;
        endcase
        if( lat_cs && !wr_n && !wr_l && !lds_n ) begin
            snd_latch <= cpu_dout[7:0];
            snd_wr    <= 1;
        end
    end
    ipl_n <= irq4 ? 3'b011 : irq3 ? 3'b100 : irq2 ? 3'b101 : 3'b111;
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
initial begin rom_cs=0; snd_latch=0; snd_wr=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, pal_addr=0, pal_we=0, oram_addr=0, oram_we=0;
`endif

endmodule
