/*  mp_bios.sv - Sega Mega Play BIOS side: Z80, BIOS ROM, RAMs, two CXD1095 I/O chips, overlay VDP
 *
 *  Copyright (C) 2026 TomSVR. Written for the TomSVR Mega Play core (built from the Mega-Tech core, MEGAPLAY).
 *  Memory map, I/O and behaviour follow MAME src/mame/sega/megaplay.cpp (BSD-3-Clause, David Haywood) and
 *  src/devices/machine/cxd1095.cpp (BSD-3-Clause, AJR). MAME says itself that the CPU communication is not
 *  fully understood; the parts taken from it unchanged are marked "(MAME)".
 *
 *  This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
 *  Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
 *  option) any later version.
 *
 *  Z80 map: 0000-3fff BIOS ROM (first 16 kB) | 4000-5fff RAM | 6000 bank shift register | 6200 io1 | 6400 io2 |
 *  6600 slot register | 6800-77ff RAM | 8000-ffff window:
 *    "ROM mode" (after an io1 port D write): BIOS ROM bank io1 D[7:6] (4 x 32 kB)
 *    "game mode" (after 9 bank writes, or io2 port D bit 4 = 0):
 *      io1 port E bit 3 = 1: 8000-9fff IC37 RAM bank io1 D[1:0], a000-bfff IC36 RAM (shared with the game)
 *      else the 68000 space at the bank address: cart ROM, the instruction ROM at 0x300000 (both bytes)
 *  The BIOS ROM banks, the cart ROM and the instruction ROM are read from SDRAM (the Z80 waits).
 *  IC36 (8 kB) is also the game Z80's 2000-3fff and the 68000's a02000-a03fff (MAME), port B here.
 *  The overlay VDP picture goes over the game picture where its colour index bits 3-0 are not 0 (MAME y1).
 *  Not modelled yet: the window's MD I/O area a10000-a1001f (MAME passes it to the 68000 I/O chip).
 */
module mp_bios (
    input             clk,        // 53.693175 MHz (master clock)
    input             reset,

    // first 16 kB of the BIOS ROM (ioctl, same clk); all of it is in SDRAM as well
    input             dl,
    input      [24:0] dl_addr,
    input      [15:0] dl_data,    // WIDE ioctl: [7:0] = byte at dl_addr, [15:8] = byte at dl_addr+1
    input             dl_wr,

    // NVRAM (RAM 4000-5fff), as mt_bios
    input             nv_dl,
    input             nv_wr,
    input      [12:0] nv_addr,
    input      [15:0] nv_din,
    output     [15:0] nv_dout,
    output            nv_chg,

    // SDRAM reads for the window (word address, word = {byte 2n, byte 2n+1}); req toggles, ack follows
    //   BIOS ROM byte b:  0x800000 + b/2    instruction ROM byte b: 0x810000 + b/2    cart byte b: b/2
    output reg [23:0] rom_wa,
    output reg        rom_req,
    input             rom_ack,
    input      [15:0] rom_data,

    // cabinet inputs, active high
    input             coin1, coin2, service_coin, start1, start2,
    input             sel_btn, service,
    input       [7:0] dsw0, dsw1,

    // 4-slot board (any of slots 2-4 loaded): slot select io1 port D bits 1-0 picks the cart for the game side and
    // the window, 6600 bit 0 reads back port D bit 0 (the BIOS's board check at 0366), 6402 bits 3-0 = cart present
    // per slot, active low (read at 06df and 207b), DSW nibbles: 6201 = slots 2|1, 6202 = slots 4|3 (BIOS 1444).
    // These are taken from what the BIOS code expects; MAME only has the 1-slot board.
    input             four_slot,
    input       [3:0] present,
    input      [11:0] dsw_x,      // DSW nibbles of slots 4, 3, 2
    output      [1:0] slot,       // cart the game side runs

    // game side
    output      [1:0] start_n,    // P1/P2 Start lines of the game pads (io1 port D bits 4/5, (MAME))
    output reg        game_reset, // one clk pulse: 68000 reset (io2 port E bits 3-2 00 -> 11, (MAME))
    input       [2:0] exp_lo,     // game I/O port C (EXT) bits 2-0, written by the 68000
    output      [7:3] exp_hi,     // game I/O port C bits 7-3, from the BIOS (MAME io_exp_data)

    // IC36, port B (game Z80 bus 2000-3fff), own clock
    input             zb_clk,
    input      [12:0] zb_a,
    input       [7:0] zb_d,
    input             zb_we,
    output logic [7:0] zb_q,

    // overlay video, locked to the game picture
    output      [1:0] r, g, b,
    output            y1,
    output            hs, vs, hblank, vblank,
    output            ce_pix,
    input             sync_tgl,   // toggles at the game picture's first active pixel (other clock)

    // overlay VDP sound: SN76489 of the 315-5246 (jt89 by Jose Tejada, GPL-3)
    output signed [10:0] snd
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
wire        rom_wait;

`ifdef SIM_T80V
T80s z80 (
`else
T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80 (
`endif
    .RESET_n(~reset), .CLK(clk), .CEN(zcen),
    .WAIT_n(~rom_wait), .INT_n(vdp_irq_n), .NMI_n(1'b1), .BUSRQ_n(1'b1),
    .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
    .RFSH_n(), .HALT_n(), .BUSAK_n(),
    .A(A), .DI(zdi), .DO(zdo)
`ifdef SIM_T80V
    , .OUT0(1'b0), .REG(), .DIRSet(1'b0), .DIR(230'd0), .ISet_out()
`endif
);

wire mem_rd = ~mreq_n & ~rd_n;
reg  wr_d;
always @(posedge clk) wr_d <= ~wr_n;
wire wr_edge = ~wr_n & ~wr_d;
wire mem_we  = ~mreq_n & wr_edge;
assign nv_chg = mem_we && A[15:12] == 4'h5 && A[11:9] != 3'b111;
wire io_we   = ~iorq_n & wr_edge;
reg  rd_d;
always @(posedge clk) rd_d <= ~rd_n;
wire rd_edge = ~rd_n & ~rd_d;

// ------------------------------------------------------------- memories
reg  [7:0] bios_rom [0:16383];
reg  [7:0] ram3     [0:4095];      // 6800-77ff (MAME ic3_ram)
reg  [7:0] ic37     [0:32767];     // 4 x 8 kB (MAME ic37_ram, banked by io1 D[1:0])
reg  [7:0] bios_q, ram3_q, ic37_q;

// download: two bytes per WIDE ioctl word, written on two consecutive clocks
reg        dl_ph1, dl_ph2;
reg [15:0] dl_w;
reg [13:0] dl_a;
always @(posedge clk) begin
    dl_ph1 <= 0;
    dl_ph2 <= dl_ph1;
    if (dl & dl_wr & ~|dl_addr[24:14]) begin dl_ph1 <= 1; dl_w <= dl_data; dl_a <= {dl_addr[13:1], 1'b0}; end
end
wire        rom_we = dl_ph1 | dl_ph2;
wire [13:0] rom_wa_dl = dl_ph1 ? dl_a : (dl_a | 14'd1);
wire  [7:0] rom_wd = dl_ph1 ? dl_w[7:0] : dl_w[15:8];
always @(posedge clk) if (rom_we) bios_rom[rom_wa_dl] <= rom_wd;

// ------------------------------------------------------------- bank / mode registers (MAME)
reg  [23:0] bank_addr;      // 6000: 9-bit shift register, window base
reg   [3:0] readpos;        // 6000 writes since the last 9 (MAME m_readpos)
reg         bios_mode;      // 1 = ROM mode
reg   [7:0] bios_bank;      // io1 port D
reg   [3:0] bios_width;     // io1 port E (4-bit port)
reg   [7:0] r6403;          // io2 port D
reg   [3:0] r6404;          // io2 port E
reg   [7:0] r6600;
reg   [7:0] io_exp;         // bits 2-0 from the 68000, 7-3 from io1 E / io2 C writes

wire [23:0] full_a = bank_addr + {9'd0, A[14:0]};
wire        win    = A[15];
wire        win_lo = ~full_a[23] & ~full_a[22];                          // 000000-3fffff
wire        w_rom  = win & win_lo & bios_mode;                           // BIOS ROM bank
wire        w_ram  = win & win_lo & ~bios_mode & bios_width[3];          // IC37 / IC36
wire        w_ic36 = w_ram & (A[14:0] >= 15'h2000);
wire        w_game = win & win_lo & ~bios_mode & ~bios_width[3];         // 68000 space: cart / instruction ROM
wire        w_ins  = w_game & (full_a[23:16] == 8'h30);

assign start_n = bios_bank[5:4];
wire [1:0] sl = four_slot ? bios_bank[1:0] : 2'd0;
assign slot = sl;
assign exp_hi  = io_exp[7:3];

// ------------------------------------------------------------- SDRAM reads (BIOS ROM banks, cart, instructions)
// SDRAM word = {byte 2n, byte 2n+1}: an odd byte is the low half
wire [23:0] want_wa = w_rom ? (24'h800000 | {8'd0, bios_bank[7:6], A[14:1]}) :  // BIOS byte bank*32k + A[14:0]
                      w_ins ? (24'h810000 | {8'd0, sl, full_a[15:2]}) :       // instruction byte (a - 300000) / 2
                      four_slot ? {2'd0, sl, full_a[20:1]} :                  // cart, 2 MB per slot
                              {3'd0, full_a[21:1]};                            // cart (slot 0)
wire        want_lo = w_rom ? A[0] : w_ins ? full_a[1] : full_a[0];
wire        rom_rd  = mem_rd & (w_rom | w_game);
reg         rbusy, rhave, rsel;
reg   [1:0] rack_s;
reg   [7:0] rom_q;
always @(posedge clk) begin
    rack_s <= {rack_s[0], rom_ack};
    if (reset) begin rbusy <= 0; rhave <= 0; end
    else begin
        if (~mem_rd) rhave <= 0;
        if (rom_rd & ~rbusy & ~rhave) begin
            rom_wa <= want_wa; rsel <= want_lo; rom_req <= ~rom_req; rbusy <= 1;
        end
        if (rbusy && rom_req == rack_s[1]) begin
            rbusy <= 0; rhave <= 1;
            rom_q <= rsel ? rom_data[7:0] : rom_data[15:8];
        end
    end
end
assign rom_wait = rom_rd & ~rhave;

// ------------------------------------------------------------- RAMs
wire [11:0] r3a   = {~A[11], A[10:0]};                     // 6800-77ff -> 000-fff
wire        r3_cs = A[15:11] == 5'b01101 || A[15:11] == 5'b01110;
always @(posedge clk) begin
    bios_q <= bios_rom[A[13:0]];
    ram3_q <= ram3[r3a];
    ic37_q <= ic37[{bios_bank[1:0], A[12:0]}];
    if (mem_we && r3_cs)            ram3[r3a] <= zdo;
    if (mem_we && w_ram && !w_ic36) ic37[{bios_bank[1:0], A[12:0]}] <= zdo;
end

// IC36: port A = BIOS window a000-bfff (MAME offset - 0x2000), port B = game Z80 bus 2000-3fff
wire [7:0] ic36_q;
`ifdef VERILATOR
reg  [7:0] ic36 [0:8191];
reg  [7:0] ic36_qr;
assign ic36_q = ic36_qr;
always @(posedge clk) begin
    ic36_qr <= ic36[A[12:0]];
    if (mem_we && w_ic36) ic36[A[12:0]] <= zdo;
end
always @(posedge zb_clk) begin
    zb_q <= ic36[zb_a];
    if (zb_we) ic36[zb_a] <= zb_d;
end
`else
// two clocks (clk_sys / clk_md): Quartus does not infer this, use the altsyncram wrapper
dpram_difclk #(13,8,13,8) ic36_ram (
    .clock_a(clk),    .address_a(A[12:0]), .data_a(zdo),  .wren_a(mem_we & w_ic36), .q_a(ic36_q),
    .clock_b(zb_clk), .address_b(zb_a),    .data_b(zb_d), .wren_b(zb_we),           .q_b(zb_q)
);
`endif

// RAM 4000-5fff = NVRAM, one port (as mt_bios)
reg  [7:0] ram [0:8191];
reg  [7:0] ram_q;
reg        nv_ph1, nv_ph2;
reg [15:0] nv_w;
reg [12:0] nv_a;
always @(posedge clk) begin
    nv_ph1 <= 0;
    nv_ph2 <= nv_ph1;
    if (nv_dl & nv_wr) begin nv_ph1 <= 1; nv_w <= nv_din; nv_a <= {nv_addr[12:1], 1'b0}; end
end
wire        nv_we  = nv_ph1 | nv_ph2;
wire        nv_rs  = ~nv_we & (zdiv == 4'd5 || zdiv == 4'd6);
wire [12:0] ram_a  = nv_we ? (nv_ph1 ? nv_a : (nv_a | 13'd1)) : nv_rs ? {nv_addr[12:1], zdiv == 4'd6} : A[12:0];
wire  [7:0] ram_d  = nv_we ? (nv_ph1 ? nv_w[7:0] : nv_w[15:8]) : zdo;
wire        ram_we = nv_we | (mem_we && A[15:13] == 3'b010);
always @(posedge clk) begin
    ram_q <= ram[ram_a];
    if (ram_we) ram[ram_a] <= ram_d;
end
reg [7:0] nv_lo, nv_hi;
always @(posedge clk) begin
    if (zdiv == 4'd6) nv_lo <= ram_q;
    if (zdiv == 4'd7) nv_hi <= ram_q;
end
assign nv_dout = {nv_hi, nv_lo};

// ------------------------------------------------------------- CXD1095 x2 (MAME model, as mt_bios)
reg [7:0] latch1 [0:4], latch2 [0:4];
reg [7:0] dir1   [0:4], dir2   [0:4];   // 1 = input
wire [7:0] in1 [0:4];
wire [7:0] in2 [0:4];
// io1: A = DSW0 (coin slots), B = DSW1 (game settings), E = io_exp (MAME bios_6204_r)
assign in1[0] = dsw0;
assign in1[1] = four_slot ? {dsw_x[3:0], dsw1[3:0]} : dsw1;
assign in1[2] = four_slot ? dsw_x[11:4] : 8'h00; assign in1[3] = 8'h00; assign in1[4] = io_exp;
// io2: A = TEST (0 Select, 7 service, both active low; 4-5 unknown active low = 1), B = COIN (0/1 coins, 4 service
// coin, 6/7 starts, active low; 5 unknown active low = 1), C = io_exp (6402), E bit 0 = io2 port D bit 4 (6404_r)
assign in2[0] = {~service, 1'b0, 2'b11, 3'b000, ~sel_btn};                       // idle b1 (MAME trace)
assign in2[1] = {~start2, ~start1, 1'b1, ~service_coin, 2'b00, ~coin2, ~coin1};   // idle f3
assign in2[2] = four_slot ? {io_exp[7:4], ~present} : io_exp; assign in2[3] = 8'h00; assign in2[4] = {7'd0, r6403[4]};

wire       io1_cs = (A[15:3] == 13'h0c40);   // 6200-6207
wire       io2_cs = (A[15:3] == 13'h0c80);   // 6400-6407
wire [2:0] io_off = A[2:0];

function [7:0] cxd_rd(input [7:0] latch, input [7:0] dir, input [7:0] inp, input is_e);
    reg [7:0] m;
    begin
        m = is_e ? (dir & 8'h0f) : dir;
        cxd_rd = (inp & m) | (latch & ~dir);
    end
endfunction

wire [7:0] wv = zdo;
integer k;
always @(posedge clk) begin
    game_reset <= 0;
    if (reset) begin
        for (k = 0; k < 5; k = k + 1) begin latch1[k] <= 0; latch2[k] <= 0; dir1[k] <= 8'hff; dir2[k] <= 8'hff; end
        bank_addr <= 0; readpos <= 4'd1; bios_mode <= 1; bios_bank <= 8'hff; bios_width <= 0;
        r6403 <= 0; r6404 <= 0; r6600 <= 0; io_exp <= 0;
    end else begin
        io_exp[2:0] <= exp_lo;
        if (mem_we && A == 16'h6000) begin                     // MAME game_w
            bank_addr <= {zdo[0], bank_addr[23:16], 15'd0};
            if (readpos == 4'd9) begin bios_mode <= 0; readpos <= 4'd1; end
            else readpos <= readpos + 4'd1;
        end
        if (mem_we && A == 16'h6600) r6600 <= zdo;
        if (mem_we && (io1_cs || io2_cs)) begin
            if (io_off < 3'd5) begin
                if (io1_cs) latch1[io_off] <= (io_off == 3'd4) ? {4'd0, zdo[3:0]} : zdo;
                else        latch2[io_off] <= (io_off == 3'd4) ? {4'd0, zdo[3:0]} : zdo;
                if (io1_cs && io_off == 3'd3) begin bios_bank <= zdo | dir1[3]; bios_mode <= 1; end   // banksel
                if (io1_cs && io_off == 3'd4) begin                                                    // width
                    bios_width <= zdo[3:0] & ~dir1[4][3:0];
                    io_exp[7:3] <= {4'd0, zdo[3] & ~dir1[4][3]};
                end
                if (io2_cs && io_off == 3'd2) io_exp[7:3] <= {2'b00, zdo[6:4] & ~dir2[2][6:4]};       // 6402
                if (io2_cs && io_off == 3'd3) begin r6403 <= zdo & ~dir2[3]; bios_mode <= zdo[4] | dir2[3][4]; end
                if (io2_cs && io_off == 3'd4) begin                                                    // 6404
                    r6404 <= zdo[3:0] & ~dir2[4][3:0];
                    if (r6404[3:2] == 2'b00 && (zdo[3:2] & ~dir2[4][3:2]) == 2'b11) game_reset <= 1;
                end
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
end

wire [7:0] io_rd_data = (io_off > 3'd4) ? 8'h00 :
                        io1_cs ? cxd_rd(latch1[io_off], dir1[io_off], in1[io_off], io_off == 3'd4)
                               : cxd_rd(latch2[io_off], dir2[io_off], in2[io_off], io_off == 3'd4);

// ------------------------------------------------------------- I/O ports (MAME megaplay_bios_io_map)
wire       vdp_cs_io = ~iorq_n & m1_n & (A[7:6] == 2'b10);     // 80-bf: VDP data/control
wire       cnt_cs_io = ~iorq_n & m1_n & (A[7:6] == 2'b01);     // 40-7f: counters (read) / PSG (write)
wire [7:0] vdp_dout;

always @(*) begin
    zdi = 8'h00;
    if (~mreq_n) begin
        casez (A)
            16'b00??_????_????_????: zdi = bios_q;                                  // 0000-3fff
            16'b010?_????_????_????: zdi = ram_q;                                   // 4000-5fff
            16'b0110_0010_0000_0???: zdi = io_rd_data;                              // 6200-6207
            16'b0110_0100_0000_0???: zdi = io_rd_data;                              // 6400-6407
            16'b0110_0110_0000_0000: zdi = four_slot ? {r6600[7:1], bios_bank[0]} : r6600;
            16'b0110_1???_????_????,
            16'b0111_0???_????_????: zdi = ram3_q;                                 // 6800-77ff
            16'b1???_????_????_????: zdi = w_ic36 ? ic36_q : w_ram ? ic37_q : (w_rom | w_game) ? rom_q : 8'h00;
            default: zdi = 8'h00;
        endcase
    end else if (~iorq_n) begin
        if (vdp_cs_io || cnt_cs_io) zdi = vdp_dout;
    end
end

// ------------------------------------------------------------- overlay PSG (port 7f, mirrored over 40-7f)
jt89 psg (
    .rst(reset), .clk(clk), .clk_en(zcen),
    .wr_n(~(io_we && A[7:6] == 2'b01)), .cs_n(1'b0), .din(zdo),
    .sound(snd), .ready()
);

// ------------------------------------------------------------- overlay VDP, phase-locked to the game picture
reg [2:0] sync_s;
always @(posedge clk) sync_s <= {sync_s[1:0], sync_tgl};
wire vdp_sync = sync_s[2] ^ sync_s[1];

mt_vdp4 vdp (
    .clk(clk), .rst(reset), .ce_pix(ce_pix), .sync(vdp_sync),
    .cs(vdp_cs_io | cnt_cs_io), .sel_cnt(cnt_cs_io),
    .rd(rd_edge & ~iorq_n), .wr(io_we & vdp_cs_io), .a0(A[0]),
    .din(zdo), .dout(vdp_dout), .irq_n(vdp_irq_n),
    .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .hblank(hblank), .vblank(vblank),
    .hpos(), .vpos(), .disp_on(), .y1(y1)
);

endmodule
