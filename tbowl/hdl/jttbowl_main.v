/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Board 6206B CPU (MAME tecmo/tbowl.cpp _6206B_map): NEC D70008AC-8 (Z80) at 8 MHz, IRQ held from the start of
 * vblank until acknowledged, NMI from the sub CPU (its fc02 write).
 *   0000-7fff ROM   8000-9fff RAM   a000-bfff bg layer 2 RAM   c000-dfff bg layer 1 RAM   e000-efff text RAM
 *   f000-f7ff ROM bank (2 kB pages of the 64 kB data ROM, fc00 bits 7-3)   f800-fbff RAM shared with the sub CPU
 *   fc00-fc03 players 1-4 (fc00 write = bank)   fc07 coins   fc08-fc0a DSW 1-3   fc0d sound latch
 *   fc10-fc13 bg 2 scroll x lo/hi, y lo/hi   fc14-fc17 bg 1 scroll */
module jttbowl_main(
    input              rst,
    input              clk,
    input              cen,
    input              irq_vb,
    input              nmi,         // pulse from the sub CPU
    output      [ 7:0] cpu_dout,
    output      [12:0] cpu_addr,
    // inputs
    input       [ 7:0] p1, p2, p3, p4, sys,
    input       [23:0] dipsw,
    // ROM
    output      [16:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    // video RAM
    output             bg1_we,      // a000-bfff (MAME bgvideoram 2)
    output             bg0_we,      // c000-dfff (MAME bgvideoram 1)
    output             txt_we,
    input       [ 7:0] bg1_dout, bg0_dout, txt_dout,
    output reg  [10:0] scrx0, scrx1,
    output reg  [ 8:0] scry0, scry1,
    // RAM shared with the sub CPU
    output      [ 9:0] sh_addr,
    output             sh_we,
    input       [ 7:0] sh_dout,
    // sound latch
    output reg         snd_wr
);

wire [15:0] A;
wire [ 7:0] ram_dout;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg  [ 7:0] din, io_dout;
reg  [ 4:0] bank;
reg         ram_cs, bg1_cs, bg0_cs, txt_cs, sh_cs, io_cs, irq, rstn, wr_l;
reg  [ 3:0] nmi_cnt;
wire        mem  = !mreq_n && rfsh_n;
wire        inta = !iorq_n && !m1_n;
wire        wr   = io_cs && !wr_n && !wr_l;

assign rom_addr = A[15] ? { 1'b1, bank, A[10:0] } : { 2'd0, A[14:0] };
assign cpu_addr = A[12:0];
assign sh_addr  = A[9:0];
assign sh_we    = sh_cs  && !wr_n;
assign bg1_we   = bg1_cs && !wr_n;
assign bg0_we   = bg0_cs && !wr_n;
assign txt_we   = txt_cs && !wr_n;

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && (!A[15] || A[15:11]==5'b11110);
    ram_cs = mem && A[15:13]==3'b100;
    bg1_cs = mem && A[15:13]==3'b101;
    bg0_cs = mem && A[15:13]==3'b110;
    txt_cs = mem && A[15:12]==4'he;
    sh_cs  = mem && A[15:10]==6'b1111_10;
    io_cs  = mem && A[15:10]==6'b1111_11;
end

always @* begin
    case( A[4:0] )
        5'h00: io_dout = p1;
        5'h01: io_dout = p2;
        5'h02: io_dout = p3;
        5'h03: io_dout = p4;
        5'h07: io_dout = sys;
        5'h08: io_dout = dipsw[ 7: 0];
        5'h09: io_dout = dipsw[15: 8];
        5'h0a: io_dout = dipsw[23:16];
        default: io_dout = 8'h00;     // unmapped, MAME reads 0 (the NMI handler tests fc06 bit 7)
    endcase
end

always @(posedge clk) begin
    din <= inta   ? 8'hff    :
           rom_cs ? rom_data :
           ram_cs ? ram_dout :
           bg1_cs ? bg1_dout :
           bg0_cs ? bg0_dout :
           txt_cs ? txt_dout :
           sh_cs  ? sh_dout  :
           io_cs  ? io_dout  : 8'hff;
end

always @(posedge clk) begin
    wr_l   <= io_cs && !wr_n;
    snd_wr <= 0;
    if( rst ) begin
        bank <= 0; irq <= 0; nmi_cnt <= 0;
        scrx0 <= 0; scrx1 <= 0; scry0 <= 0; scry1 <= 0;
    end else begin
        if( wr ) case( A[4:0] )
            5'h00: bank <= cpu_dout[7:3];
            5'h0d: snd_wr <= 1;
            5'h10: scrx1[ 7:0] <= cpu_dout;
            5'h11: scrx1[10:8] <= cpu_dout[2:0];
            5'h12: scry1[ 7:0] <= cpu_dout;
            5'h13: scry1[8]    <= cpu_dout[0];
            5'h14: scrx0[ 7:0] <= cpu_dout;
            5'h15: scrx0[10:8] <= cpu_dout[2:0];
            5'h16: scry0[ 7:0] <= cpu_dout;
            5'h17: scry0[8]    <= cpu_dout[0];
            default:;
        endcase
        if( irq_vb ) irq <= 1;
        else if( inta ) irq <= 0;
        if( nmi ) nmi_cnt <= 4'hf;
        else if( nmi_cnt!=0 && cen ) nmi_cnt <= nmi_cnt - 1'd1;
    end
end

jtframe_ram #(.AW(13)) u_ram(
    .clk    ( clk           ),
    .cen    ( 1'b1          ),
    .data   ( cpu_dout      ),
    .addr   ( A[12:0]       ),
    .we     ( ram_cs && !wr_n ),
    .q      ( ram_dout      )
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
    .dev_busy   ( 1'b0        )
);

endmodule
