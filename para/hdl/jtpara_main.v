/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung Paradise board (MAME paradise.cpp, paradise config): Z80 at 6 MHz.
 *   memory: 0000-7fff ROM, 8000-bfff ROM bank (16 kB pages), c000-c7ff fg tilemap, c800-cfff mid tilemap,
 *           d000-d7ff bg tilemap, d800-d8ff RAM, d900-e0ff sprites, e100-ffff RAM
 *   I/O:    0000-17ff palette (R, G, B), 1800 priority, 2001 flip, 2004 palette banks, 2006 ROM bank,
 *           2007 OKI 2 bank, 2010 OKI 1, 2030 OKI 2, 2020-2024 inputs, 8000-ffff pixel layer
 * Torus map (tmap): d800-dfff sprites, e000-ffff RAM.
 * Built on JTFRAME by Jose Tejada (jotego). */

module jtpara_main(
    input              rst,
    input              clk,
    input              cen6,
    input              irq,          // strobe, 4 per frame
    input              lvbl,
    input              tmap,         // Torus/Penky/Mad Ball map: sprites d800-dfff, RAM e000-ffff
    input              tflip,        // Target Ball family: flip polarity inverted
    input       [ 3:0] bank_mask,    // number of 16 kB ROM pages - 1

    input       [ 7:0] p1, p2, sys,
    input       [15:0] dipsw,

    output      [ 7:0] cpu_dout,
    // ROM
    output      [17:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    // BRAM
    output      [10:0] vram_addr,
    output             vram0_we, vram1_we, vram2_we,
    input       [ 7:0] vram0_dout, vram1_dout, vram2_dout,
    output      [10:0] objram_addr,
    output             objram_we,
    input       [ 7:0] objram_dout,
    output      [14:0] pix_addr,
    output             pix_we,
    input       [ 7:0] pix_dout,
    output      [10:0] pal_addr,
    output             palr_we, palg_we, palb_we,
    input       [ 7:0] palr_dout, palg_dout, palb_dout,
    // video registers
    output reg  [ 7:0] prio,
    output reg         flip,
    output reg  [ 3:0] bg_bank,      // tilemap 0 colour = { bg_bank, 1 }
    output reg  [ 3:0] pix_bank,     // pixel layer palette at 0x200 + pix_bank*16
    // OKI
    output             oki1_wrn, oki2_wrn,
    input       [ 7:0] oki1_dout, oki2_dout,
    output reg         oki2_bank
);

`ifndef NOMAIN
wire [15:0] A;
wire [ 7:0] ram_dout;
wire        mreq_n, iorq_n, rd_n, wr_n, rfsh_n, m1_n;
reg  [ 7:0] din;
reg  [ 3:0] bank;
reg         ram_cs, vram0_cs, vram1_cs, vram2_cs, objram_cs;
wire        mem = !mreq_n && rfsh_n;
wire        io  = !iorq_n && m1_n;
wire        pal_cs = io && A < 16'h1800;
wire        pix_cs = io && A[15];
wire [15:0] objofs = A - (tmap ? 16'hd800 : 16'hd900);
reg         rstn;

assign rom_addr    = A[15] ? { bank, A[13:0] } : { 3'd0, A[14:0] };
assign vram_addr   = A[10:0];
assign objram_addr = objofs[10:0];
assign pix_addr    = A[14:0];
assign pal_addr    = A[10:0];
assign vram0_we    = vram0_cs  && !wr_n;
assign vram1_we    = vram1_cs  && !wr_n;
assign vram2_we    = vram2_cs  && !wr_n;
assign objram_we   = objram_cs && !wr_n;
assign pix_we      = pix_cs    && !wr_n;
assign palr_we     = pal_cs && A[12:11]==0 && !wr_n;
assign palg_we     = pal_cs && A[12:11]==1 && !wr_n;
assign palb_we     = pal_cs && A[12:11]==2 && !wr_n;
assign oki1_wrn    = !(io && A==16'h2010 && !wr_n);
assign oki2_wrn    = !(io && A==16'h2030 && !wr_n);

always @* begin
    rom_cs    = mem && A[15:14] != 2'b11;           // 0000-bfff
    vram2_cs  = mem && A[15:11] == 5'b1100_0;       // c000-c7ff
    vram1_cs  = mem && A[15:11] == 5'b1100_1;       // c800-cfff
    vram0_cs  = mem && A[15:11] == 5'b1101_0;       // d000-d7ff
    objram_cs = mem && (tmap ? (A[15:11]==5'b1101_1) : (A >= 16'hd900 && A < 16'he100));
    ram_cs    = mem && A >= 16'hd800 && !objram_cs; // d800-d8ff, e100-ffff (Torus map: e000-ffff)
end

always @(posedge clk) begin
    din <= rom_cs    ? rom_data    :
           ram_cs    ? ram_dout    :
           vram0_cs  ? vram0_dout  :
           vram1_cs  ? vram1_dout  :
           vram2_cs  ? vram2_dout  :
           objram_cs ? objram_dout :
           pal_cs    ? (A[12:11]==0 ? palr_dout : A[12:11]==1 ? palg_dout : palb_dout) :
           pix_cs    ? pix_dout    :
           io && A==16'h2010 ? oki1_dout :
           io && A==16'h2030 ? oki2_dout :
           io && A==16'h2020 ? dipsw[ 7:0] :
           io && A==16'h2021 ? dipsw[15:8] :
           io && A==16'h2022 ? p1 :
           io && A==16'h2023 ? p2 :
           io && A==16'h2024 ? sys : 8'hff;
end

always @(posedge clk) begin
    rstn <= ~rst;
    if( rst ) begin
        prio <= 0; flip <= 0; bg_bank <= 0; pix_bank <= 0; bank <= 0; oki2_bank <= 0;
    end else if( io && !wr_n ) begin
        case( A )
            16'h1800: prio      <= cpu_dout;
            16'h2001: flip      <= (cpu_dout!=0) ^ ~tflip; // MAME: data ? 0 : 1 (Target Ball family: data ? 1 : 0)
            16'h2004: begin bg_bank <= { 1'b0, cpu_dout[3:1] }; pix_bank <= cpu_dout[7:4]; end
            16'h2006: bank      <= cpu_dout[3:0] & bank_mask;   // up to 16 pages of 16 kB (MAME: bank % pages)
            16'h2007: oki2_bank <= cpu_dout[1];
            default:;
        endcase
    end
end

jtframe_sysz80 #(.RAM_AW(14),.CLR_INT(1)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen6        ),
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
initial begin rom_cs=0; prio=8'h7; flip=0; bg_bank=0; pix_bank=0; oki2_bank=0; end
assign cpu_dout=0, rom_addr=0, vram_addr=0, vram0_we=0, vram1_we=0, vram2_we=0, objram_addr=0, objram_we=0,
       pix_addr=0, pix_we=0, pal_addr=0, palr_we=0, palg_we=0, palb_we=0, oki1_wrn=1, oki2_wrn=1;
`endif

endmodule
