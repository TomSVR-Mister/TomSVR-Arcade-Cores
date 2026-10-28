/*  nss_board.sv - Nintendo Super System: the Z80 BIOS side of the board
 *
 *  Copyright (C) 2026 TomSVR. Written for the TomSVR NSS core.
 *  Memory map, I/O ports and chip behaviour follow nocash's fullsnes NSS chapters (Martin Korth) and
 *  MAME src/mame/nintendo/nss.cpp + src/devices/machine/{rp5h01,m6m80011ap,s3520cf}.cpp (Angelo Salese et al.).
 *
 *  This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
 *  Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
 *  option) any later version.
 *
 *  Z80 (4 MHz) map: 0000-7fff BIOS | 8000-9fff RAM (9000-9fff write protect, port 00 bit 2) | a000 EEPROM in |
 *  c000-dfff INST ROM of the selected slot (upper 8K of the 32K EPROM) | e000-ffff PROM in/out + EEPROM out.
 *  One cart slot is fitted (slot 1); slots 2-3 read as empty.
 */
module nss_board #(
    parameter PROM_DATA_INV = 1      // nocash: PROM data out read inverted (0=High=One); MAME reads it straight
)(
    input             clk,           // 21.47727 MHz (SNES master clock)
    input             reset,

    // ROM download: 00000-07fff BIOS, 08000-09fff INST ROM (upper 8K), 0a000-0a00f PROM, 0c000-0d1ff OSD font
    input             dl_wr,
    input      [16:0] dl_addr,
    input       [7:0] dl_data,

    // EEPROM as NVRAM (128 words; the file holds them little endian)
    input             nv_wr,
    input       [6:0] nv_addr,
    input      [15:0] nv_din,
    output     [15:0] nv_dout,
    output reg        nv_chg,        // EEPROM written by the BIOS

    input      [64:0] rtc,           // MiSTer RTC (BCD: [7:0] sec ... [47:40] year, [55:48] wday), [64] toggles

    // SNES side
    input             snes_vblank,   // NMI on the rising edge (MAME)
    input             snes_vsync,    // port 00 bit 6 (nocash: 0 during vsync)
    input             snes_joy_read, // pulse when the SNES reads its joypads (watchdog)
    input             snes_out2,     // 4016h.W bit 2 (1 = game over)
    output      [7:0] p01,           // port 01 out: 7 joypad enable, 5 mute, 4 P2 ctl, 3-2 slot, 1 run, 0 /reset
    output      [7:0] p03,           // port 03 out: 7-6 layer enables?, 3 LED inst, 2-0 LED game
    output      [1:0] coin_cnt,

    // cabinet inputs, active high
    input       [5:0] pad,           // {B, A, Down, Up, Left, Right} of joypad 1
    input       [6:0] panel,         // {Restart, Page Up, Page Down, Instructions, Game 3, Game 2, Game 1}
    input       [2:0] coin,          // {Service, Coin 2, Coin 1}

    // OSD video: dot timing from the video side
    input             osd_ce,        // OSD dot clock enable (12 OSD dots ~ 8 SNES dots)
    input             osd_hs,        // one clk pulse at line start (hsync)
    input             osd_vs,        // one clk pulse at frame start (vsync), together with osd_hs
    output      [2:0] osd_rgb,       // colour of the OSD pixel (bit0 R, bit1 G, bit2 B)
    output            osd_fg,        // character or border pixel
    output            osd_raster,    // OSD covers the whole raster here (backdrop)
    output     [15:0] osd_reg0, osd_reg7,

    // debug
    output     [15:0] dbg_pc
);

// ------------------------------------------------------------------ Z80
reg  [15:0] zcnt;
reg         zcen;
always @(posedge clk) begin
    zcen <= 0;
    if (zcnt >= 16'd21477 - 16'd4000) begin zcnt <= zcnt + 16'd4000 - 16'd21477; zcen <= 1; end
    else zcnt <= zcnt + 16'd4000;
end

wire [15:0] A;
wire  [7:0] zdo;
reg   [7:0] zdi;
wire m1_n, mreq_n, iorq_n, rd_n, wr_n;
reg  nmi_n;

`ifdef SIM_T80V
T80s z80 (
`else
T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80 (
`endif
    .RESET_n(~reset), .CLK(clk), .CEN(zcen),
    .WAIT_n(1'b1), .INT_n(1'b1), .NMI_n(nmi_n), .BUSRQ_n(1'b1),
    .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
    .RFSH_n(), .HALT_n(), .BUSAK_n(),
    .A(A), .DI(zdi), .DO(zdo)
`ifdef SIM_T80V
    , .OUT0(1'b0), .REG(), .DIRSet(1'b0), .DIR(230'd0), .ISet_out()
`endif
);

reg [15:0] pc_r;
always @(posedge clk) if (~m1_n & ~mreq_n & ~rd_n) pc_r <= A;
assign dbg_pc = pc_r;

reg wr_d;
always @(posedge clk) wr_d <= ~wr_n;
wire wr_edge = ~wr_n & ~wr_d;
wire mem_we  = ~mreq_n & wr_edge;
wire io_we   = ~iorq_n & wr_edge;
reg  rd_d;
always @(posedge clk) rd_d <= ~rd_n;
wire io_rd_edge = ~iorq_n & ~rd_n & ~rd_d & m1_n;

// ------------------------------------------------------------------ memories
reg [7:0] bios[32768];
reg [7:0] inst[8192];
reg [7:0] prom[16];
reg [7:0] ram[8192];
reg [7:0] bios_q, inst_q, ram_q;

always @(posedge clk) begin
    if (dl_wr && dl_addr[16:15] == 2'b00) bios[dl_addr[14:0]] <= dl_data;
    bios_q <= bios[A[14:0]];
end
always @(posedge clk) begin
    if (dl_wr && dl_addr[16:13] == 4'b0100) inst[dl_addr[12:0]] <= dl_data;
    inst_q <= inst[A[12:0]];
end
always @(posedge clk) if (dl_wr && dl_addr[16:4] == 13'h0a00) prom[dl_addr[3:0]] <= dl_data;

reg wp_en;      // port 00 bit 2: RAM 9000-9fff writable
always @(posedge clk) begin
    if (mem_we && A[15:13] == 3'b100 && (~A[12] | wp_en)) ram[A[12:0]] <= zdo;
    ram_q <= ram[A[12:0]];
end

// ------------------------------------------------------------------ ports
reg  [7:0] p01_r, p03_r, p02_r;
reg  [1:0] cc_r;
reg        nmi_en, joy_flag;
assign p01 = p01_r;
assign p03 = p03_r;
assign coin_cnt = cc_r;
wire [1:0] slot = p01_r[3:2];

// NMI: pulse on the SNES vblank rising edge while enabled (MAME nss_vblank_irq)
reg vbl_d;
reg [3:0] nmi_cnt;
always @(posedge clk) begin
    vbl_d <= snes_vblank;
    if (reset) begin nmi_n <= 1; nmi_cnt <= 0; end
    else if (snes_vblank & ~vbl_d & nmi_en) begin nmi_n <= 0; nmi_cnt <= 4'd15; end
    else if (zcen && nmi_cnt != 0) nmi_cnt <= nmi_cnt - 1'd1;
    else if (nmi_cnt == 0) nmi_n <= 1;
end

// RP5H01 security PROM (MAME rp5h01.cpp); written at e000-ffff: bit 4 test, bit 3 clock, bit 0 = /reset
reg [6:0] pcnt;
reg       ptest, pclk_o, preset_o;
// bit order: LSB first with the inverted data out of nocash: the BIOS then decrypts the INST ROM header of all 12
// dumped carts (checked in sim, and on MiSTer). MAME reads MSB first: 5 carts (con3 rob3 smw ssoc sten) fail there.
wire      prom_bit = prom[pcnt[6:3] & (ptest ? 4'hf : 4'h7)][pcnt[2:0]];
// EEPROM / PROM writes
wire e_we = mem_we && A[15:13] == 3'b111;

always @(posedge clk) begin
    if (reset) begin
        pcnt <= 0; ptest <= 0; pclk_o <= 0; preset_o <= 1;
    end else if (e_we) begin
        ptest <= zdo[4];
        // a falling clock edge counts only while reset was already released (nocash: the edge that comes
        // together with the reset release must be ignored)
        if (~preset_o && pclk_o && ~zdo[3]) pcnt <= pcnt + 1'd1;
        pclk_o <= zdo[3];
        preset_o <= ~zdo[0];
        if (~zdo[0]) pcnt <= 0;
    end
end
// slot 1 only has the PROM (MAME); 7-bit counter wraps over the 16 bytes in test mode, 6-bit otherwise
wire [7:0] prom_rd = (slot == 2'd0) ?
    {3'b111, ~pcnt[5], prom_bit ^ PROM_DATA_INV[0], 3'b111} : 8'hff;

// ------------------------------------------------------------------ EEPROM (M6M80011, MAME m6m80011ap.cpp)
wire ee_do;
nss_eeprom eeprom (
    .clk(clk), .reset(reset),
    .we(e_we), .din(zdo),
    .dout(ee_do),
    .nv_wr(nv_wr), .nv_addr(nv_addr), .nv_din(nv_din), .nv_dout(nv_dout), .nv_chg(ee_chg)
);
wire ee_chg;
always @(posedge clk) nv_chg <= ee_chg;

// ------------------------------------------------------------------ RTC (S-3520) + OSD (M50458), port 02
wire p02_we = io_we && A[2:0] == 3'd2;
wire rtc_do;
nss_rtc rtc_i (
    .clk(clk), .reset(reset), .rtc(rtc),
    .we(p02_we), .din(zdo), .dout(rtc_do)
);

nss_osd osd (
    .clk(clk), .reset(reset),
    .dl_wr(dl_wr && dl_addr[16:13] == 4'b0110), .dl_addr(dl_addr[12:0]), .dl_data(dl_data),
    .we(p02_we), .din(zdo),
    .ce(osd_ce), .hs(osd_hs), .vs(osd_vs),
    .rgb(osd_rgb), .fg(osd_fg), .raster(osd_raster),
    .reg0(osd_reg0), .reg7(osd_reg7)
);

// ------------------------------------------------------------------ port writes / reads
always @(posedge clk) begin
    if (reset) begin
        p01_r <= 8'h00; p03_r <= 0; cc_r <= 0; nmi_en <= 0; wp_en <= 0; joy_flag <= 1; p02_r <= 8'hff;
    end else begin
        if (snes_joy_read) joy_flag <= 0;
        if (io_we) case (A[2:0])
            3'd0: begin nmi_en <= zdo[0]; wp_en <= zdo[2]; end
            3'd1: p01_r <= zdo;
            3'd2: p02_r <= zdo;
            3'd3: p03_r <= zdo;
            3'd4: cc_r <= zdo[1:0];
            3'd7: joy_flag <= 1;
            default: ;
        endcase
        if (io_rd_edge && A[2:0] == 3'd7) joy_flag <= 1;
    end
end

wire [7:0] io_q =
    A[2:0] == 3'd0 ? {joy_flag, ~snes_vsync, pad} :
    A[2:0] == 3'd1 ? {~snes_out2, panel} :
    A[2:0] == 3'd2 ? {5'd0, coin} :
    A[2:0] == 3'd3 ? {7'h3f, rtc_do} :
                     8'hff;

always @(*) begin
    if (~iorq_n) zdi = io_q;
    else casez (A[15:13])
        3'b0??: zdi = bios_q;
        3'b100: zdi = ram_q;
        3'b101: zdi = {ee_do, 1'b1, 6'd0};
        3'b110: zdi = slot == 2'd0 ? inst_q : 8'hff;
        3'b111: zdi = prom_rd;
        default: zdi = 8'hff;
    endcase
end

endmodule
