/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Board 6206C CPU (MAME tecmo/tbowl.cpp _6206C_map): NEC D70008AC-8 (Z80) at 8 MHz, IRQ held from the start of
 * vblank until acknowledged.
 *   0000-bfff ROM   c000-d7ff RAM   d800-dfff sprite RAM   e000-efff palette (2 x 1024 colours, xBRG 444 big endian)
 *   f000-f7ff ROM bank (2 kB pages of the second 64 kB ROM, fc00 bits 7-3)   f800-fbff RAM shared with the main CPU
 *   fc02 write: NMI to the main CPU */
module jttbowl_sub(
    input              rst,
    input              clk,
    input              cen,
    input              irq_vb,
    output reg         main_nmi,
    output      [ 7:0] cpu_dout,
    output      [11:0] cpu_addr,
    // ROM
    output      [16:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    // video
    output             obj_we,
    input       [ 7:0] obj_dout,
    output             pal_we,
    input       [ 7:0] pal_dout,
    // RAM shared with the main CPU
    output      [ 9:0] sh_addr,
    output             sh_we,
    input       [ 7:0] sh_dout
);

wire [15:0] A;
wire [ 7:0] ram_dout;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg  [ 7:0] din;
reg  [ 4:0] bank;
reg         ram_cs, obj_cs, pal_cs, sh_cs, io_cs, irq, rstn, wr_l;
wire        mem  = !mreq_n && rfsh_n;
wire        inta = !iorq_n && !m1_n;
wire        wr   = io_cs && !wr_n && !wr_l;

assign rom_addr = A[15:12]==4'hf ? { 1'b1, bank, A[10:0] } : { 1'b0, A };
assign cpu_addr = A[11:0];
assign sh_addr  = A[9:0];
assign sh_we    = sh_cs  && !wr_n;
assign obj_we   = obj_cs && !wr_n;
assign pal_we   = pal_cs && !wr_n;

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && (A[15:14]!=2'b11 || A[15:11]==5'b11110);
    ram_cs = mem && A[15:12]==4'hc || (mem && A[15:11]==5'b11010);   // c000-d7ff
    obj_cs = mem && A[15:11]==5'b11011;
    pal_cs = mem && A[15:12]==4'he;
    sh_cs  = mem && A[15:10]==6'b1111_10;
    io_cs  = mem && A[15:10]==6'b1111_11;
end

always @(posedge clk) begin
    din <= inta   ? 8'hff    :
           rom_cs ? rom_data :
           ram_cs ? ram_dout :
           obj_cs ? obj_dout :
           pal_cs ? pal_dout :
           sh_cs  ? sh_dout  : 8'h00;   // unmapped reads 0, as in MAME
end

always @(posedge clk) begin
    wr_l     <= io_cs && !wr_n;
    main_nmi <= 0;
    if( rst ) begin
        bank <= 0; irq <= 0;
    end else begin
        if( wr ) case( A[2:0] )
            3'd0: bank <= cpu_dout[7:3];
            3'd2: main_nmi <= 1;
            default:;
        endcase
        if( irq_vb ) irq <= 1;
        else if( inta ) irq <= 0;
    end
end

jtframe_ram #(.AW(13)) u_ram(       // c000-d7ff (6 kB used)
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
    .din        ( din         ),
    .dout       ( cpu_dout    ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( rom_ok      ),
    .dev_busy   ( 1'b0        )
);

endmodule
