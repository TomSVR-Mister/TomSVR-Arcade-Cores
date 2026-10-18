/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Funny Bubble main CPU (MAME funybubl.cpp main_program_map / main_io_map): Z80 at 6 MHz, INT at vblank (held until
 * acknowledged).
 *   0000-7fff ROM   8000-bfff ROM bank (16 kB pages)   c400-cfff palette (4 bytes per colour)
 *   d000-dfff tile map RAM (bank 0) or sprite RAM (bank 1)   e000-ffff RAM
 *   I/O 00: SYSTEM / video RAM bank   01: P1 / ROM bank   02: P2   03: DSW / sound latch */

module jtfunybubl_main(
    input              rst,
    input              clk,
    input              cen,
    input              lvbl,
    input              dip_pause,
    input       [ 7:0] sys, p1, p2, dsw,

    output      [ 7:0] cpu_dout,
    output      [11:0] cpu_addr,
    output      [17:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output             pal_we,
    input       [ 7:0] pal_dout,
    output             vram_we,
    input       [ 7:0] vram_dout,
    output             sram_we,
    input       [ 7:0] sram_dout,

    output reg  [ 7:0] snd_latch,
    output reg         snd_wr
);
`ifndef NOMAIN
wire [15:0] A;
wire [ 7:0] ram_dout;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg  [ 7:0] din;
reg  [ 3:0] bank;
reg         vbank, ram_cs, pal_cs, vid_cs, irq, lvbl_l, rstn, iow_l;
wire        mem  = !mreq_n && rfsh_n;
wire        io   = !iorq_n && m1_n;
wire        iow  = io && !wr_n;

assign cpu_addr = A[11:0];
assign rom_addr = A[15] ? { bank, A[13:0] } : { 3'd0, A[14:0] };
assign pal_we   = pal_cs && !wr_n;
assign vram_we  = vid_cs && !vbank && !wr_n;
assign sram_we  = vid_cs &&  vbank && !wr_n;

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && A[15:14] != 2'b11;
    pal_cs = mem && A[15:12] == 4'hc;
    vid_cs = mem && A[15:12] == 4'hd;
    ram_cs = mem && A[15:13] == 3'b111;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout : pal_cs ? pal_dout :
           vid_cs ? (vbank ? sram_dout : vram_dout) :
           io ? ( A[1:0]==0 ? sys : A[1:0]==1 ? p1 : A[1:0]==2 ? p2 : dsw ) : 8'hff;
end

always @(posedge clk) begin
    snd_wr <= 0;
    iow_l  <= iow;
    lvbl_l <= lvbl;
    if( rst ) begin
        bank <= 0; vbank <= 0; snd_latch <= 0; irq <= 0;
    end else begin
        if( iow && !iow_l ) case( A[7:0] )
            8'h00: vbank <= cpu_dout[0];
            8'h01: bank  <= cpu_dout[3:0];
            8'h03: begin snd_latch <= cpu_dout; snd_wr <= 1; end
            default:;
        endcase
        if( !lvbl && lvbl_l && dip_pause ) irq <= 1;
        if( !m1_n && !iorq_n ) irq <= 0;
    end
end

jtframe_sysz80 #(.RAM_AW(13)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen         ),
    .cpu_cen    (             ),
    .int_n      ( ~irq        ),
    .nmi_n      ( 1'b1        ),
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
    .cpu_din    ( din         ),
    .cpu_dout   ( cpu_dout    ),
    .ram_dout   ( ram_dout    ),
    .ram_cs     ( ram_cs      ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( rom_ok      )
);
`else
initial begin rom_cs=0; snd_latch=0; snd_wr=0; end
assign cpu_dout=0, cpu_addr=0, rom_addr=0, pal_we=0, vram_we=0, sram_we=0;
`endif
endmodule
