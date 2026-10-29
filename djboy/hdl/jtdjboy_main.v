/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DJ Boy / Air Buster main CPU (MAME kaneko/djboy.cpp maincpu_am, kaneko/airbustr.cpp main_map): Z80 at 6 MHz, IM 2.
 * Two interrupts, each held until acknowledged: MAME line 240 (djboy vector fd, airbustr ff) and line 64 (djboy ff,
 * airbustr fd). The Pandora sprite RAM is 8-bit with its address lines swapped (kan_pand.cpp spriteram_w).
 *   DJ Boy:    0000-afff ROM   b000-bfff sprite RAM   c000-dfff ROM bank (8 kB pages, port 00 ^ bankxor)
 *              e000-ffff RAM shared with the sub CPU. NMI from the sub CPU (its port 0a).
 *   Air Buster: 0000-7fff ROM  8000-bfff ROM bank (16 kB pages, port 00)  c000-cfff sprite RAM  d000-efff RAM
 *              (efe0-eff5 = Kaneko CALC1 on the original boards)  f000-ffff RAM shared with the sub CPU.
 *              Port 02 pulses the sub CPU NMI. */
module jtdjboy_main(
    input              rst,
    input              clk,
    input              cen,
    input              abus,        // Air Buster board
    input              bankxor,     // djboyj / djboyja: bank number ^ 1f
    input              calc_en,     // CALC1 present (airbustr, airbustrj)
    input              irq_vb,      // line 240 pulse
    input              irq_64,      // line 64 pulse
    input              nmi,         // pulse from the sub CPU (DJ Boy)
    output reg         sub_nmi,     // pulse to the sub CPU (Air Buster)
    output             wdog,        // CALC1 register 0 read: watchdog kick (kaneko_hit.cpp type 0)
    output      [ 7:0] cpu_dout,
    // ROM
    output      [17:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    // sprite RAM
    output      [11:0] oram_addr,
    output             oram_we,
    input       [ 7:0] oram_dout,
    input              ocopy,
    // RAM shared with the sub CPU
    output      [12:0] sh_addr,
    output             sh_we,
    input       [ 7:0] sh_dout
);

wire [15:0] A;
wire [ 7:0] ram_dout, calc_dout;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg  [ 7:0] din, vector;
reg  [ 4:0] bank;
reg         obj_cs, sh_cs, ram_cs, calc_cs, irq, iow_l, rstn;
reg  [ 3:0] nmi_cnt;
wire        mem   = !mreq_n && rfsh_n;
wire        io    = !iorq_n && m1_n;
wire        iow   = io && !wr_n && !iow_l;
wire        inta  = !iorq_n && !m1_n;

assign rom_addr  = abus ? ( A[15] ? { 1'b0, bank[2:0], A[13:0] } : { 3'd0, A[14:0] } ) :
                          ( A[15:13]==3'b110 ? { bank, A[12:0] } : { 2'd0, A } );
assign oram_addr = { A[11], A[7:0], A[10:8] };   // c000 / b000 window, 4 kB
assign oram_we   = obj_cs && !wr_n;
assign sh_addr   = abus ? { 1'b0, A[11:0] } : A[12:0];
assign sh_we     = sh_cs && !wr_n;
assign wdog      = calc_cs && !rd_n && A[4:1]==0;

always @(posedge clk) rstn <= ~rst;

always @* begin
    if( abus ) begin
        rom_cs  = mem && A[15:14]!=2'b11;
        obj_cs  = mem && A[15:12]==4'hc;
        ram_cs  = mem && (A[15:12]==4'hd || A[15:12]==4'he);
        calc_cs = ram_cs && calc_en && A[15:5]==11'b1110_1111_111 && A[4:0] <= 5'h15;
        sh_cs   = mem && A[15:12]==4'hf;
    end else begin
        rom_cs  = mem && (A < 16'hb000 || A[15:13]==3'b110);
        obj_cs  = mem && A[15:12]==4'hb;
        ram_cs  = 0;
        calc_cs = 0;
        sh_cs   = mem && A[15:13]==3'b111;
    end
end

always @(posedge clk) begin
    din <= inta    ? vector    :
           rom_cs  ? rom_data  :
           obj_cs  ? oram_dout :
           calc_cs ? calc_dout :
           ram_cs  ? ram_dout  :
           sh_cs   ? sh_dout   : 8'hff;
end

always @(posedge clk) begin
    iow_l <= io && !wr_n;
    if( rst ) begin
        bank <= 0; irq <= 0; vector <= 8'hff; sub_nmi <= 0; nmi_cnt <= 0;
    end else begin
        sub_nmi <= 0;
        if( iow ) case( A[7:0] )
            8'h00: bank <= abus ? { 2'd0, cpu_dout[2:0] } : cpu_dout[4:0] ^ {5{bankxor}};
            8'h02: if( abus ) sub_nmi <= 1;
            default:;
        endcase
        // MAME HOLD_LINE: the vector of the last request wins if both are pending
        if( irq_vb ) begin irq <= 1; vector <= abus ? 8'hff : 8'hfd; end
        if( irq_64 ) begin irq <= 1; vector <= abus ? 8'hfd : 8'hff; end
        if( inta ) irq <= 0;
        if( nmi ) nmi_cnt <= 4'hf;
        else if( nmi_cnt!=0 && cen ) nmi_cnt <= nmi_cnt - 1'd1;
    end
end

jtframe_ram #(.AW(13)) u_ram(       // Air Buster d000-efff
    .clk    ( clk           ),
    .cen    ( 1'b1          ),
    .data   ( cpu_dout      ),
    .addr   ( A[12:0]       ),
    .we     ( ram_cs && !wr_n ),
    .q      ( ram_dout      )
);

jtdjboy_calc u_calc(
    .rst    ( rst           ),
    .clk    ( clk           ),
    .we     ( calc_cs && !wr_n ),
    .addr   ( A[4:0]        ),
    .din    ( cpu_dout      ),
    .dout   ( calc_dout     )
);

jtframe_z80_devwait u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen         ),
    .cpu_cen    (             ),
    .int_n      ( ~irq        ),
    .nmi_n      ( nmi_cnt==0  ),
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
    .din        ( din         ),
    .dout       ( cpu_dout    ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( rom_ok      ),
    .dev_busy   ( obj_cs && ocopy )
);

endmodule
