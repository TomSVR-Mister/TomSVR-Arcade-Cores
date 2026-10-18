/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Afega main board (MAME nmk16.cpp afega_map, "popspops" machine): 68000 at 12 MHz, 20-bit address bus.
 *   000000-07ffff ROM (address lines scrambled, see scr)   080000 IN0   080002 IN1   080004 DSW (both banks)
 *   080012 reads 0x0100   08001f sound latch   084000/08c000 scroll registers (0-3: bg y/x, 4-7: text y/x)
 *   088000-0885ff palette   090000-093fff bg video RAM   09c000-09c7ff text video RAM   0c0000-0cffff work RAM (mirror 0f0000)
 * Interrupts (held until acknowledged): IRQ 4 at line 240, IRQ 2 at line 0, IRQ 1 at lines 25 and 153.
 * scr: 1 = Bubble 2000 / Hot Bubble / Mang-Chi (CPU A13<->A17, A14<->A16), 2 = Pop's Pop's (A16<->A17, A14<->A15). */

module jtafega_main(
    input              rst,
    input              clk,
    input       [ 8:0] vdump,
    input              hs_start,    // first clock of a line
    input              dip_pause,
    input       [ 1:0] scr,

    input       [15:0] in0, in1, dsw,

    output      [15:0] cpu_dout,
    output      [18:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [10:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [13:1] bgram_addr,
    output      [ 1:0] bgram_we,
    input       [15:0] bgram_dout,
    output      [10:1] txram_addr,
    output      [ 1:0] txram_we,
    input       [15:0] txram_dout,

    output reg  [15:0] bg_scry, bg_scrx, tx_scry, tx_scrx,
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
reg         wram_cs, pal_cs, bg_cs, tx_cs, io_cs, scr_cs;
reg         irq1, irq2, irq4;
wire [ 7:0] pg = A[19:12];

assign dsn        = { uds_n, lds_n };
assign bus_n      = as_n | (lds_n & uds_n);
assign wen        = {2{~wr_n}} & ~dsn;
assign rom_addr   = scr==1 ? { A[18], A[13], A[14], A[15], A[16], A[17], A[12:1] } :
                    scr==2 ? { A[18], A[16], A[17], A[14], A[15], A[13:1] } : A[18:1];
assign wram_addr  = A[15:1];
assign pal_addr   = A[10:1];
assign bgram_addr = A[13:1];
assign txram_addr = A[10:1];
assign wram_we    = wram_cs ? wen : 2'b00;
assign pal_we     = pal_cs  ? wen : 2'b00;
assign bgram_we   = bg_cs   ? wen : 2'b00;
assign txram_we   = tx_cs   ? wen : 2'b00;
assign int_ack    = fc == 3'b111 && !as_n;
assign vpa_n      = !int_ack;
assign bus_busy   = rom_cs && !rom_ok;

always @* begin
    rom_cs = 0; wram_cs = 0; pal_cs = 0; bg_cs = 0; tx_cs = 0; io_cs = 0; scr_cs = 0;
    if( !bus_n ) begin
        rom_cs  = !A[19];
        io_cs   = pg == 8'h80 && A[11:5] == 0;
        scr_cs  = (pg == 8'h84 || pg == 8'h8c) && A[11:3] == 0;          // 4 words
        pal_cs  = pg == 8'h88 && A[11] == 0;
        bg_cs   = A[19:14] == 6'b1001_00;               // 090000-093fff
        tx_cs   = pg == 8'h9c && A[11] == 0;
        wram_cs = A[19:16] == 4'hc || A[19:16] == 4'hf;
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs  ? rom_data   :
               wram_cs ? wram_dout  :
               pal_cs  ? pal_dout   :
               bg_cs   ? bgram_dout :
               tx_cs   ? txram_dout :
               scr_cs  ? (A[2:1]==0 ? bg_scry : A[2:1]==1 ? bg_scrx : A[2:1]==2 ? tx_scry : tx_scrx) :
               io_cs   ? ( A[4:1]==0 ? in0 : A[4:1]==1 ? in1 : A[4:1]==2 ? dsw : A[4:1]==9 ? 16'h0100 : 16'd0 ) :
               16'd0;
end

reg wr_l;
always @(posedge clk) begin
    snd_wr <= 0;
    wr_l   <= io_cs && !wr_n;
    if( rst ) begin
        bg_scrx <= 0; bg_scry <= 0; tx_scrx <= 0; tx_scry <= 0; snd_latch <= 0;
    end else begin
        if( scr_cs && !wr_n ) case( A[2:1] )   // set 0: bg y, x  set 1: text y, x
            2'b00: begin if(!uds_n) bg_scry[15:8] <= cpu_dout[15:8]; if(!lds_n) bg_scry[7:0] <= cpu_dout[7:0]; end
            2'b01: begin if(!uds_n) bg_scrx[15:8] <= cpu_dout[15:8]; if(!lds_n) bg_scrx[7:0] <= cpu_dout[7:0]; end
            2'b10: begin if(!uds_n) tx_scry[15:8] <= cpu_dout[15:8]; if(!lds_n) tx_scry[7:0] <= cpu_dout[7:0]; end
            2'b11: begin if(!uds_n) tx_scrx[15:8] <= cpu_dout[15:8]; if(!lds_n) tx_scrx[7:0] <= cpu_dout[7:0]; end
        endcase
        if( io_cs && !wr_n && !wr_l && A[4:1]==4'hf && !lds_n ) begin
            snd_latch <= cpu_dout[7:0];
            snd_wr    <= 1;
        end
    end
end

// interrupts, cleared by the acknowledge cycle of their level
always @(posedge clk) begin
    if( rst ) begin
        irq1 <= 0; irq2 <= 0; irq4 <= 0;
    end else begin
        if( hs_start && dip_pause ) begin
            if( vdump == 9'd240 ) irq4 <= 1;
            if( vdump == 9'd0   ) irq2 <= 1;
            if( vdump == 9'd25 || vdump == 9'd153 ) irq1 <= 1;
        end
        if( int_ack ) case( A[3:1] )
            3'd1: irq1 <= 0;
            3'd2: irq2 <= 0;
            3'd4: irq4 <= 0;
            default:;
        endcase
    end
    ipl_n <= irq4 ? 3'b011 : irq2 ? 3'b101 : irq1 ? 3'b110 : 3'b111;
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
initial begin rom_cs=0; bg_scrx=0; bg_scry=0; tx_scrx=0; tx_scry=0; snd_latch=0; snd_wr=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, pal_addr=0, pal_we=0, bgram_addr=0, bgram_we=0,
       txram_addr=0, txram_we=0;
`endif

endmodule
