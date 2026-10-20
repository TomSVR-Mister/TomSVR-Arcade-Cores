/* SPDX-License-Identifier: GPL-3.0-or-later
   Seibu sound system for Dynamite Duke: Z80 with SEI80BU decryption over its whole address space, YM3812
   and OKI 6295. Adapted from jotego's jttoki_sound (JTTOKI), with the Seibu main-CPU port of MAME's
   seibusound.cpp: offsets 0-1 command latches, 2/6 mark the command as sent, 4 raises RST 18,
   reads 2-3 return the reply latches and 5 the pending flag. Coins are read by the sound CPU. */

module jtdynduke_sound(
    input             rst,
    input             clk,
    input             fm_cen,
    input             oki_cen,

    input       [1:0] coin,

    // main CPU port
    input       [2:0] main_addr,
    input       [7:0] main_dout,
    input             main_we,     // one pulse per write
    output reg  [7:0] main_din,

    output     [16:0] rom_addr,
    output reg        rom_cs,
    input       [7:0] rom_data,
    input             rom_ok,

    output     [15:0] pcm_addr,
    output reg        pcm_cs,
    input       [7:0] pcm_data,
    input             pcm_ok,

    output reg signed [15:0] fm,
    output reg signed [13:0] pcm
);

`ifndef NOSOUND
wire        [17:0] oki_addr;
wire        [15:0] cpu_addr;
wire signed [15:0] opl_snd;
wire signed [13:0] oki_snd;
wire        [ 7:0] cpu_dout, ram_dout, dec_data, im0_opcode, ym_dout, oki_dout;
wire               dec_ok, cpu_rd_n, cpu_wr_n, mem_acc, mem_wr, cpu_m1_n, cpu_mreq_n,
                   cpu_rfsh_n, cpu_iorq_n, irq_n, irq_ack, ym_irq_n, rst_n;
reg         [ 7:0] din, main2sub0, main2sub1, sub2main0, sub2main1;
reg                ram_cs, ym_cs, oki_cs, bank, wait_ok, sub2main_pending, main2sub_pending;
reg                pending_set_cs, irq_clear_cs, fm_eoi_cs, main_eoi_cs, bank_cs,
                   latch0_cs, latch1_cs, pend_rd_cs, coin_cs, reply0_cs, reply1_cs;

assign mem_acc  = ~cpu_mreq_n & cpu_rfsh_n;
assign mem_wr   = mem_acc & ~cpu_wr_n;
assign irq_ack  = ~cpu_iorq_n & ~cpu_m1_n;
assign rst_n    = ~rst;
// the 32 kB bank window shows the second half of the ROM (bank 0) or a copy of the first half (bank 1)
assign rom_addr = !cpu_addr[15] ? {2'b00, cpu_addr[14:0]} : {bank, ~bank, cpu_addr[14:0]};
// sample ROM address lines 13 and 15 are swapped on the board
assign pcm_addr = {oki_addr[13], oki_addr[14], oki_addr[15], oki_addr[12:0]};

always @* begin
    ram_cs         = mem_acc && cpu_addr[15:11]==5'b00100;         // 2000-27ff
    pending_set_cs = cpu_addr==16'h4000;
    irq_clear_cs   = cpu_addr==16'h4001;
    fm_eoi_cs      = cpu_addr==16'h4002;
    main_eoi_cs    = cpu_addr==16'h4003;
    bank_cs        = cpu_addr==16'h4007;
    ym_cs          = mem_acc && cpu_addr[15:1]==15'h2004;           // 4008-4009
    latch0_cs      = cpu_addr==16'h4010;
    latch1_cs      = cpu_addr==16'h4011;
    pend_rd_cs     = cpu_addr==16'h4012;
    coin_cs        = cpu_addr==16'h4013;
    reply0_cs      = cpu_addr==16'h4018;
    reply1_cs      = cpu_addr==16'h4019;
    oki_cs         = mem_acc && cpu_addr==16'h6000;
    rom_cs         = mem_acc && !ram_cs && cpu_addr[15:13]!=3'b010 && cpu_addr[15:11]!=5'b01100;
end

always @(posedge clk) begin
    wait_ok <= rom_cs & dec_ok;
    fm      <= opl_snd;
    pcm     <= oki_snd;
    pcm_cs  <= 1;
end

always @(posedge clk) begin
    if( rst ) begin
        bank <= 0;
        main2sub0 <= 0; main2sub1 <= 0; sub2main0 <= 0; sub2main1 <= 0;
        sub2main_pending <= 0; main2sub_pending <= 0;
    end else begin
        if( mem_wr && bank_cs   ) bank      <= cpu_dout[0];
        if( mem_wr && reply0_cs ) sub2main0 <= cpu_dout;
        if( mem_wr && reply1_cs ) sub2main1 <= cpu_dout;
        if( mem_wr && pending_set_cs ) begin
            main2sub_pending <= 0;
            sub2main_pending <= 1;
        end
        if( main_we ) case( main_addr )
            0: main2sub0 <= main_dout;
            1: main2sub1 <= main_dout;
            2, 6: begin
                main2sub_pending <= 1;
                sub2main_pending <= 0;
            end
            default:;
        endcase
    end
end

always @(posedge clk) begin
    case( main_addr )
        2: main_din <= sub2main0;
        3: main_din <= sub2main1;
        5: main_din <= {7'd0, main2sub_pending};
        default: main_din <= 8'hff;
    endcase
end

always @(posedge clk) begin
    din <= irq_ack    ? im0_opcode :
           pend_rd_cs ? {7'd0, sub2main_pending} :
           ym_cs      ? ym_dout   :
           oki_cs     ? oki_dout  :
           latch0_cs  ? main2sub0 :
           latch1_cs  ? main2sub1 :
           coin_cs    ? {6'd0, ~coin[1], ~coin[0]} :
           ram_cs     ? ram_dout  :
           rom_cs     ? dec_data  : 8'hff;
end

jttoki_irq u_irq(
    .rst           ( rst                          ),
    .clk           ( clk                          ),
    .fm_irq_n      ( ym_irq_n                     ),
    .main_irq_trig ( main_we && main_addr==4      ),
    .cpu_irq_ack   ( irq_ack                      ),
    .fm_eoi        ( mem_wr & fm_eoi_cs           ),
    .main_eoi      ( mem_wr & (irq_clear_cs | main_eoi_cs) ),
    .cpu_irq_n     ( irq_n                        ),
    .im0_opcode    ( im0_opcode                   )
);

sei80bu u_sei80bu(
    .clk      ( clk         ),
    .rom_addr ( cpu_addr    ),
    .rom_data ( rom_data    ),
    .rom_ok   ( rom_ok      ),
    .rom_cs   ( rom_cs      ),
    .z80_m1   ( ~cpu_m1_n   ),
    .dec_data ( dec_data    ),
    .dec_ok   ( dec_ok      )
);

jt6295 #(.INTERPOL(1)) u_oki(
    .rst      ( rst                 ),
    .clk      ( clk                 ),
    .cen      ( oki_cen             ),
    .ss       ( 1'b1                ),
    .wrn      ( ~(mem_wr & oki_cs)  ),
    .din      ( cpu_dout            ),
    .dout     ( oki_dout            ),
    .rom_addr ( oki_addr            ),
    .rom_data ( pcm_data            ),
    .rom_ok   ( pcm_ok              ),
    .sound    ( oki_snd             ),
    .sample   (                     )
);

jtopl2 u_opl2(
    .rst    ( rst           ),
    .clk    ( clk           ),
    .cen    ( fm_cen        ),
    .din    ( cpu_dout      ),
    .addr   ( cpu_addr[0]   ),
    .cs_n   ( ~ym_cs        ),
    .wr_n   ( ~mem_wr       ),
    .dout   ( ym_dout       ),
    .irq_n  ( ym_irq_n      ),
    .snd    ( opl_snd       ),
    .sample (               )
);

jtframe_sysz80 #(.RAM_AW(11)) u_z80(
    .rst_n    ( rst_n        ),
    .clk      ( clk          ),
    .cen      ( fm_cen       ),
    .cpu_cen  (              ),
    .int_n    ( irq_n        ),
    .nmi_n    ( 1'b1         ),
    .busrq_n  ( 1'b1         ),
    .m1_n     ( cpu_m1_n     ),
    .mreq_n   ( cpu_mreq_n   ),
    .iorq_n   ( cpu_iorq_n   ),
    .rd_n     ( cpu_rd_n     ),
    .wr_n     ( cpu_wr_n     ),
    .rfsh_n   ( cpu_rfsh_n   ),
    .halt_n   (              ),
    .busak_n  (              ),
    .A        ( cpu_addr     ),
    .cpu_din  ( din          ),
    .cpu_dout ( cpu_dout     ),
    .ram_dout ( ram_dout     ),
    .ram_cs   ( ram_cs       ),
    .rom_cs   ( rom_cs       ),
    .rom_ok   ( wait_ok      )
);
`else
assign rom_addr = 0;
assign pcm_addr = 0;
initial begin
    rom_cs = 0; pcm_cs = 0; fm = 0; pcm = 0; main_din = 8'hff;
end
`endif

endmodule
