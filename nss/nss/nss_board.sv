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
 *
 *  Cartridges: up to 12 games are loaded ("positions" 0-11, each with its INST ROM, security PROM, SNES ROM size and
 *  RAM size; the SNES ROM itself is in SDRAM at position * 1 MB). Each of the 3 slots holds one of them: the MRA's
 *  default, or the game picked in the OSD (by its fixed game number), taken at reset. An empty slot reads FFh.
 *  Each slot's PROM has its own counter, clocked only while that slot is selected (port 01 bits 3-2).
 */
module nss_board #(
    parameter PROM_DATA_INV = 1      // nocash: PROM data out read inverted (0=High=One); MAME reads it straight
)(
    input             clk,           // 21.47727 MHz (SNES master clock)
    input             reset,

    // ROM download: 00000-07fff BIOS | 08000-091ff OSD font | 0a000-0a0bf game table, 16 bytes per position:
    // +0 present, +1 game number, +2 SNES ROM size (1 KB << n), +3 SNES RAM size (0 = none, else 1 KB << n) |
    // 0a0f0-0a0f2 default game number of slots 1-3 (ff = empty) | 0a100-0a1bf PROMs (16 bytes per position) |
    // 0c000-23fff INST ROMs (upper 8K of each EPROM, 8 KB per position)
    input             dl_wr,
    input      [17:0] dl_addr,
    input       [7:0] dl_data,

    // slot contents: OSD choice per slot (0 = MRA default, 1 = empty, 2-13 = game number 0-11), taken at reset
    input      [11:0] slot_pick,
    // the cartridge in the selected slot, for the SNES side
    output reg        cart_ok,       // a game is in the selected slot
    output reg  [3:0] cart_pos,      // its position (SNES ROM at pos * 1 MB)
    output reg  [3:0] cart_rom_n,
    output reg  [3:0] cart_ram_n,

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
reg [7:0] inst[98304];           // 12 x 8 KB
reg [7:0] prom[192];             // 12 x 16
reg [7:0] ram[8192];
reg [7:0] bios_q, inst_q, ram_q;

// game table
reg        t_present[12];
reg  [3:0] t_id[12], t_rom[12], t_ram[12];
reg  [7:0] t_def[3];

wire dl_inst = dl_addr >= 18'h0c000 && dl_addr < 18'h24000;
wire [17:0] dl_inst_a = dl_addr - 18'h0c000;

always @(posedge clk) begin
    if (dl_wr && dl_addr[17:15] == 3'b000) bios[dl_addr[14:0]] <= dl_data;
    bios_q <= bios[A[14:0]];
end

// slot -> position (resolved at reset, as a cabinet's cartridges don't change while it runs)
reg  [3:0] s_pos[3];
reg  [2:0] s_ok;
wire [1:0] slot;
integer si, pi;
reg [3:0] want;
reg       want_ok, found;
always @(posedge clk) begin
    if (reset) begin
        for (si = 0; si < 3; si = si + 1) begin
            case (slot_pick[si*4 +: 4])
                4'd0:    begin want = t_def[si][3:0]; want_ok = t_def[si] < 8'd12; end
                4'd1:    begin want = 4'd0; want_ok = 0; end
                default: begin want = slot_pick[si*4 +: 4] - 4'd2; want_ok = 1; end
            endcase
            found = 0;
            for (pi = 11; pi >= 0; pi = pi - 1)
                if (want_ok && t_present[pi] && t_id[pi] == want) begin s_pos[si] <= pi[3:0]; found = 1; end
            s_ok[si] <= found;
        end
    end
end

wire       sel_ok  = slot != 2'd3 && s_ok[slot];
wire [3:0] sel_pos = s_pos[slot];
always @(posedge clk) begin
    cart_ok    <= sel_ok;
    cart_pos   <= sel_pos;
    cart_rom_n <= t_rom[sel_pos];
    cart_ram_n <= t_ram[sel_pos];
end

wire [16:0] inst_ra = {sel_pos, 13'd0} + {4'd0, A[12:0]};
always @(posedge clk) begin
    if (dl_wr && dl_inst) inst[dl_inst_a[16:0]] <= dl_data;
    inst_q <= inst[inst_ra];
end
always @(posedge clk) begin
    if (dl_wr && dl_addr[17:8] == 10'h0a1 && dl_addr[7:0] < 8'd192) prom[dl_addr[7:0]] <= dl_data;
    if (dl_wr && dl_addr[17:8] == 10'h0a0) begin
        if (dl_addr[7:4] < 4'd12) case (dl_addr[3:0])
            4'd0: t_present[dl_addr[7:4]] <= dl_data[0];
            4'd1: t_id[dl_addr[7:4]]      <= dl_data[3:0];
            4'd2: t_rom[dl_addr[7:4]]     <= dl_data[3:0];
            4'd3: t_ram[dl_addr[7:4]]     <= dl_data[3:0];
            default: ;
        endcase
        if (dl_addr[7:0] >= 8'hf0 && dl_addr[7:0] <= 8'hf2) t_def[dl_addr[1:0]] <= dl_data;
    end
end

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
assign slot = p01_r[3:2];

// NMI: pulse at the END of the SNES vblank while enabled. MAME pulses it at the vblank start, but then the BIOS
// start-up races: it enables NMI at 02EF, sends the OSD set-up (about 65 lines), waits for a vsync, and only then
// (031A) loads I, which its NMI handler counts down as a software watchdog (I >= 80h: JP 0). Two NMIs in that
// window (about 1 start in 4 with the NMI 11 lines before vsync) make I wrap to FFh, and since JP 0 does not
// clear I, every restart dies the same way: a black screen until a hardware reset. The Z80 /NMI input is
// falling-edge triggered, so an active-high vblank wired to it fires at the vblank end; there the window never
// holds two NMIs. (Found with a start-phase sweep of the BIOS in simulation, matching the PCs seen on MiSTer.)
reg vbl_d;
reg [3:0] nmi_cnt;
always @(posedge clk) begin
    vbl_d <= snes_vblank;
    if (reset) begin nmi_n <= 1; nmi_cnt <= 0; end
    else if (~snes_vblank & vbl_d & nmi_en) begin nmi_n <= 0; nmi_cnt <= 4'd15; end
    else if (zcen && nmi_cnt != 0) nmi_cnt <= nmi_cnt - 1'd1;
    else if (nmi_cnt == 0) nmi_n <= 1;
end

// RP5H01 security PROMs (MAME rp5h01.cpp), one per slot, clocked while their slot is selected;
// written at e000-ffff: bit 4 test, bit 3 clock, bit 0 = /reset
reg [6:0] pcnt[3];
reg [2:0] ptest, pclk_o, preset_o;
wire [1:0] ps = slot == 2'd3 ? 2'd0 : slot;
wire [6:0] pc  = pcnt[ps];
// bit order: LSB first with the inverted data out of nocash: the BIOS then decrypts the INST ROM header of all 12
// dumped carts (checked in sim, and on MiSTer). MAME reads MSB first: 5 carts (con3 rob3 smw ssoc sten) fail there.
wire [7:0] prom_byte = prom[{sel_pos, 4'd0} + {4'd0, pc[6:3] & (ptest[ps] ? 4'hf : 4'h7)}];
wire       prom_bit  = prom_byte[pc[2:0]];
// EEPROM / PROM writes
wire e_we = mem_we && A[15:13] == 3'b111;

integer k;
always @(posedge clk) begin
    if (reset) begin
        for (k = 0; k < 3; k = k + 1) pcnt[k] <= 0;
        ptest <= 0; pclk_o <= 0; preset_o <= 3'b111;
    end else if (e_we && sel_ok) begin
        ptest[ps] <= zdo[4];
        // a falling clock edge counts only while reset was already released (nocash: the edge that comes
        // together with the reset release must be ignored)
        if (~preset_o[ps] && pclk_o[ps] && ~zdo[3]) pcnt[ps] <= pcnt[ps] + 1'd1;
        pclk_o[ps] <= zdo[3];
        preset_o[ps] <= ~zdo[0];
        if (~zdo[0]) pcnt[ps] <= 0;
    end
end
// 7-bit counter wraps over the 16 bytes in test mode, 6-bit otherwise; no cartridge: FFh
wire [7:0] prom_rd = sel_ok ? {3'b111, ~pc[5], prom_bit ^ PROM_DATA_INV[0], 3'b111} : 8'hff;

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
    .dl_wr(dl_wr && dl_addr[17:13] == 5'b00100), .dl_addr(dl_addr[12:0]), .dl_data(dl_data),
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
`ifdef SIM_IOLOG
        if (io_we) $display("IOW %0t %04x %02x pc=%04x nmi=%b", $time, A, zdo, pc_r, nmi_n);
`endif
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
        3'b110: zdi = sel_ok ? inst_q : 8'hff;
        3'b111: zdi = prom_rd;
        default: zdi = 8'hff;
    endcase
end

endmodule
