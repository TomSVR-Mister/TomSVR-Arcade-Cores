/*  mt_vdp4.v - Mode 4 video for the Mega-Tech menu screen (Sega 315-5246 VDP, "SMS2" VDP)
 *
 *  Copyright (C) 2026 TomSVR. Written for the TomSVR Mega-Tech core.
 *  Behaviour taken from MAME src/devices/video/315_5124.cpp (BSD-3-Clause, David Haywood, Charles MacDonald,
 *  Enik Land): Mode 4 background, 64 sprites (8 per line), 224-line mode, CPU ports, counters, interrupts.
 *  Only what the Mega-Tech BIOS needs: Mode 4 (192/224 lines), NTSC 342 x 262 timing. No TMS9918 modes,
 *  no PSG (separate), no sprite collision.
 *
 *  This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
 *  Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
 *  option) any later version.
 *
 *  Timing: ce_pix = one pixel (MASTER/10 = 5.37 MHz on Mega-Tech). The next line is drawn into a line buffer
 *  during the current line by a state machine running on every clk, so clk must be at least ~6x ce_pix.
 *  Line counter vcnt: 0..223 active (224-line mode), 0..191 in 192-line mode, total 262 lines.
 */
module mt_vdp4 #(parameter SMALL = 0) (   // SMALL = 1: 12 kB VRAM for the BIOS TEST MODE screens (see vmap)
    input             clk,
    input             rst,
    input             ce_pix,
    input             sync,        // one clk pulse: next pixel is the first active pixel (side-by-side lock)

    // CPU port (Z80): a0 = 0 data, 1 control. sel_cnt reads the V (a0=0) / H (a0=1) counters (ports 40/41)
    input             cs,
    input             sel_cnt,
    input             rd,          // one clk pulse per access
    input             wr,
    input             a0,
    input       [7:0] din,
    output reg  [7:0] dout,
    output            irq_n,

    // video
    output      [1:0] r,
    output      [1:0] g,
    output      [1:0] b,
    output reg        hs,
    output reg        vs,
    output reg        hblank,
    output reg        vblank,
    output      [8:0] hpos,
    output      [8:0] vpos,
    output            disp_on      // register 1 bit 6
);

// ---------------------------------------------------------------- registers and CPU interface
reg  [7:0] R[0:10];
reg [13:0] addr;
reg  [1:0] code;
reg        latch_first;   // 1: next control write is the second byte
reg  [7:0] latch_lo;
reg  [7:0] rbuf;
(* ramstyle = "logic" *) reg  [5:0] cram[0:31];
reg        vint_flag, line_flag, spr_ovr;
reg  [7:0] stat_q = 8'h1f;

wire       m224   = R[0][1] & R[1][4];               // 224-line mode (M2 + M1 with M4)
wire       disp   = R[1][6];
assign     disp_on = disp;
wire [8:0] lines  = m224 ? 9'd224 : 9'd192;

// VRAM: port A CPU, port B renderer
// SMALL: the TEST MODE screens use VRAM 0000-13ff, 2a00-36ff and 3800-3fff only (logged in sim/bios):
// 2000-3fff is stored at 1000-2fff, so 12 kB hold all three (2000-27ff and 1800-1fff are never written)
localparam VSIZE = SMALL ? 12288 : 16384;
function [13:0] vmap(input [13:0] a);
    vmap = (SMALL && a[13]) ? a - 14'h1000 : a;
endfunction
reg  [7:0] vram[0:VSIZE-1];
reg  [7:0] vq_cpu, vq;
reg [13:0] va_r;
reg        vwe;
reg  [7:0] vdin;

reg  [8:0] h, v;
`ifdef SIM_VDPLOG
integer fcount = 0;
always @(posedge clk) if (ce_pix && h == 9'd0 && v == 9'd0) fcount <= fcount + 1;
`endif
wire [8:0] v16 = v + 9'd16;
wire [8:0] wy  = m224 ? v : (v16 >= 9'd262 ? v16 - 9'd262 : v16);   // row in the 224-line output window
assign hpos = h;
assign vpos = v;

// VDP counters as MAME (NTSC): V 00-DA/EA then jump back; H = (hpos - 46) / 2 of the previous pixel
wire [7:0] vc = m224 ? (v <= 9'd234 ? v[7:0] : v[7:0] - 8'd6) : (v <= 9'd218 ? v[7:0] : v[7:0] - 8'd6);
reg  [7:0] hc_latch;

integer i;
reg rd_pending;
always @(posedge clk) begin
    vwe <= 0;
    if (rst) begin
        latch_first <= 0; code <= 0; addr <= 0; rbuf <= 0;
        for (i = 0; i < 11; i = i + 1) R[i] <= 0;
        rd_pending <= 0;
    end else begin
        if (rd_pending) begin rbuf <= vq_cpu; rd_pending <= 0; end
        if (cs & wr & ~sel_cnt) begin
            if (a0) begin           // control port
                if (!latch_first) begin
                    latch_lo <= din; latch_first <= 1;
                    addr[7:0] <= din;
                end else begin
                    latch_first <= 0;
                    addr <= {din[5:0], latch_lo};
                    code <= din[7:6];
                    if (din[7:6] == 2'd0) begin   // read setup: prefetch
                        va_r <= {din[5:0], latch_lo}; rd_pending <= 1;
                        addr <= {din[5:0], latch_lo} + 14'd1;
                    end
                    if (din[7:6] == 2'd2 && din[3:0] < 4'd11) R[din[3:0]] <= latch_lo;
`ifdef SIM_VDPLOG
                    if (din[7:6] == 2'd2 && fcount > 2000) $display("vdp f%0d v%0d R%0d=%02x", fcount, v, din[3:0], latch_lo);
`endif
                end
            end else begin          // data port
                latch_first <= 0;
                if (code == 2'd3) cram[addr[4:0]] <= din[5:0];
                else begin vwe <= 1; va_r <= addr; vdin <= din; end
                rbuf <= din;
                addr <= addr + 14'd1;
            end
        end
        if (cs & rd & ~sel_cnt) begin
            latch_first <= 0;
            if (!a0) begin          // data read: buffer, then prefetch next
                va_r <= addr; rd_pending <= 1; addr <= addr + 14'd1;
            end
        end
    end
end

// CPU read data (combinational on the access; the CPU samples it during its read cycle)
always @(*) begin
    if (sel_cnt) dout = a0 ? hc_latch : vc;
    else if (a0) dout = stat_q;
    else dout = rbuf;
end

always @(posedge clk) begin
    if (vwe) vram[vmap(va_r)] <= vdin;
    vq_cpu <= vram[vmap(va_r)];
end

// ---------------------------------------------------------------- timing
reg sync_p;
always @(posedge clk) begin
    if (rst) begin h <= 0; v <= 0; sync_p <= 0; end
    else if (sync) sync_p <= 1;
    if (!rst && ce_pix) begin
        if (sync_p || sync) begin
            sync_p <= 0;
            h <= 0;
            v <= m224 ? 9'd0 : 9'd246;          // wy = 0
        end else if (h == 9'd341) begin
            h <= 0;
            v <= (v == 9'd261) ? 9'd0 : v + 9'd1;
        end else h <= h + 9'd1;
        hc_latch <= (h >= 9'd46) ? (h - 9'd46) >> 1 : 8'd0;
        hblank <= ~(h < 9'd256);
        // fixed 224-line window: in 192-line mode the picture sits 16 lines lower (top/bottom border), as MAME
        vblank <= ~(wy < 9'd224);
        hs <= (h >= 9'd280 && h < 9'd306);
        vs <= (wy >= 9'd243 && wy < 9'd246);
    end
end

// interrupts: frame at the first line after the active area, line counter as MAME
reg [7:0] lcnt;
always @(posedge clk) begin
    if (rst) begin vint_flag <= 0; line_flag <= 0; lcnt <= 8'hff; spr_ovr <= 0; end
    else begin
        if (ce_pix && h == 9'd0) begin
            if (v == lines) vint_flag <= 1;
            if (v <= lines) begin
                if (lcnt == 8'd0) begin lcnt <= R[10]; line_flag <= 1; end
                else lcnt <= lcnt - 8'd1;
            end else lcnt <= R[10];
        end
        if (ovr_set) spr_ovr <= 1;
        // status read: rd is one clk at the start of the CPU's read cycle and the flags clear on it, so the CPU
        // (sampling later in the cycle) gets the value captured here. Reading the live flags returned 0 nearly
        // always: the BIOS TEST MODE loop (polls bit 7 at 1d4c) then missed most joystick and Test presses.
        if (cs & rd & a0 & ~sel_cnt) begin
            stat_q <= {vint_flag, spr_ovr, 1'b0, 5'h1f};
            vint_flag <= 0; line_flag <= 0; spr_ovr <= 0;
        end
    end
end
assign irq_n = ~((vint_flag & R[1][5]) | (line_flag & R[0][4]));

// ---------------------------------------------------------------- line renderer
// line buffers: {bg priority over sprites, 5-bit colour}; buffer (line & 1)
(* ramstyle = "MLAB" *) reg  [5:0] lb0[0:255];
(* ramstyle = "MLAB" *) reg  [5:0] lb1[0:255];   // small RAMs in logic: the M10K blocks are all used
reg  [7:0] lb_wa;
reg  [5:0] lb_wd;
reg        lb_we, lb_sel;
reg  [5:0] lb_q;
reg  [7:0] lb_ra;
always @(posedge clk) begin
    if (lb_we) begin if (lb_sel) lb1[lb_wa] <= lb_wd; else lb0[lb_wa] <= lb_wd; end
end

reg [13:0] ra;          // renderer VRAM address
always @(posedge clk) vq <= vram[vmap(ra)];

localparam S_IDLE=0, S_SPR=1, S_SPRX=2, S_BG=3, S_BGPIX=4, S_SPD=5, S_LEFT=6, S_DONE=7;
reg  [2:0] st;
reg        pal0, ovr_set;
reg  [3:0] step;
reg  [8:0] tl;          // line being drawn
reg  [6:0] si;          // sprite index
reg  [3:0] scount;
reg  [7:0] sx[0:7];
reg  [8:0] stile[0:7];
reg  [2:0] srow[0:7];
reg  [5:0] col;
reg [15:0] ntw;
reg  [7:0] p0, p1, p2, p3;
reg  [3:0] px;
reg  [7:0] sy;
reg  [3:0] ds;          // sprite being drawn (counts down)

wire [13:0] satb   = {R[5][6:1], 8'h00};
wire [13:0] ntb    = m224 ? {R[2][3:2], 12'h700} : {R[2][3:1], 11'h0};
wire  [7:0] xs     = (R[0][6] && tl < 9'd16) ? 8'd0 : R[8];
wire  [7:0] ys     = (R[0][7] && col > 6'd23) ? 8'd0 : R[9];
wire  [8:0] ysum   = {1'b0, tl[7:0]} + {1'b0, ys};
wire  [7:0] brow   = m224 ? ysum[7:0] : (ysum >= 9'd224 ? ysum - 9'd224 : ysum[7:0]);
wire  [4:0] tcol   = col[4:0] - xs[7:3];
wire  [8:0] sh     = R[1][1] ? 9'd16 : 9'd8;
wire  [8:0] sydiff = {1'b0, tl[7:0]} - 9'd1 - (sy >= 8'd240 ? {1'b1, sy} : {1'b0, sy}); // line-1 - y (mod 512)
wire  [3:0] pen    = {p3[7-px[2:0]], p2[7-px[2:0]], p1[7-px[2:0]], p0[7-px[2:0]]};
wire  [2:0] bpx    = ntw[9] ? 3'd7 - px[2:0] : px[2:0];       // h flip
wire  [8:0] bgx    = {1'b0, col[4:0], 3'b000} + {6'd0, xs[2:0]} + {6'd0, bpx};

always @(posedge clk) begin
    lb_we <= 0; ovr_set <= 0;
    if (rst) st <= S_IDLE;
    else case (st)
    S_IDLE: if (ce_pix && h == 9'd0) begin
                tl <= (v == 9'd261) ? 9'd0 : v + 9'd1;
                lb_sel <= (v == 9'd261) ? 1'b0 : ~v[0];
                si <= 0; scount <= 0; step <= 0;
                st <= S_SPR;
            end
    // sprite selection: Y at satb+i, X/N at satb+0x80+2i
    S_SPR:  case (step)
                0: begin ra <= satb + {7'd0, si[5:0]}; step <= 1; end
                1: step <= 2;
                2: begin sy <= vq; step <= 3; end
                3: begin
                    step <= 0;
                    if (!m224 && sy == 8'hd0) st <= S_BG;          // terminator (192-line mode only)
                    else if (sydiff < sh && scount < 4'd8) begin
                        srow[scount[2:0]] <= sydiff[2:0];
                        st <= S_SPRX;
                    end else begin
                        if (sydiff < sh) ovr_set <= 1;
                        if (si == 7'd63) st <= S_BG; else si <= si + 7'd1;
                    end
                end
                default: step <= 0;
            endcase
    S_SPRX: begin
                case (step)
                0: begin ra <= satb + 14'h80 + {6'd0, si[5:0], 1'b0}; step <= 1; end
                1: step <= 2;
                2: begin sx[scount[2:0]] <= R[0][3] ? vq - 8'd8 : vq; ra <= ra + 14'd1; step <= 3; end
                3: step <= 4;
                4: begin
                    stile[scount[2:0]] <= ({R[6][2], (R[1][1] ? {vq[7:1], 1'b0} : vq)}) + {8'd0, (sydiff > 9'd7)};
                    scount <= scount + 4'd1;
                    step <= 0;
                    if (si == 7'd63) st <= S_BG; else begin si <= si + 7'd1; st <= S_SPR; end
                end
                endcase
            end
    // background: 32 columns, name word then 4 pattern bytes, then 8 pixels
    S_BG:   begin
                case (step)
                0: begin col <= 0; step <= 1; end
                1: begin ra <= ntb + {3'd0, brow[7:3], tcol, 1'b0}; step <= 2; end
                2: step <= 3;
                3: begin ntw[7:0] <= vq; ra <= ra + 14'd1; step <= 4; end
                4: step <= 5;
                5: begin ntw[15:8] <= vq; step <= 6; end
                6: begin ra <= {ntw[8:0], (ntw[10] ? 3'd7 - brow[2:0] : brow[2:0]), 2'b00}; step <= 7; end
                7: begin ra <= ra + 14'd1; step <= 8; end
                8: begin p0 <= vq; ra <= ra + 14'd1; step <= 9; end
                9: begin p1 <= vq; ra <= ra + 14'd1; step <= 10; end
                10: begin p2 <= vq; step <= 11; end
                11: begin p3 <= vq; px <= 0; st <= S_BGPIX; end
                endcase
            end
    S_BGPIX: begin
                // pixel px of the tile goes to x = col*8 + fine scroll + (flipped) px
                if (bgx < 9'd256) begin
                    lb_we <= 1; lb_wa <= bgx[7:0];
                    lb_wd <= {ntw[12] & (pen != 0), ntw[11], pen};
                end
                if (col == 0) pal0 <= ntw[11];
                if (px == 4'd7) begin
                    px <= 0;
                    if (col == 6'd31) begin st <= S_LEFT; px <= 0; end
                    else begin col <= col + 6'd1; step <= 1; st <= S_BG; end
                end else px <= px + 4'd1;
            end
    // leftmost pixels not covered by a full tile when scrolled: colour 0 of column 0's palette (as MAME)
    S_LEFT: begin
                if ({1'b0, px[2:0]} < {1'b0, xs[2:0]}) begin
                    lb_we <= 1; lb_wa <= {5'd0, px[2:0]}; lb_wd <= {1'b0, pal0, 4'd0};
                end
                if (px == 4'd7) begin st <= S_SPD; ds <= scount; step <= 0; end
                else px <= px + 4'd1;
            end
    // sprites, last selected first so that lower indexes win
    S_SPD:  begin
                if (ds == 0) st <= S_DONE;
                else case (step)
                0: begin ra <= {stile[ds-1], srow[ds-1], 2'b00}; step <= 1; end
                1: begin ra <= ra + 14'd1; step <= 2; end
                2: begin p0 <= vq; ra <= ra + 14'd1; step <= 3; end
                3: begin p1 <= vq; ra <= ra + 14'd1; step <= 4; end
                4: begin p2 <= vq; step <= 5; end
                5: begin p3 <= vq; px <= 0; step <= 6; end
                6: begin lb_ra <= sx[ds-1] + {5'd0, px[2:0]}; step <= 7; end
                7: step <= 8;
                8: begin
                    // write when the sprite pixel is opaque, on screen, and the background has no priority
                    if (pen != 0 && ({1'b0, sx[ds-1]} + {6'd0, px[2:0]} < 9'd256) && !lb_q[5]) begin
                        lb_we <= 1; lb_wa <= lb_ra; lb_wd <= {1'b0, 1'b1, pen};
                    end
                    if (px == 4'd7) begin ds <= ds - 4'd1; step <= 0; end
                    else begin px <= px + 4'd1; step <= 6; end
                end
                endcase
            end
    S_DONE: st <= S_IDLE;
    endcase
end

// read port of the line buffer being drawn (sprite merge) / being shown (output)
reg [5:0] out_q;
always @(posedge clk) begin
    lb_q  <= lb_sel ? lb1[lb_ra] : lb0[lb_ra];
    out_q <= v[0] ? lb1[h[7:0]] : lb0[h[7:0]];
end

// ---------------------------------------------------------------- output
reg [5:0] pix;
always @(posedge clk) if (ce_pix) begin
    if (!disp || v >= lines || h >= 9'd256 || (R[0][5] && h < 9'd8))
        pix <= cram[{1'b1, R[7][3:0]}];
    else
        pix <= cram[out_q[4:0]];
end
assign r = pix[1:0];
assign g = pix[3:2];
assign b = pix[5:4];

endmodule
