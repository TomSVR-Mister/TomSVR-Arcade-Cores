/*  nss_osd.sv - Mitsubishi M50458-001SP on-screen display controller, as used by the NSS
 *
 *  Copyright (C) 2026 TomSVR. Written for the TomSVR NSS core.
 *  Registers and character format follow nocash fullsnes ("NSS On-Screen Controller (OSD)") and the M50458
 *  datasheet; the serial protocol follows MAME src/devices/video/m50458.cpp (Angelo Salese). GPL-3.0-or-later.
 *
 *  Serial input (Z80 port 02 writes): bit 7 clock (a bit is taken when it goes low), bit 5 data, bit 4 = reset
 *  (1 = idle; the next 16 bits are an address). Words are 16 bits, LSB first: an address, then data words with
 *  auto increment. 000-11f character RAM (24 x 12), 120-127 registers.
 *  Character word: 6-0 code, 10-8 colour (bit 0 R, 1 G, 2 B), 11 blink, 12 underline.
 *  Characters are 12 x 18 dots (font ROM loaded through dl_*: 128 chars x 18 rows x 2 bytes, big endian,
 *  dot 0 = bit 11). Border mode draws a black 1-dot outline round the character dots (the photos of real
 *  machines show this outline on all NSS text).
 *
 *  Video: ce = OSD dot clock enable, hs = one clk at each line start, vs = one clk at frame start (with hs).
 *  Display starts reg1[5:0]*4 dots after hs and reg2[5:0]*4 lines after vs (offsets tuned by the caller).
 */
module nss_osd (
    input             clk,
    input             reset,

    input             dl_wr,
    input      [12:0] dl_addr,
    input       [7:0] dl_data,

    input             we,
    input       [7:0] din,

    input             ce,
    input             hs,
    input             vs,
    output reg  [2:0] rgb,
    output reg        fg,        // character, underline or border dot
    output            raster,    // whole raster mode (reg 7 bit 0)
    output     [15:0] reg0,
    output     [15:0] reg7
);

// ------------------------------------------------------------------ registers / RAM
reg [15:0] r[8];
assign reg0 = r[0];
assign reg7 = r[7];
assign raster = r[7][0];

reg  [15:0] vram[512];
reg  [11:0] font[2304];

reg   [8:0] vw_a;
reg  [15:0] vw_d;
reg         vw_we;

always @(posedge clk) if (vw_we) vram[vw_a] <= vw_d;

reg [7:0] fhi;
always @(posedge clk) begin
    if (dl_wr && ~dl_addr[0]) fhi <= dl_data;
    if (dl_wr &&  dl_addr[0] && dl_addr[12:1] < 12'd2304) font[dl_addr[12:1]] <= {fhi[3:0], dl_data};
end

// ------------------------------------------------------------------ serial interface
reg        clk_o;
reg  [3:0] pos;
reg [15:0] sh;
reg        have_addr;
reg  [8:0] addr;
reg        erase;
reg  [8:0] erase_a;

wire [15:0] sh_n = {din[5], sh[15:1]};

always @(posedge clk) begin
    vw_we <= 0;
    if (reset) begin
        clk_o <= 1; pos <= 0; have_addr <= 0; erase <= 1; erase_a <= 0;
        r[0] <= 0; r[1] <= 0; r[2] <= 0; r[3] <= 0; r[4] <= 0; r[5] <= 0; r[6] <= 0; r[7] <= 0;
    end else begin
        if (erase) begin
            vw_we <= 1; vw_a <= erase_a; vw_d <= 16'h007f;
            erase_a <= erase_a + 1'd1;
            if (erase_a == 9'h11f) erase <= 0;
        end
        if (we) begin
            clk_o <= din[7];
            if (din[4]) begin pos <= 0; have_addr <= 0; end
            else if (clk_o & ~din[7]) begin
                sh  <= sh_n;
                pos <= pos + 1'd1;
                if (pos == 4'd15) begin
                    if (~have_addr) begin addr <= sh_n[8:0]; have_addr <= 1; end
                    else begin
`ifdef SIM_OSDLOG
                        $display("OSDW %03x %04x", addr, sh_n);
`endif
                        if (addr < 9'h120) begin vw_we <= 1; vw_a <= addr; vw_d <= sh_n; end
                        else begin
                            r[addr[2:0]] <= sh_n;
                            if (addr[2:0] == 3'd7 && sh_n[5]) begin erase <= 1; erase_a <= 0; end
                        end
                        addr <= (addr >= 9'h127) ? 9'd0 : addr + 1'd1;
                    end
                end
            end
        end
    end
end

// ------------------------------------------------------------------ vertical
wire [5:0] vstart = r[2][5:0];
wire [1:0] vz1 = r[2][7:6], vz2 = r[2][9:8], vz3 = r[2][11:10];
wire [1:0] hz1 = r[1][7:6], hz2 = r[1][9:8], hz3 = r[1][11:10];
wire [4:0] scrf = r[3][4:0];
wire [1:0] space = r[3][6:5];
wire [3:0] scrr = r[3][11:8];
wire       scroll = scrr != 0;

reg  [8:0] vline;       // lines since vs
reg  [1:0] vreg;        // 0 wait for vstart, 1 rows, 2 gap after row 0, 3 done
reg  [5:0] gleft;       // gap lines left
reg  [3:0] src;         // character row in RAM
reg  [4:0] grow;        // glyph row 0-17
reg  [1:0] vsub;
reg  [3:0] nrows;       // rows started after row 0
// character size follows the RAM row (as MAME): row 0 = size 1, row 11 = size 3, rows 1-10 = size 2.
// The NSS boot screen depends on this: with scroll offset 8 its row 10 (NINTENDO, 2x) and row 11
// (SUPER SYSTEM, 1x) end up mid-screen, as photos of real machines show.
wire [1:0] vz = (src == 4'd0) ? vz1 : (src == 4'd11) ? vz3 : vz2;
wire [1:0] hz = (src == 4'd0) ? hz1 : (src == 4'd11) ? hz3 : hz2;
wire [5:0] gaph = (space == 2'd0) ? 6'd0 : (space == 2'd1) ? 6'd18 : (space == 2'd2) ? 6'd36 : 6'd54;

wire vis_row = (vreg == 2'd1);

always @(posedge clk) begin
    if (hs) begin
        vline <= vs ? 9'd0 : vline + 1'd1;
        if (vs) vreg <= 0;
        else case (vreg)
        2'd0: if (vline + 1'd1 == {1'b0, vstart, 2'b00}) begin
                  vreg <= 2'd1; src <= 0; grow <= 0; vsub <= 0; nrows <= 0;
              end
        2'd1: begin
            // advance one displayed line
            if (vsub == vz) begin
                vsub <= 0;
                if (grow == 5'd17) begin
                    grow <= 0;
                    if (src == 4'd0) begin
                        // after row 0: optional gap, then row 1 (or the scroll start row / dot offset)
                        src  <= scroll ? scrr : 4'd1;
                        grow <= scroll ? scrf : 5'd0;
                        nrows <= 4'd1;
                        if (gaph != 0) begin vreg <= 2'd2; gleft <= gaph - 1'd1; end
                    end else if (nrows == 4'd11) vreg <= 2'd3;
                    else begin
                        src <= (src == 4'd11) ? 4'd1 : src + 1'd1;
                        nrows <= nrows + 1'd1;
                    end
                end else grow <= grow + 1'd1;
            end else vsub <= vsub + 1'd1;
        end
        2'd2: if (gleft == 0) vreg <= 2'd1; else gleft <= gleft - 1'd1;
        default: ;
        endcase
    end
end

// ------------------------------------------------------------------ horizontal + fetch
wire [5:0] hstart = r[1][5:0];
reg  [9:0] hdot;
reg  [4:0] col;         // 0-23 shown, 24 = done, 31 = before start
reg  [3:0] gcol;
reg  [1:0] hsub;

// fetched character (current) and prefetched (next)
reg [15:0] c_attr, n_attr;
reg [11:0] c_rp, c_rc, c_rn, n_rp, n_rc, n_rn;   // glyph rows grow-1, grow, grow+1
reg  [2:0] fst;
reg  [4:0] fcol;
reg  [15:0] vq;
reg  [11:0] fq;
reg  [8:0] vr_a;
reg [11:0] fr_a;
always @(posedge clk) vq <= vram[vr_a];
always @(posedge clk) fq <= font[fr_a];

wire [8:0] row_base = {src, 4'b0} + {1'b0, src, 3'b0};   // src * 24
wire [11:0] fbase = {n_attr[6:0], 4'b0} + {4'b0, n_attr[6:0], 1'b0};  // code * 18
wire start_fetch;
reg  fetch_req;

always @(posedge clk) begin
    // fetch sequencer: attr, then 3 font rows
    case (fst)
    3'd0: if (fetch_req) begin vr_a <= row_base + fcol; fst <= 3'd1; end
    3'd1: fst <= 3'd2;
    3'd2: begin n_attr <= vq; fst <= 3'd3; end
    3'd3: begin fr_a <= fbase + grow - 1'd1; fst <= 3'd4; end
    3'd4: begin fr_a <= fbase + grow; fst <= 3'd5; end
    3'd5: begin fr_a <= fbase + grow + 1'd1; n_rp <= (grow == 0) ? 12'd0 : fq; fst <= 3'd6; end
    3'd6: begin n_rc <= fq; fst <= 3'd7; end
    3'd7: begin n_rn <= (grow == 5'd17) ? 12'd0 : fq; fst <= 3'd0; end
    endcase
end

// ------------------------------------------------------------------ blink
reg [5:0] fcnt;
always @(posedge clk) if (hs & vs) fcnt <= fcnt + 1'd1;
wire [5:0] fph = r[5][2] ? {1'b0, fcnt[4:0]} : fcnt;     // phase in a 32 or 64 frame cycle
wire [5:0] fhalf = r[5][2] ? 6'd32 : 6'd64;
reg blink_off;
always @(*) case (r[5][1:0])
    2'd0: blink_off = 0;
    2'd1: blink_off = fph < (fhalf >> 2);
    2'd2: blink_off = fph < (fhalf >> 1);
    2'd3: blink_off = fph < (fhalf - (fhalf >> 2));
endcase

// ------------------------------------------------------------------ dot output
wire [3:0] gx = gcol;
wire bit_c  = c_rc[4'd11 - gx];
wire bit_l  = (gx != 0)      && (c_rp[4'd12 - gx] | c_rc[4'd12 - gx] | c_rn[4'd12 - gx]);
wire bit_r  = (gx != 4'd11)  && (c_rp[4'd10 - gx] | c_rc[4'd10 - gx] | c_rn[4'd10 - gx]);
wire bit_ud = c_rp[4'd11 - gx] | c_rn[4'd11 - gx];
wire mode_border = r[7][3:2] == 2'd2 || r[7][3:2] == 2'd3;
wire hidden = c_attr[11] & blink_off;
wire uline  = c_attr[12] & (grow == 5'd17);
wire showing = vis_row && col < 5'd24;

always @(posedge clk) begin
    fetch_req <= 0;
    if (hs) begin
        hdot <= 0; col <= 5'd31; gcol <= 0; hsub <= 0;
        // first character of the line
        fcol <= 0; fetch_req <= 1;
    end else if (ce) begin
        hdot <= hdot + 1'd1;
        if (col == 5'd31) begin
            if (hdot + 1'd1 == {2'b0, hstart, 2'b00}) begin
                col <= 0; gcol <= 0; hsub <= 0;
                c_attr <= n_attr; c_rp <= n_rp; c_rc <= n_rc; c_rn <= n_rn;
                fcol <= 5'd1; fetch_req <= 1;
            end
        end else if (col < 5'd24) begin
            if (hsub == hz) begin
                hsub <= 0;
                if (gcol == 4'd11) begin
                    gcol <= 0;
                    col <= col + 1'd1;
                    c_attr <= n_attr; c_rp <= n_rp; c_rc <= n_rc; c_rn <= n_rn;
                    fcol <= col + 5'd2; fetch_req <= (col + 5'd2) < 5'd24;
                end else gcol <= gcol + 1'd1;
            end else hsub <= hsub + 1'd1;
        end
    end

    if (ce) begin
        fg <= 0;
        rgb <= 3'd0;
        if (showing && r[7][7] && ~hidden) begin
            if (uline) begin
                fg <= 1;
                rgb <= r[6][12] ? r[6][10:8] : c_attr[10:8];
            end else if (bit_c) begin
                fg <= 1; rgb <= c_attr[10:8];
            end else if (mode_border && (bit_l | bit_r | bit_ud)) begin
                fg <= 1; rgb <= r[6][6:4];      // border in the character background colour (black on NSS)
            end
        end
        if (~fg_any) rgb <= r[6][2:0];
    end
end
wire fg_any = showing && r[7][7] && ~hidden && (uline | bit_c | (mode_border & (bit_l | bit_r | bit_ud)));

endmodule
