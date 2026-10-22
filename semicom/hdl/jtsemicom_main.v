/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SemiCom main board (MAME snowbros.cpp hyperpac_map): 68000 at 12 MHz.
 *   000000-07ffff ROM   100000-10ffff RAM   200000 game-specific read (3in1semi family 000a, cookbib3 2a2a)
 *   300001 sound latch   500000 DSW1 + P1   500002 DSW2 + P2   500004 SYSTEM   600000-6001ff palette
 *   700000-701fff Pandora sprite RAM (one byte per word, read back on both halves)
 *   800000/900000/a00000 IRQ 4/3/2 acknowledge
 * IRQ 4 at line 32, IRQ 3 at line 128, IRQ 2 at line 240, each held until its acknowledge write.
 * Protection: the MCU leaves 0x200 bytes of code/data in RAM. MAME (machine reset "semiprot") copies its dump
 * (user1/protdata.bin) to RAM 10f000 (Final Tetris: 102000); here the CPU stays in reset while the copy runs. */

module jtsemicom_main(
    input              rst,
    input              clk,
    input       [ 8:0] vdump,
    input              hs_start,
    input              dip_pause,
    input       [ 1:0] r200,        // 0x200000 read: 0 = 0, 1 = 000a, 2 = 2a2a
    input              pbase,       // protection data at 102000 instead of 10f000
    input              ocopy,       // the video is copying the sprite RAM: sprite RAM accesses wait
    input              mbase,       // MCU writes go to 10e000 (Hyper Pacman) instead of 10f000
    input              mcu_req,     // MCU word write to RAM
    input       [ 7:0] mcu_off,
    input       [15:0] mcu_data,

    input       [15:0] in1, in2, sys,

    output      [15:0] cpu_dout,
    output      [18:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    output      [15:0] wram_din,
    input       [15:0] wram_dout,
    output      [ 8:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [11:0] oram_addr,
    output             oram_we,
    output      [ 7:0] oram_din,
    input       [ 7:0] oram_dout,

    // protection data (PROM)
    output      [ 7:0] prot_addr,
    input       [15:0] prot_data,

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
reg         wram_cs, pal_cs, oram_cs, io_cs, lat_cs, ack_cs, r2_cs;
reg         irq2, irq3, irq4, wr_l;
reg  [ 8:0] pcnt;               // protection copy: word counter, bit 8 = done
reg  [ 7:0] pwa;                // write address (PROM data comes one clock after its address)
reg         pwv, prst;
wire        copying = pwv;
reg         mpend;              // MCU write waiting for a clock without a CPU RAM access
reg  [ 7:0] moff;
reg  [15:0] mdata;
wire        mwr = mpend && !copying && !wram_cs;
wire [ 3:0] pg = A[23:20];

assign dsn       = { uds_n, lds_n };
assign bus_n     = as_n | (lds_n & uds_n);
assign wen       = {2{~wr_n}} & ~dsn;
assign rom_addr  = A[18:1];
assign prot_addr = pcnt[7:0];
assign wram_addr = copying ? { pbase ? 4'h2 : 4'hf, 3'd0, pwa } : mwr ? { mbase ? 4'he : 4'hf, 3'd0, moff } : A[15:1];
assign wram_din  = copying ? prot_data : mwr ? mdata : cpu_dout;
assign wram_we   = copying || mwr ? 2'b11 : wram_cs ? wen : 2'b00;
assign pal_addr  = A[8:1];
assign pal_we    = pal_cs  ? wen : 2'b00;
assign oram_addr = A[12:1];
assign oram_we   = oram_cs && !wr_n && !ocopy;
assign oram_din  = lds_n ? cpu_dout[15:8] : cpu_dout[7:0];
assign int_ack   = fc == 3'b111 && !as_n;
assign vpa_n     = !int_ack;
assign bus_busy  = (rom_cs && !rom_ok) || (oram_cs && ocopy);

always @(posedge clk) begin
    if( rst ) mpend <= 0;
    else begin
        if( mcu_req ) begin mpend <= 1; moff <= mcu_off; mdata <= mcu_data; end
        else if( mwr ) mpend <= 0;
    end
end

// the protection copy starts when reset ends (the prot BRAM keeps its data, so a reset copies again, like MAME)
always @(posedge clk) begin
    if( rst ) begin
        pcnt <= 0;
        pwv  <= 0;
        prst <= 1;
    end else begin
        if( !pcnt[8] ) pcnt <= pcnt + 1'd1;
        pwa  <= pcnt[7:0];
        pwv  <= !pcnt[8];
        prst <= !pcnt[8] || pwv;
    end
end

always @* begin
    rom_cs = 0; wram_cs = 0; pal_cs = 0; oram_cs = 0; io_cs = 0; lat_cs = 0; ack_cs = 0; r2_cs = 0;
    if( !bus_n ) begin
        rom_cs  = pg == 4'h0 && !A[19];
        wram_cs = pg == 4'h1;
        r2_cs   = pg == 4'h2;
        lat_cs  = pg == 4'h3;
        io_cs   = pg == 4'h5;
        pal_cs  = pg == 4'h6 && A[19:9] == 0;
        oram_cs = pg == 4'h7 && A[19:13] == 0;
        ack_cs  = pg == 4'h8 || pg == 4'h9 || pg == 4'ha;
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs  ? rom_data  :
               wram_cs ? wram_dout :
               pal_cs  ? pal_dout  :
               oram_cs ? { oram_dout, oram_dout } :
               io_cs   ? ( A[2:1]==0 ? in1 : A[2:1]==1 ? in2 : sys ) :
               r2_cs   ? ( r200==1 ? 16'h000a : r200==2 ? 16'h2a2a : 16'h0 ) :
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
            4'h8: irq4 <= 0;
            4'h9: irq3 <= 0;
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
    .rst     ( prst      ),
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
    .rst       ( prst     ),
    .clk       ( clk      ),
    .cpu_cen   ( cpu_cen  ),
    .cpu_cenb  ( cpu_cenb ),
    .bus_cs    ( rom_cs | oram_cs ),
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
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, wram_din=0, pal_addr=0, pal_we=0,
       oram_addr=0, oram_we=0, oram_din=0, prot_addr=0;
`endif

endmodule
