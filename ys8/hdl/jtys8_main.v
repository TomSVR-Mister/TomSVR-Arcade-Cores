/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 8-bit board (MAME yunsung8.cpp): Z80 at 8 MHz, IRQ at vblank until port 7 is written.
 *   0000-7fff ROM (a write to 0001 also sets the bank), 8000-bfff ROM bank (16 kB), e000-ffff RAM
 *   c000-c7ff palette, c800-cfff colour RAM, d000-dfff tile RAM; port 0 selects the views:
 *     palette view v: writes pens v*0x400 + offset/2, reads return the other bank (MAME's crossed shares)
 *     tile view v:    writes go to layer !v (view 0 = text layer), reads come from layer v
 *   ports: 0 system / video bank, 1 P1 / ROM bank + layer enables, 2 P2 / sound latch, 3 DSW1, 4 DSW2, 6 flip, 7 IRQ ack
 * Built on JTFRAME by Jose Tejada (jotego). */

module jtys8_main(
    input              rst,
    input              clk,
    input              cen8,
    input              lvbl,

    input       [ 7:0] sys, p1, p2, dsw1, dsw2,

    output      [ 7:0] cpu_dout,
    output      [16:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,

    output      [10:0] vaddr,           // shared address for the tile/colour/palette BRAMs
    output             t0lo_we, t0hi_we, t1lo_we, t1hi_we, c0_we, c1_we, plo_we, phi_we,
    input       [ 7:0] t0lo_dout, t0hi_dout, t1lo_dout, t1hi_dout, c0_dout, c1_dout, plo_dout, phi_dout,

    output reg  [ 1:0] layers,          // bit 0 bg enabled, bit 1 text enabled
    output reg         flip,
    output reg         snd_wr
);

`ifndef NOMAIN
wire [15:0] A;
wire [ 7:0] ram_dout;
wire        mreq_n, iorq_n, rd_n, wr_n, rfsh_n, m1_n;
reg  [ 7:0] din;
reg  [ 2:0] bank;
reg         pal_view, tile_view, irq, rstn;
wire        mem   = !mreq_n && rfsh_n;
wire        io    = !iorq_n && m1_n;
wire        pal_cs = mem && A[15:11]==5'b11000;     // c000-c7ff
wire        col_cs = mem && A[15:11]==5'b11001;     // c800-cfff
wire        til_cs = mem && A[15:12]==4'b1101;      // d000-dfff
wire        ram_cs = mem && A[15:13]==3'b111;       // e000-ffff
wire        wr     = !wr_n;
wire        twl    = !tile_view;                    // layer written in the current tile view

assign rom_addr = A[15] ? { bank, A[13:0] } : { 2'd0, A[14:0] };
// palette: write { view, offset/2 }, read { !view, offset/2 }; tiles: offset/2; colour: offset
assign vaddr    = pal_cs ? { wr ? pal_view : ~pal_view, A[10:1] } :
                  til_cs ? A[11:1] : A[10:0];
assign plo_we   = pal_cs && wr && !A[0];
assign phi_we   = pal_cs && wr &&  A[0];
assign c0_we    = col_cs && wr && !twl;
assign c1_we    = col_cs && wr &&  twl;
assign t0lo_we  = til_cs && wr && !twl && !A[0];
assign t0hi_we  = til_cs && wr && !twl &&  A[0];
assign t1lo_we  = til_cs && wr &&  twl && !A[0];
assign t1hi_we  = til_cs && wr &&  twl &&  A[0];

always @* begin
    rom_cs = mem && !A[15] || mem && A[15:14]==2'b10;
    rom_cs = rom_cs && !wr_n ? 1'b0 : rom_cs;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout :
           pal_cs ? (A[0] ? phi_dout : plo_dout) :
           col_cs ? (tile_view ? c1_dout : c0_dout) :
           til_cs ? (tile_view ? (A[0] ? t1hi_dout : t1lo_dout) : (A[0] ? t0hi_dout : t0lo_dout)) :
           io ? ( A[7:0]==0 ? sys : A[7:0]==1 ? p1 : A[7:0]==2 ? p2 : A[7:0]==3 ? dsw1 : A[7:0]==4 ? dsw2 : 8'hff ) :
           8'hff;
end

reg wr_l, lvbl_l;
always @(posedge clk) begin
    rstn   <= ~rst;
    wr_l   <= wr_n;
    lvbl_l <= lvbl;
    snd_wr <= 0;
    if( rst ) begin
        bank <= 0; layers <= 2'b11; pal_view <= 0; tile_view <= 0; flip <= 0; irq <= 0;
    end else begin
        if( !lvbl && lvbl_l ) irq <= 1;
        if( !wr_n && wr_l ) begin
            if( io ) case( A[7:0] )
                0: begin pal_view <= cpu_dout[1]; tile_view <= cpu_dout[0]; end
                1: begin bank <= cpu_dout[2:0]; layers <= ~cpu_dout[5:4]; end
                2: snd_wr <= 1;
                6: flip <= cpu_dout[0];
                7: irq <= 0;
                default:;
            endcase
            if( mem && A==16'h0001 ) begin bank <= cpu_dout[2:0]; layers <= ~cpu_dout[5:4]; end
        end
    end
end

jtframe_sysz80 #(.RAM_AW(13)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen8        ),
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
initial begin rom_cs=0; layers=3; flip=0; snd_wr=0; end
assign cpu_dout=0, rom_addr=0, vaddr=0, t0lo_we=0, t0hi_we=0, t1lo_we=0, t1hi_we=0, c0_we=0, c1_we=0, plo_we=0, phi_we=0;
`endif

endmodule
