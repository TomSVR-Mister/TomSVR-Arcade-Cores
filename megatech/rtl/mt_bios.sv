/*  mt_bios.sv - Sega Mega-Tech BIOS side: Z80, BIOS ROM, RAMs, two CXD1095 I/O chips, menu VDP
 *
 *  Copyright (C) 2026 TomSVR. Written for the TomSVR Mega-Tech core.
 *  Memory map, I/O and behaviour follow MAME src/mame/sega/megatech.cpp (BSD-3-Clause, David Haywood,
 *  Barry Rodewald) and src/devices/machine/cxd1095.cpp (BSD-3-Clause, AJR).
 *
 *  This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
 *  Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
 *  option) any later version.
 *
 *  Z80 map: 0000-2fff BIOS ROM | 3000-3fff RAM banked by cart slot | 4000-5fff RAM | 6000 bank shift register |
 *  6400 io1 | 6800 io2 | 7000-77ff BIOS ROM | 8000-9fff window into the 68000 space (only the instruction ROM
 *  at 0x300000, odd bytes, is mapped here; MAME logs show the BIOS reads nothing else).
 *  Banked RAM: slot 0 has its own 4 kB, slots 1-7 share one 4 kB (only one cart slot is fitted here).
 *  As MAME: a write to the cart select port (io1 port E) restarts the game side (game_reset pulse).
 *  Not modelled (MAME doesn't either): the BIOS stopping the game when time runs out.
 */
module mt_bios (
    input             clk,        // 53.693175 MHz (Mega-Tech master clock)
    input             reset,

    // ROM download (ioctl, same clk): BIOS at 0x0000-0x7fff, instruction ROM at 0x8000-0xffff
    input             dl,
    input      [24:0] dl_addr,
    input      [15:0] dl_data,    // WIDE ioctl: [7:0] = byte at dl_addr, [15:8] = byte at dl_addr+1
    input             dl_wr,

    // cabinet inputs, active high
    input             coin1, coin2, service_coin, start1, start2,
    input       [8:0] tu_x, tu_y,          // pixel position relative to the TIME UP text (game screen timing)
    input             sel_btn, enter_btn, service, door1, door2,
    input       [7:0] dsw0, dsw1,
    input       [7:0] cart_present,   // io2 port C: bit n low = cart in slot n+1 (MAME returns 00)
    input       [5:0] pad1,       // {C,B,A? -> as MAME PAD: bit5..0 = C B R L D U} active low
    input       [5:0] pad2,
    input             pad1_a, pad2_a, // A / Start for port 3f == 0x55 reads

    output reg  [2:0] cart_sel,
    output reg        game_reset, // one clk pulse on every cart select write (MAME switch_cart)
    output reg  [7:0] portd,      // io2 port D outputs (bit 7 alarm, bit 2 game input disable)
    output reg  [3:0] porte,      // io2 port E outputs (bit 1 screen flash)

    // menu video
    output      [1:0] r, g, b,
    output            hs, vs, hblank, vblank,
    output            ce_pix,

    // menu sound: SN76489 of the 315-5246 (jt89 by Jose Tejada, GPL-3)
    output signed [10:0] snd,

    // TIME UP screen for the main monitor, in the menu video timing (see "TIME UP on the main monitor")
    output reg        timeup,
    output            tu_px                // TIME UP text pixel at (tu_x, tu_y)
);

// ------------------------------------------------------------- clock enables: Z80 /15, pixel /10
reg [3:0] zdiv;
reg [3:0] pdiv;
always @(posedge clk) begin
    zdiv <= (zdiv == 4'd14) ? 4'd0 : zdiv + 4'd1;
    pdiv <= (pdiv == 4'd9)  ? 4'd0 : pdiv + 4'd1;
end
wire zcen = (zdiv == 4'd0);
assign ce_pix = (pdiv == 4'd0);

// ------------------------------------------------------------- Z80
wire [15:0] A;
wire  [7:0] zdo;
reg   [7:0] zdi;
wire        mreq_n, iorq_n, rd_n, wr_n, m1_n;
wire        vdp_irq_n;

`ifdef SIM_T80V
T80s z80 (            // Verilog copy made with GHDL for Verilator (generics fixed to Mode 0, T2Write 1, IOWait 1)
`else
T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80 (
`endif
    .RESET_n(~reset), .CLK(clk), .CEN(zcen),
    .WAIT_n(1'b1), .INT_n(vdp_irq_n), .NMI_n(1'b1), .BUSRQ_n(1'b1),
    .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
    .RFSH_n(), .HALT_n(), .BUSAK_n(),
    .A(A), .DI(zdi), .DO(zdo)
`ifdef SIM_T80V
    , .OUT0(1'b0), .REG(), .DIRSet(1'b0), .DIR(230'd0), .ISet_out()
`endif
);

wire mem_rd = ~mreq_n & ~rd_n;
wire io_rd  = ~iorq_n & ~rd_n & m1_n;
wire io_wr  = ~iorq_n & ~wr_n;
// one-clk write strobes (the Z80 holds WR_n low for many clk)
reg  wr_d;
always @(posedge clk) wr_d <= ~wr_n;
wire wr_edge = ~wr_n & ~wr_d;
wire mem_we  = ~mreq_n & wr_edge;
wire io_we   = ~iorq_n & wr_edge;
reg  rd_d;
always @(posedge clk) rd_d <= ~rd_n;
wire rd_edge = ~rd_n & ~rd_d;

// ------------------------------------------------------------- memories
reg  [7:0] bios_rom [0:32767];
reg  [7:0] instr_rom[0:32767];
reg  [7:0] ram      [0:8191];
reg  [7:0] bram     [0:8191];      // {slot != 0, 12-bit offset}
reg  [7:0] bios_q, instr_q, ram_q, bram_q;

// download: two bytes per WIDE ioctl word, written on two consecutive clocks
reg        dl_ph1, dl_ph2;
reg [15:0] dl_w;
reg [14:0] dl_a;
reg        dl_hi;      // 0: BIOS (0x0000-0x7fff), 1: instruction ROM (0x8000-0xffff)
always @(posedge clk) begin
    dl_ph1 <= 0;
    dl_ph2 <= dl_ph1;
    if (dl & dl_wr & ~|dl_addr[24:16]) begin dl_ph1 <= 1; dl_w <= dl_data; dl_a <= {dl_addr[14:1], 1'b0}; dl_hi <= dl_addr[15]; end
end
// one write port per ROM: low byte on the first clock, high byte on the second
wire        rom_we = dl_ph1 | dl_ph2;
wire [14:0] rom_wa = dl_ph1 ? dl_a : (dl_a | 15'd1);
wire  [7:0] rom_wd = dl_ph1 ? dl_w[7:0] : dl_w[15:8];
always @(posedge clk) begin
    if (rom_we &  dl_hi) instr_rom[rom_wa] <= rom_wd;
    if (rom_we & ~dl_hi) bios_rom[rom_wa]  <= rom_wd;
end

// 68000 window (8000-9fff): bank_addr is a 9-bit shift register (MAME mt_z80_bank_w)
reg  [23:0] bank_addr;
wire [23:0] win_a   = bank_addr | {11'd0, A[12:0]};
wire        win_ins = (win_a[23:16] == 8'h30);          // 0x300000-0x30ffff: instruction ROM on odd bytes

always @(posedge clk) begin
    bios_q  <= bios_rom[A[14:0]];
    instr_q <= instr_rom[win_a[15:1]];
    ram_q   <= ram[A[12:0]];
    bram_q  <= bram[{cart_sel != 3'd0, A[11:0]}];
    if (mem_we && A[15:13] == 3'b010) ram[A[12:0]] <= zdo;            // 4000-5fff
    if (mem_we && A[15:12] == 4'h3) bram[{cart_sel != 3'd0, A[11:0]}] <= zdo;
end

always @(posedge clk) begin
    if (reset) bank_addr <= 0;
    else if (mem_we && A == 16'h6000) bank_addr <= {zdo[0], bank_addr[23:16], 15'd0} & 24'hff8000;
end

// ------------------------------------------------------------- CXD1095 x2 (MAME model)
reg [7:0] latch1 [0:4], latch2 [0:4];
reg [7:0] dir1   [0:4], dir2   [0:4];   // 1 = input
wire [7:0] in1 [0:4];
wire [7:0] in2 [0:4];
assign in1[0] = dsw0;  assign in1[1] = dsw1;  assign in1[2] = 8'h00; assign in1[3] = 8'h00; assign in1[4] = 8'h00;
// io2 A: BIOS_IN0 (active low): 0 select, 4/5 doors, 7 service; B: BIOS_IN1: coins, service coin, enter, starts
assign in2[0] = ~{service, 1'b0, door2, door1, 3'b000, sel_btn};
assign in2[1] = ~{start2, start1, enter_btn, service_coin, 2'b00, coin2, coin1};
assign in2[2] = cart_present; assign in2[3] = 8'h00; assign in2[4] = 8'h00;   // port E input (bit 0: MD bus ready) reads 0 as MAME

wire       io1_cs = (A[15:3] == 13'h0c80);   // 6400-6407
wire       io2_cs = (A[15:3] == 13'h0d00);   // 6800-6807
wire [2:0] io_off = A[2:0];

function [7:0] cxd_rd(input [7:0] latch, input [7:0] dir, input [7:0] inp, input is_e);
    reg [7:0] m;
    begin
        m = is_e ? (dir & 8'h0f) : dir;
        cxd_rd = (inp & m) | (latch & ~dir);
    end
endfunction

integer k;
always @(posedge clk) begin
    game_reset <= 0;
    if (reset) begin
        for (k = 0; k < 5; k = k + 1) begin latch1[k] <= 0; latch2[k] <= 0; dir1[k] <= 8'hff; dir2[k] <= 8'hff; end
        cart_sel <= 0; portd <= 0; porte <= 0;
    end else if (mem_we && (io1_cs || io2_cs)) begin
        if (io_off < 3'd5) begin
            if (io1_cs) latch1[io_off] <= (io_off == 3'd4) ? {4'd0, zdo[3:0]} : zdo;
            else        latch2[io_off] <= (io_off == 3'd4) ? {4'd0, zdo[3:0]} : zdo;
            if (io1_cs && io_off == 3'd4) begin               // cart select (MAME: io1 out_porte -> switch_cart)
                cart_sel <= zdo[2:0] & ~dir1[4][2:0];
                game_reset <= 1;
            end
            if (io2_cs && io_off == 3'd3) portd <= zdo & ~dir2[3];
            if (io2_cs && io_off == 3'd4) porte <= zdo[3:0] & ~dir2[4][3:0];
        end else if (io_off == 3'd6) begin
            for (k = 0; k < 4; k = k + 1)
                if (io1_cs) dir1[k] <= {{4{zdo[2*k+1]}}, {4{zdo[2*k]}}};
                else        dir2[k] <= {{4{zdo[2*k+1]}}, {4{zdo[2*k]}}};
        end else if (io_off == 3'd7) begin
            if (io1_cs) dir1[4] <= {4'hf, zdo[3:0]};
            else        dir2[4] <= {4'hf, zdo[3:0]};
        end
    end
end

wire [7:0] io_rd_data = (io_off > 3'd4) ? 8'h00 :
                        io1_cs ? cxd_rd(latch1[io_off], dir1[io_off], in1[io_off], io_off == 3'd4)
                               : cxd_rd(latch2[io_off], dir2[io_off], in2[io_off], io_off == 3'd4);

// ------------------------------------------------------------- I/O ports
reg  [7:0] port3f;
// PAL 315-5346 (IC14): the menu VDP/PSG only see I/O cycles while io2 port D bit 7 = 1. With bit 7 = 0 every I/O
// cycle goes to the Mega Drive Z80 bus (the BIOS uses that only for the TIME UP screen, on the main monitor).
wire       pd7       = portd[7];
wire       vdp_cs_io = ~iorq_n & m1_n & (A[7:6] == 2'b10) & pd7;     // 80-bf: VDP data/control
wire       cnt_cs_io = ~iorq_n & m1_n & (A[7:6] == 2'b01) & pd7;     // 40-7f: counters (read) / PSG (write)
wire [7:0] vdp_dout;

always @(posedge clk) if (reset) port3f <= 0; else if (io_we && A[7:0] == 8'h3f) port3f <= zdo;

// pads as MAME bios_joypad_r: dc = P1 bits 5-0 + P2 bits 1-0, dd = P2 bits 5-2 | f0; 3f == 55 reads the A keys
wire [7:0] pad_dc = (port3f == 8'h55) ? ({2'b11, 1'b1, pad1_a, 1'b1, pad2_a, 2'b11} | 8'heb) : {pad2[1:0], pad1};
wire [7:0] pad_dd = (port3f == 8'h55) ? ({2'b11, 1'b1, pad1_a, 1'b1, pad2_a, 2'b11} | 8'heb) : {4'hf, pad2[5:2]};

always @(*) begin
    zdi = 8'h00;     // unmapped reads (MAME returns 0)
    if (~mreq_n) begin
        casez (A)
            16'b00??_????_????_????: zdi = (A[13:12] == 2'b11) ? bram_q : bios_q;   // 0000-2fff ROM, 3000-3fff banked RAM
            16'b010?_????_????_????: zdi = ram_q;
            16'b0110_01??_????_????: zdi = io1_cs ? io_rd_data : 8'h00;
            16'b0110_10??_????_????: zdi = io2_cs ? io_rd_data : 8'h00;
            16'b0111_0???_????_????: zdi = bios_q;                                   // 7000-77ff
            16'b100?_????_????_????: zdi = (win_ins && win_a[0] && cart_sel == 3'd0) ? instr_q : 8'h00;
            default: zdi = 8'h00;
        endcase
    end else if (~iorq_n) begin
        if (vdp_cs_io || cnt_cs_io) zdi = vdp_dout;
        else if (A[7:0] == 8'hdc) zdi = pad_dc;
        else if (A[7:0] == 8'hdd) zdi = pad_dd;
    end
end

// ------------------------------------------------------------- TIME UP on the main monitor
// The BIOS draws TIME UP with port D bit 7 = 0, i.e. into the Mega Drive VDP (switched to Mode 4), so it
// shows on the main monitor; the menu VDP is untouched (MAME sends these writes to the menu VDP and then hangs
// because its frame IRQ was turned off). Here: shadow the control port for those writes; TIME UP is shown from
// the BIOS turning that display on (register 1 bit 6) until the game side is restarted (cart select).
reg       md_ctl_first;
reg [7:0] md_ctl_lo;
always @(posedge clk) begin
    if (reset) begin md_ctl_first <= 0; timeup <= 0; end
    else begin
        if (io_we && !pd7 && A[7:6] == 2'b10 && A[0]) begin
            if (!md_ctl_first) begin md_ctl_lo <= zdo; md_ctl_first <= 1; end
            else begin
                md_ctl_first <= 0;
                if (zdo == 8'h81) timeup <= md_ctl_lo[6];
            end
        end
        if (io_we && !pd7 && A[7:6] == 2'b10 && !A[0]) md_ctl_first <= 0;
        // the BIOS ends TIME UP by resetting the game side (port E bit 3 low): the game's VDP restarts in another
        // mode, so stop drawing the text there (Tom, test f: a stretched copy for ~0.4 s)
        if (game_reset || !porte[3]) timeup <= 0;
    end
end

wire [8:0] mh, mv;
wire [3:0] tu_row = tu_y[3:0];
    // "TIME UP" text, 108x13 at (74,98) of the 256x224 window, from MAME's render of the BIOS writes
    reg [107:0] tu_bits;
    always @(*) case (tu_row)
        4'd0: tu_bits = 108'b111111111111100000011111110000111111000011111000111111111111000000000000000000001111100001111000111111111110;
        4'd1: tu_bits = 108'b111111111111100000011111110000111111000011111000111111111111000000000000000000001111100001111000111111111111;
        4'd2: tu_bits = 108'b110001110001100000000111000000011110000001110000011100000011000000000000000000000111000000110000011100000111;
        4'd3: tu_bits = 108'b100001110000100000000111000000011111000011110000011100000001000000000000000000000111000000110000011100000011;
        4'd4: tu_bits = 108'b000001110000000000000111000000011011000010110000011100000001000000000000000000000111000000110000011100000011;
        4'd5: tu_bits = 108'b000001110000000000000111000000011011000110110000011100010000000000000000000000000111000000110000011100000111;
        4'd6: tu_bits = 108'b000001110000000000000111000000011011100110110000011111110000000000000000000000000111000000110000011111111111;
        4'd7: tu_bits = 108'b000001110000000000000111000000011001101100110000011111110000000000000000000000000111000000110000011111111110;
        4'd8: tu_bits = 108'b000001110000000000000111000000011001101100110000011100010001000000000000000000000111000000110000011100000000;
        4'd9: tu_bits = 108'b000001110000000000000111000000011000111000110000011100000001000000000000000000000111000000110000011100000000;
        4'd10: tu_bits = 108'b000001110000000000000111000000011000111000110000011100000011000000000000000000000011100001110000011100000000;
        4'd11: tu_bits = 108'b001111111110000000011111110000111110110001111000111111111111000000000000000000000011111111100000111110000000;
        4'd12: tu_bits = 108'b001111111110000000011111110000111110010001111000111111111111000000000000000000000000111111000000111110000000;
        default: tu_bits = 108'd0;
    endcase
assign tu_px = tu_y < 9'd13 && tu_x < 9'd108 && tu_bits[107 - tu_x];

// ------------------------------------------------------------- menu PSG (ports 40-7f, writes)
jt89 psg (
    .rst(reset), .clk(clk), .clk_en(zcen),
    .wr_n(~(io_we && A[7:6] == 2'b01)), .cs_n(1'b0), .din(zdo),
    .sound(snd), .ready()
);

// ------------------------------------------------------------- menu VDP
mt_vdp4 vdp (
    .clk(clk), .rst(reset), .ce_pix(ce_pix),
    .cs(vdp_cs_io | cnt_cs_io), .sel_cnt(cnt_cs_io),
    .rd(rd_edge & ~iorq_n), .wr(io_we & vdp_cs_io), .a0(A[0]),
    .din(zdo), .dout(vdp_dout), .irq_n(vdp_irq_n),
    .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .hblank(hblank), .vblank(vblank),
    .hpos(mh), .vpos(mv)
);

endmodule
