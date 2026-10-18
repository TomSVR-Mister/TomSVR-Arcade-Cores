/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Super Qix board without MCU (MAME superqix.cpp sqix_nomcu: Perestroika Girls). Z80 at 6 MHz.
 *   Memory: 0000-7fff ROM   8000-bfff ROM bank (0x10000 + bank * 0x4000)   e000-ffff RAM (e000 sprites, e800 tile map)
 *   I/O:    0000-00ff palette   0401 AY1 read   0402/0403 AY1 data/address   0405 AY2 read   0406/0407 AY2 data/address
 *           0408 semaphore (reads 0)   0410 { -, -, rom bank[1:0], NMI enable, bitmap page, tile bank[1:0] }
 *           0418 SYSTEM inputs, acknowledges the NMI   0800-77ff bitmap 0   8800-f7ff bitmap 1
 *   NMI four times per frame while enabled (MAME sqix_timer_irq, 240 Hz), held until 0418 is read.
 *   AY1 ports: P1, P2. AY2 ports: DSW2, DSW1 with its bits reversed.
 * Perestroika Girls program: bytes are shuffled within each 16-byte block (MAME init_perestro). */

module jtsqix_main(
    input              rst,
    input              clk,
    input              cen_6,
    input              cen_1p5,
    input       [ 8:0] vdump,
    input              hs_start,
    input              lvbl,

    input       [ 7:0] p1, p2, system, dsw1, dsw2,

    output      [ 7:0] cpu_dout,
    output      [16:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [12:0] ram_addr,
    output             ram_we,
    input       [ 7:0] ram_dout,
    output      [ 9:0] pal_addr,
    output             pal_we,
    input       [ 7:0] pal_dout,
    output      [14:0] bmp0_addr,
    output             bmp0_we,
    input       [ 7:0] bmp0_dout,
    output      [14:0] bmp1_addr,
    output             bmp1_we,
    input       [ 7:0] bmp1_dout,

    output reg  [ 1:0] tbank,
    output reg         bpage,
    output      [ 9:0] psg0, psg1
);

`ifndef NOMAIN
wire [15:0] A;
wire [ 7:0] ay1_dout, ay2_dout;
reg  [ 7:0] din;
reg         rstn, nmi_en, nmi_n;
reg  [ 1:0] rbank;
reg         ram_cs, pal_cs, b0_cs, b1_cs, reg_cs;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
wire        mem = !mreq_n && rfsh_n;
wire        io  = !iorq_n && m1_n;
wire [ 1:0] bdir, bc1;
wire [15:0] bo0 = A - 16'h0800, bo1 = A - 16'h8800;
// program shuffle: byte j of a block comes from { ~j3, ~(j2 ^ (j1 | j0)), j1, j0 ^ j1 }
wire [ 3:0] jl  = A[3:0];
wire [ 3:0] cj  = { ~jl[3], ~(jl[2] ^ (jl[1] | jl[0])), jl[1], jl[0] ^ jl[1] };
wire [16:0] pa  = A[15] ? { 1'b1, rbank, A[13:0] } : { 2'b00, A[14:0] };   // 8000-bfff: 0x10000 + bank * 0x4000

assign rom_addr  = { pa[16:4], cj };
assign ram_addr  = A[12:0];
assign pal_addr  = { 2'd0, A[7:0] };
assign bmp0_addr = bo0[14:0];
assign bmp1_addr = bo1[14:0];
assign ram_we    = ram_cs && !wr_n;
assign pal_we    = pal_cs && !wr_n;
assign bmp0_we   = b0_cs  && !wr_n;
assign bmp1_we   = b1_cs  && !wr_n;
// AY bus control: BDIR/BC1 = 01 read, 10 write, 11 latch address
wire ay1_rd = reg_cs && A[7:0]==8'h01 && !rd_n;
wire ay1_dw = reg_cs && A[7:0]==8'h02 && !wr_n;
wire ay1_aw = reg_cs && A[7:0]==8'h03 && !wr_n;
wire ay2_rd = reg_cs && A[7:0]==8'h05 && !rd_n;
wire ay2_dw = reg_cs && A[7:0]==8'h06 && !wr_n;
wire ay2_aw = reg_cs && A[7:0]==8'h07 && !wr_n;
assign bdir = { ay2_dw | ay2_aw, ay1_dw | ay1_aw };
assign bc1  = { ay2_rd | ay2_aw, ay1_rd | ay1_aw };

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && A[15:14]!=2'b11;
    ram_cs = mem && A[15:13]==3'b111;
    pal_cs = io && A[15:8]==8'h00;
    reg_cs = io && A[15:8]==8'h04;
    b0_cs  = io && A >= 16'h0800 && A < 16'h7800;
    b1_cs  = io && A >= 16'h8800 && A < 16'hf800;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data :
           ram_cs ? ram_dout :
           pal_cs ? pal_dout :
           b0_cs  ? bmp0_dout :
           b1_cs  ? bmp1_dout :
           reg_cs ? ( A[7:0]==8'h01 ? ay1_dout : A[7:0]==8'h05 ? ay2_dout : A[7:0]==8'h18 ? system : 8'h00 ) :
           8'hff;
end

// control register and NMI
reg wr_l;
always @(posedge clk) begin
    wr_l <= wr_n;
    if( rst ) begin
        tbank <= 0; bpage <= 0; nmi_en <= 0; rbank <= 0; nmi_n <= 1;
    end else begin
        if( reg_cs && A[7:0]==8'h10 && !wr_n && wr_l ) begin
            tbank  <= cpu_dout[1:0];
            bpage  <= cpu_dout[2];
            nmi_en <= cpu_dout[3];
            rbank  <= cpu_dout[5:4];
        end
        if( hs_start && nmi_en && (vdump==9'd0 || vdump==9'd66 || vdump==9'd131 || vdump==9'd197) ) nmi_n <= 0;
        if( reg_cs && A[7:0]==8'h18 && !rd_n ) nmi_n <= 1;
    end
end

jtframe_sysz80 #(.RAM_AW(2)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen_6       ),
    .cpu_cen    (             ),
    .int_n      ( 1'b1        ),
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
    .cpu_dout   ( cpu_dout    ),
    .ram_dout   (             ),
    .ram_cs     ( 1'b0        ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( rom_ok      )
);

jt49_bus u_ay1(
    .rst_n  ( rstn      ),
    .clk    ( clk       ),
    .clk_en ( cen_1p5   ),
    .bdir   ( bdir[0]   ),
    .bc1    ( bc1[0]    ),
    .din    ( cpu_dout  ),
    .sel    ( 1'b1      ),
    .dout   ( ay1_dout  ),
    .sound  ( psg0      ),
    .sample (           ),
    .IOA_in ( p1        ),
    .IOA_out(           ),
    .IOA_oe (           ),
    .IOB_in ( p2        ),
    .IOB_out(           ),
    .IOB_oe (           ),
    .A(), .B(), .C()
);

jt49_bus u_ay2(
    .rst_n  ( rstn      ),
    .clk    ( clk       ),
    .clk_en ( cen_1p5   ),
    .bdir   ( bdir[1]   ),
    .bc1    ( bc1[1]    ),
    .din    ( cpu_dout  ),
    .sel    ( 1'b1      ),
    .dout   ( ay2_dout  ),
    .sound  ( psg1      ),
    .sample (           ),
    .IOA_in ( dsw2      ),
    .IOA_out(           ),
    .IOA_oe (           ),
    .IOB_in ( { dsw1[0], dsw1[1], dsw1[2], dsw1[3], dsw1[4], dsw1[5], dsw1[6], dsw1[7] } ),
    .IOB_out(           ),
    .IOB_oe (           ),
    .A(), .B(), .C()
);
`else
initial begin rom_cs=0; tbank=0; bpage=0; end
assign cpu_dout=0, rom_addr=0, ram_addr=0, ram_we=0, pal_addr=0, pal_we=0, bmp0_addr=0, bmp0_we=0, bmp1_addr=0, bmp1_we=0,
       psg0=0, psg1=0;
`endif

endmodule
