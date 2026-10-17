/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung YS-1300 / YS-2111 main board (MAME nmg5.cpp): 68000 at 16 MHz, IRQ 6 at vblank (hold).
 *   nmg5 map (pc=0)             pclubys map (pc=1)
 *   000000-0fffff ROM            same
 *   120000-12ffff RAM            200000-20ffff
 *   140000-1407ff palette        440000
 *   160000-1607ff sprites        460000
 *   180000-18000f I/O            480000: 01 sound latch (+ NMI), 04 protection (value | last 4 bits written),
 *                                         06 tile bank, 08 DSW, 0a SYSTEM, 0c INPUTS, 0e priority
 *   300002-300009 scroll         500002
 *   320000 / 322000 tile RAM     520000 / 522000
 *   800000-80ffff pixel layer (two 4-bit pixels per byte)
 * Built on JTFRAME by Jose Tejada (jotego). */

module jtnmg5_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,
    input              pc,
    input       [ 7:0] prot_val,

    input       [15:0] inputs, system, dipsw,

    output      [15:0] cpu_dout,
    output      [19:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [10:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [10:1] objram_addr,
    output      [ 1:0] objram_we,
    input       [15:0] objram_dout,
    output      [12:1] vram0_addr,
    output      [ 1:0] vram0_we,
    input       [15:0] vram0_dout,
    output      [12:1] vram1_addr,
    output      [ 1:0] vram1_we,
    input       [15:0] vram1_dout,
    output      [15:1] pix_addr,
    output      [ 1:0] pix_we,
    input       [15:0] pix_dout,

    output reg  [ 8:0] scr0x, scr0y, scr1x, scr1y,   // raw scroll RAM words 2, 3, 0, 1 (low 9 bits)
    output reg  [ 1:0] gfx_bank,
    output reg  [ 2:0] prio,
    output reg  [ 7:0] snd_latch,
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
reg  [ 3:0] prot_in;
reg         irq_n;
reg         wram_cs, pal_cs, objram_cs, io_cs, scr_cs, vram0_cs, vram1_cs, pix_cs;
wire [ 3:0] hi  = pc ? 4'h4 : 4'h1;
wire [ 3:0] vhi = pc ? 4'h5 : 4'h3;

assign dsn        = { uds_n, lds_n };
assign bus_n      = as_n | (lds_n & uds_n);
assign wen        = {2{~wr_n}} & ~dsn;
assign rom_addr   = A[19:1];
assign wram_addr  = A[15:1];
assign pal_addr   = A[10:1];
assign objram_addr= A[10:1];
assign vram0_addr = A[12:1];
assign vram1_addr = A[12:1];
assign pix_addr   = A[15:1];
assign wram_we    = wram_cs   ? wen : 2'b00;
assign pal_we     = pal_cs    ? wen : 2'b00;
assign objram_we  = objram_cs ? wen : 2'b00;
assign vram0_we   = vram0_cs  ? wen : 2'b00;
assign vram1_we   = vram1_cs  ? wen : 2'b00;
assign pix_we     = pix_cs    ? wen : 2'b00;
assign int_ack    = fc == 3'b111 && !as_n;
assign vpa_n      = !int_ack;
assign ipl_n      = irq_n ? 3'b111 : 3'b001;     // level 6
assign bus_busy   = rom_cs && !rom_ok;

always @* begin
    rom_cs = 0; wram_cs = 0; pal_cs = 0; objram_cs = 0; io_cs = 0; scr_cs = 0; vram0_cs = 0; vram1_cs = 0; pix_cs = 0;
    if( !bus_n ) begin
        rom_cs    = A[23:20] == 0;
        wram_cs   = A[23:16] == (pc ? 8'h20 : 8'h12);
        pal_cs    = A[23:20] == hi && A[19:16] == 4'h4 && A[15:11] == 0;
        objram_cs = A[23:20] == hi && A[19:16] == 4'h6 && A[15:11] == 0;
        io_cs     = A[23:20] == hi && A[19:16] == 4'h8 && A[15:4]  == 0;
        scr_cs    = A[23:20] == vhi && A[19:4] == 16'h0000;
        vram0_cs  = A[23:20] == vhi && A[19:13] == 7'b0010_000;    // x20000-x21fff
        vram1_cs  = A[23:20] == vhi && A[19:13] == 7'b0010_001;    // x22000-x23fff
        pix_cs    = A[23:16] == 8'h80;
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs    ? rom_data    :
               wram_cs   ? wram_dout   :
               pal_cs    ? pal_dout    :
               objram_cs ? objram_dout :
               vram0_cs  ? vram0_dout  :
               vram1_cs  ? vram1_dout  :
               pix_cs    ? pix_dout    :
               io_cs     ? ( A[3:1]==2 ? { 8'h00, prot_val | { 4'd0, prot_in } } :
                             A[3:1]==4 ? dipsw  :
                             A[3:1]==5 ? system :
                             A[3:1]==6 ? inputs : 16'hffff ) :
               16'hffff;
end

reg wr_l;
always @(posedge clk) begin
    snd_wr <= 0;
    wr_l   <= io_cs && !wr_n;
    if( rst ) begin
        scr0x <= 0; scr0y <= 0; scr1x <= 0; scr1y <= 0;
        gfx_bank <= 0; prio <= 7; prot_in <= 0; snd_latch <= 0;
    end else begin
        if( scr_cs && !wr_n ) case( A[3:1] )
            1: scr1x <= cpu_dout[8:0];
            2: scr1y <= cpu_dout[8:0];
            3: scr0x <= cpu_dout[8:0];
            4: scr0y <= cpu_dout[8:0];
            default:;
        endcase
        if( io_cs && !wr_n && !wr_l ) case( A[3:1] )
            0: if( !lds_n ) begin snd_latch <= cpu_dout[7:0]; snd_wr <= 1; end
            2: prot_in  <= cpu_dout[3:0];
            3: gfx_bank <= cpu_dout[1:0];
            7: prio     <= cpu_dout[2:0];
            default:;
        endcase
    end
end

`ifdef SIMULATION
reg [15:0] dbg_cnt=0; reg as_l=1;
always @(posedge clk) begin
    as_l <= as_n;
    if( !as_n && as_l ) begin
        dbg_cnt <= dbg_cnt + 1'd1;
        if( io_cs && !wr_n && A[3:1]!=0 && A[3:1]!=2 )
            $display("68k %06X %s fc=%d dout=%04X", {A,1'b0}, wr_n ? "R" : "W", fc, cpu_dout);
    end
end
`endif

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

// 16 MHz from 48 MHz
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
    .den       ( 5'd3     ),
    .DTACKn    ( dtack_n  ),
    .wait2     ( 1'b0     ),
    .wait3     ( 1'b0     ),
    .fave      (          ),
    .fworst    (          )
);
`else
initial begin rom_cs=0; scr0x=0; scr0y=0; scr1x=0; scr1y=0; gfx_bank=0; prio=7; snd_latch=0; snd_wr=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, pal_addr=0, pal_we=0, objram_addr=0, objram_we=0,
       vram0_addr=0, vram0_we=0, vram1_addr=0, vram1_we=0, pix_addr=0, pix_we=0;
`endif

endmodule
