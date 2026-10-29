/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DJ Boy "BEAST" protection MCU: OKI MSM80C51F at 6 MHz with its 4 kB internal ROM (MAME djboy.cpp beast_p*_r/w).
 * Two latches with the sub CPU:
 *   beastlatch (sub -> MCU): written by sub port 04, raises INT0; read on P1 while P0.0 is low; acknowledged
 *     (pending cleared) by P0 writes with bit 0 low.
 *   sublatch (MCU -> sub): P1 value written on a rising edge of P0.1; read (and cleared) by sub port 04.
 *   P2 in: P0 bits 3-2 select IN1 (0), IN2 (1), IN0 (2), ff (3).
 *   P3 in: bits 7-4 = one bit of each DSW nibble, selected by P0 bits 6-5; bit 2 = beastlatch empty,
 *     bit 3 = sublatch full. P3.1 out = sub CPU reset (low = held in reset).
 * The MCU runs on clk24 (timing); the latches stay on the CPU clock.
 * The jt8051 has no port write strobe: an acknowledge is taken on every change of P0 while bit 0 is low. */
module jtdjboy_beast(
    input              rst,
    input              clk,
    input              clk_mcu,     // 24 MHz
    input              cen,         // 6 MHz, clk_mcu domain
    input       [ 7:0] in0, in1, in2,
    input       [ 7:0] dsw1, dsw2,
    // sub CPU side
    input       [ 7:0] sub_dout,
    input              sub_wr,
    input              sub_rd,
    output reg  [ 7:0] sub_din,     // sublatch value
    output      [ 7:0] status,      // sub port 0c
    output             sub_rstn,
    // program
    input       [11:0] prog_addr,
    input       [ 7:0] prog_data,
    input              prom_we
);

wire [7:0] p0, p1, p2, p3;
reg  [7:0] blatch, p0_l, p2_i;
reg  [3:0] dsw;
reg        bpend, spend;
wire [7:0] ndsw1 = ~dsw1, ndsw2 = ~dsw2;

assign status   = { 4'd0, bpend, ~spend, 2'd0 };
assign sub_rstn = p3[1];

always @* begin
    case( p0[3:2] )
        2'd0: p2_i = in1;
        2'd1: p2_i = in2;
        2'd2: p2_i = in0;
        2'd3: p2_i = 8'hff;
    endcase
    case( p0[6:5] )
        2'd0: dsw = { ndsw2[4], ndsw2[0], ndsw1[4], ndsw1[0] };
        2'd1: dsw = { ndsw2[5], ndsw2[1], ndsw1[5], ndsw1[1] };
        2'd2: dsw = { ndsw2[6], ndsw2[2], ndsw1[6], ndsw1[2] };
        2'd3: dsw = { ndsw2[7], ndsw2[3], ndsw1[7], ndsw1[3] };
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        bpend <= 0; spend <= 0; blatch <= 0; sub_din <= 0; p0_l <= 8'hff;
    end else begin
        p0_l <= p0;
        if( p0[1] && !p0_l[1] ) begin sub_din <= p1; spend <= 1; end
        if( !p0[0] && p0 != p0_l ) bpend <= 0;
        if( sub_rd ) spend <= 0;
        if( sub_wr ) begin blatch <= sub_dout; bpend <= 1; end
    end
end

jtframe_8751mcu #(.SYNC_XDATA(0),.ROMBIN("beast.bin")) u_mcu(
    .rst        ( rst       ),
    .clk        ( clk_mcu   ),
    .cen        ( cen       ),
    .int0n      ( ~bpend    ),
    .int1n      ( 1'b1      ),
    .p0_i       ( 8'h00     ),
    .p1_i       ( blatch    ),   // MAME: 0 while P0.0 is high; the jt8051 sees P0 one cycle late, so always the latch
    .p2_i       ( p2_i      ),
    .p3_i       ( { dsw, spend, ~bpend, 2'b00 } ),
    .p0_o       ( p0        ),
    .p1_o       ( p1        ),
    .p2_o       ( p2        ),
    .p3_o       ( p3        ),
    .x_din      ( 8'hff     ),
    .x_dout     (           ),
    .x_addr     (           ),
    .x_wr       (           ),
    .x_acc      (           ),
    .clk_rom    ( clk       ),
    .prog_addr  ( prog_addr ),
    .prom_din   ( prog_data ),
    .prom_we    ( prom_we   )
);

endmodule
