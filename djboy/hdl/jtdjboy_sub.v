/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DJ Boy / Air Buster sub CPU (MAME djboy.cpp subcpu_am/subcpu_port_am, airbustr.cpp sub_map/sub_io_map):
 * Z80 at 6 MHz, IM 2, vblank interrupt held until acknowledged (djboy vector ff, airbustr fd).
 *   DJ Boy:     0000-7fff ROM   8000-bfff ROM bank (port 00 bits 3-0; pages 0-3 = sub 00000, 8-15 = sub 10000)
 *               c000-cfff tile map (c000 codes, c800 attributes)   d000-d3ff palette (xRGB_444, big endian)
 *               d400-dfff RAM   e000-ffff RAM shared with the main CPU. Reset by the BEAST (P3.1).
 *     I/O 00 video register / bank   02 sound latch   04 BEAST latches   06 scroll y   08 scroll x
 *         0a main CPU NMI   0c BEAST latch status   0e coin counters
 *   Air Buster: 0000-7fff ROM   8000-bfff ROM bank (port 00 bits 2-0)   c000-cfff tile maps (c000/c400 fg codes /
 *               attributes, c800/cc00 bg)   d000-d5ff palette (xGRB_555, little endian)   d600-efff RAM
 *               f000-ffff RAM shared with the main CPU. NMI from the main CPU.
 *     I/O 00 bank, bit 4 flip, bit 5 clear sprite frame   02 sound latches   04-0c scroll   0e latch status
 *         20 P1   22 P2   24 SYSTEM   28 coin counters */
module jtdjboy_sub(
    input              rst,
    input              clk,
    input              cen,
    input              abus,
    input              rstn_beast,  // DJ Boy: reset from the BEAST MCU
    input              irq_vb,
    input              nmi,         // Air Buster: pulse from the main CPU
    output reg         main_nmi,    // DJ Boy: pulse to the main CPU
    output      [15:0] A,
    output      [ 7:0] cpu_dout,
    input       [ 7:0] p1, p2, sys,
    // ROM
    output      [17:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    // video memories
    output reg         vram_we,
    input       [ 7:0] vram_dout,
    output             pal_we,      // d000-dfff (palette + RAM)
    input       [ 7:0] pal_dout,
    // shared RAM
    output      [12:0] sh_addr,
    output             sh_we,
    input       [ 7:0] sh_dout,
    // latches
    output reg         snd_wr,      // sound latch write (both)
    output reg         sndr_rd,     // Air Buster: read of the latch from the sound CPU
    input       [ 7:0] sndr_dout,
    input       [ 7:0] snd_status,  // Air Buster port 0e
    output reg         bst_wr,      // DJ Boy: latch to the BEAST
    output reg         bst_rd,      // DJ Boy: latch from the BEAST
    input       [ 7:0] bst_dout,
    input       [ 7:0] bst_status,  // DJ Boy port 0c
    // video registers
    output reg  [ 7:0] vreg,        // port 00
    output reg  [ 7:0] scrx0, scry0, scrx1, scry1, scrhi
);

wire [ 7:0] ram_dout;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg  [ 7:0] din, port;
reg  [ 3:0] bank;
reg         ram_cs, pal_cs, vid_cs, sh_cs, irq, iow_l, ior_l, rstn;
wire        mem   = !mreq_n && rfsh_n;
wire        io    = !iorq_n && m1_n;
wire        iow   = io && !wr_n && !iow_l;
wire        ior   = io && !rd_n && !ior_l;
wire        inta  = !iorq_n && !m1_n;
wire [ 3:0] page  = bank[3] ? bank-4'd4 : bank;

assign rom_addr = !A[15] ? { 3'd0, A[14:0] } :
                  abus   ? { 1'b0, bank[2:0], A[13:0] } : { page, A[13:0] };
assign pal_we   = pal_cs && !wr_n;
assign sh_addr  = abus ? { 1'b0, A[11:0] } : A[12:0];
assign sh_we    = sh_cs && !wr_n;

always @(posedge clk) rstn <= ~rst & (abus | rstn_beast);

always @* begin
    rom_cs  = mem && A[15:14]!=2'b11;
    vid_cs  = mem && A[15:12]==4'hc;
    vram_we = vid_cs && !wr_n;
    pal_cs  = mem && A[15:12]==4'hd;
    ram_cs  = abus && mem && A[15:12]==4'he;
    sh_cs   = mem && (abus ? A[15:12]==4'hf : A[15:13]==3'b111);
end

always @* begin
    case( A[7:0] )
        8'h02: port = sndr_dout;
        8'h04: port = bst_dout;
        8'h0c: port = bst_status;
        8'h0e: port = snd_status;
        8'h20: port = p1;
        8'h22: port = p2;
        8'h24: port = sys;
        default: port = 8'hff;
    endcase
end

always @(posedge clk) begin
    din <= inta   ? (abus ? 8'hfd : 8'hff) :
           rom_cs ? rom_data  :
           vid_cs ? vram_dout :
           pal_cs ? pal_dout  :
           ram_cs ? ram_dout  :
           sh_cs  ? sh_dout   :
           io     ? port      : 8'hff;
end

always @(posedge clk) begin
    iow_l <= io && !wr_n;
    ior_l <= io && !rd_n;
    snd_wr <= 0; sndr_rd <= 0; bst_wr <= 0; bst_rd <= 0; main_nmi <= 0;
    if( rst ) begin
        bank <= 0; irq <= 0; vreg <= abus ? 8'h20 : 8'h00;   // airbustr: sprite frame cleared after reset
        scrx0 <= 0; scry0 <= 0; scrx1 <= 0; scry1 <= 0; scrhi <= 0;
    end else begin
        if( iow ) begin
            if( abus ) case( A[7:0] )
                8'h00: begin vreg <= cpu_dout; bank <= { 1'b0, cpu_dout[2:0] }; end
                8'h02: snd_wr <= 1;
                // airbustr scrollregs_w: port 4 fg y, 6 fg x, 8 bg y, a bg x, c high bits (complemented)
                8'h04: scry1 <= cpu_dout;
                8'h06: scrx1 <= cpu_dout;
                8'h08: scry0 <= cpu_dout;
                8'h0a: scrx0 <= cpu_dout;
                8'h0c: scrhi <= ~cpu_dout;
                default:;
            endcase else case( A[7:0] )
                8'h00: begin vreg <= cpu_dout; if( cpu_dout[3:2]!=2'b01 ) bank <= cpu_dout[3:0]; end
                8'h02: snd_wr <= 1;
                8'h04: bst_wr <= 1;
                8'h06: scry0 <= cpu_dout;
                8'h08: scrx0 <= cpu_dout;
                8'h0a: main_nmi <= 1;
                default:;
            endcase
        end
        if( ior ) begin
            if( abus && A[7:0]==8'h02 ) sndr_rd <= 1;
            if( !abus && A[7:0]==8'h04 ) bst_rd <= 1;
        end
        if( irq_vb ) irq <= 1;
        if( inta ) irq <= 0;
    end
end

reg [3:0] nmi_cnt;
always @(posedge clk) begin
    if( rst ) nmi_cnt <= 0;
    else if( nmi ) nmi_cnt <= 4'hf;
    else if( nmi_cnt!=0 && cen ) nmi_cnt <= nmi_cnt - 1'd1;
end

jtframe_ram #(.AW(12)) u_ram(       // Air Buster e000-efff
    .clk    ( clk           ),
    .cen    ( 1'b1          ),
    .data   ( cpu_dout      ),
    .addr   ( A[11:0]       ),
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
