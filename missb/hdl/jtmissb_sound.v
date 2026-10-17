/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 02-06-2020
 * Miss Bubble II changes (2026, Tom Sveen), MAME missb2.cpp: no YM2203; OKI M6295 at 9000 (data bits 1/2 and 5/6 swapped),
 * YM3526 at a000, INT held at vblank, 8000-8fff RAM, e000-efff reads 0 (empty ROM space). */

module jtmissb_sound(
    input             rst,    // System reset
    input             rstn,   // from Main
    input             clk,
    input             cen3,   //  3   MHz

    input             LVBL,
    input             cen_oki,
    // Interface with main CPU
    input      [ 7:0] snd_latch,
    input             snd_stb,
    output reg [ 7:0] main_latch,
    output reg        main_stb,
    output            snd_flag,
    input             main_flag,
    // ROM
    output     [14:0] rom_addr,
    output reg        rom_cs,
    input      [ 7:0] rom_data,
    input             rom_ok,

    // Sound output
    output     [17:0] oki_addr,
    input      [ 7:0] oki_data,
    input             oki_ok,
    output signed [15:0] fm,
    output signed [13:0] pcm
);

`ifndef NOSOUND
wire        [15:0] A;
wire               iorq_n, m1_n, wr_n, rd_n;
wire        [ 7:0] ram_dout, dout, fm_dout, oki_dout;
reg                ram_cs, fm_cs, oki_cs, io_cs, zero_cs, nmi_en, macc_n;
wire               mreq_n, rfsh_n, nmi_n;
reg         [ 7:0] din;
reg                int_n, lvbl_l;
wire               flag_clr;
wire               snd_rstn = ~rst & rstn;
wire        [ 7:0] oki_din = { dout[7], dout[5], dout[6], dout[4], dout[3], dout[1], dout[2], dout[0] };
wire        [ 7:0] oki_rd  = { oki_dout[7], oki_dout[5], oki_dout[6], oki_dout[4], oki_dout[3], oki_dout[1], oki_dout[2], oki_dout[0] };

assign rom_addr   = A[14:0];
assign nmi_n      = snd_flag | ~nmi_en;
assign flag_clr   = (io_cs && !rd_n && A[1:0]==2'b0) || ~snd_rstn;

always @(*) begin
    macc_n  =  mreq_n | ~rfsh_n;
    rom_cs  = !macc_n && !A[15];
    ram_cs  = !macc_n && A[15:12]==4'h8;
    oki_cs  = !macc_n && A[15:12]==4'h9;
    fm_cs   = !macc_n && A[15:12]==4'ha;
    io_cs   = !macc_n && A[15:12]==4'hb;
    zero_cs = !macc_n && A[15:12]==4'he;
end

always @(posedge clk) begin
    case( 1'b1 )
        rom_cs:   din <= rom_data;
        fm_cs:    din <= fm_dout;
        oki_cs:   din <= oki_rd;
        io_cs:    din <= A[1] ? 8'hff : (A[0] ? {6'h3f, main_stb, snd_flag} : snd_latch);
        ram_cs:   din <= ram_dout;
        zero_cs:  din <= 8'h00;
        default:  din <= 8'hff;
    endcase
end

// INT held from the start of vblank until acknowledged
always @(posedge clk) begin
    lvbl_l <= LVBL;
    if( !snd_rstn ) int_n <= 1;
    else begin
        if( !LVBL && lvbl_l ) int_n <= 0;
        if( !iorq_n && !m1_n ) int_n <= 1;
    end
end

always @(posedge clk, negedge snd_rstn) begin
    if( !snd_rstn ) begin
        main_latch <= 8'h00;
        main_stb   <= 0;
        nmi_en     <= 0;
    end else begin
        if( io_cs && !wr_n ) begin
            case( A[1:0] )
                2'd0: begin
                    main_latch <= dout;
                    main_stb   <= 1;
                end
                2'd1: nmi_en     <= 1; // enables NMI
                2'd2: nmi_en     <= 0;
                default:;
            endcase
        end else begin
            main_stb <= 0;
        end
    end
end

jtframe_ff u_flag(
    .clk    ( clk      ),
    .rst    ( rst      ),
    .cen    ( 1'b1     ),
    .din    ( 1'b1     ),
    .q      (          ),
    .qn     ( snd_flag ),
    .set    ( 1'b0     ),
    .clr    ( flag_clr ),
    .sigedge( snd_stb  )
);

jtframe_sysz80 #(.RAM_AW(12),.RECOVERY(0)) u_cpu(
    .rst_n      ( snd_rstn    ),
    .clk        ( clk         ),
    .cen        ( cen3        ),
    .cpu_cen    (             ),
    .int_n      ( int_n       ),
    .nmi_n      ( nmi_n       ),
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
    .cpu_dout   ( dout        ),
    .ram_dout   ( ram_dout    ),
    .ram_cs     ( ram_cs      ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( 1'b1        )   // SDRAM gating managed in mem.yaml
);

jtopl u_opl(
    .rst        ( ~snd_rstn  ),
    .clk        ( clk        ),
    .cen        ( cen3       ),
    .din        ( dout       ),
    .dout       ( fm_dout    ),
    .addr       ( A[0]       ),
    .cs_n       ( ~fm_cs     ),
    .wr_n       ( wr_n       ),
    .irq_n      (            ),
    .snd        ( fm         ),
    .sample     (            )
);

jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst           ),
    .clk      ( clk           ),
    .cen      ( cen_oki       ),
    .ss       ( 1'b1          ),
    .wrn      ( ~(oki_cs & ~wr_n) ),
    .din      ( oki_din       ),
    .dout     ( oki_dout      ),
    .rom_addr ( oki_addr      ),
    .rom_data ( oki_data      ),
    .rom_ok   ( oki_ok        ),
    .sound    ( pcm           ),
    .sample   (               )
);
`else
assign snd_flag = 1'b0;
assign rom_addr = 15'd0;
assign oki_addr = 18'd0;
assign fm       = 16'sd0;
assign pcm      = 14'sd0;
initial begin
    main_latch = 8'd0;
    main_stb   = 1'b0;
    rom_cs     = 1'b0;
end
`endif

endmodule
