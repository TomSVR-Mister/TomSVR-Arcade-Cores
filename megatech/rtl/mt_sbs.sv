/*  mt_sbs.sv - Mega-Tech side-by-side output: game screen (left) and menu screen (right) on one line
 *
 *  Copyright (C) 2026 TomSVR. Written for the TomSVR Mega-Tech core.
 *
 *  This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
 *  Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
 *  option) any later version.
 *
 *  The cabinet has two monitors. Both pictures have the same line (3420 master clocks) and frame (262 lines)
 *  length, so the menu VDP is phase-locked to the game picture (mt_vdp4 sync input, see sync_tgl) and each
 *  picture only needs a two-line buffer: line k of both is written during game line k and shown during line k+1.
 *  Output: one pixel every 4 master clocks (13.4 MHz, 855 per line), two 320-pixel slots. A 256-pixel source
 *  (menu, H32 game) is stretched to 320 by nearest neighbour, so both keep the 4:3 shape of a full screen.
 */
module mt_sbs (
    input            clk,        // CLK_VIDEO (master clock)
    // game picture (clk)
    input            g_ce,
    input      [7:0] g_r, g_g, g_b,
    input            g_hbl, g_vbl, g_hs, g_vs,
    output reg       sync_tgl,   // toggles at the first active pixel of the game picture (menu VDP phase lock)
    // menu picture (clk_m, same frequency as clk)
    input            clk_m,
    input            m_ce,
    input      [1:0] m_r, m_g, m_b,
    input            m_hbl, m_vbl,
    // output (clk)
    output reg       ce,
    output reg [7:0] r, g, b,
    output reg       hbl, vbl, hs, vs
);

// ---------------------------------------------------------------- game line buffer (2 x 512 x 24)
reg [23:0] gbuf[0:1023];
reg  [8:0] gx, gw;
reg        gline, ghbl_d, gvbl_d, gact;
always @(posedge clk) begin
    if (g_ce) begin
        ghbl_d <= g_hbl;
        gvbl_d <= g_vbl;
        if (~g_hbl & ~g_vbl) begin
            if (gx != 9'd511) begin gbuf[{gline, gx}] <= {g_r, g_g, g_b}; gx <= gx + 9'd1; end
            gact <= 1;
        end
        if (g_hbl & ~ghbl_d) begin               // end of a line: next line goes to the other buffer
            if (gact) begin gline <= ~gline; gw <= gx; end
            gx <= 0; gact <= 0;
        end
        if (gvbl_d & ~g_vbl) sync_tgl <= ~sync_tgl;
        if (g_vbl) gline <= 0;
    end
end

// ---------------------------------------------------------------- menu line buffer (2 x 256 x 6), clk_m
reg  [5:0] mbuf[0:511];
reg  [7:0] mx;
reg        mline, mhbl_d, mact;
always @(posedge clk_m) begin
    if (m_ce) begin
        mhbl_d <= m_hbl;
        if (~m_hbl & ~m_vbl) begin
            mbuf[{mline, mx}] <= {m_r, m_g, m_b};
            if (mx != 8'd255) mx <= mx + 8'd1;
            mact <= 1;
        end
        if (m_hbl & ~mhbl_d) begin
            if (mact) mline <= ~mline;
            mx <= 0; mact <= 0;
        end
        if (m_vbl) mline <= 0;
    end
end

// ---------------------------------------------------------------- output timing, locked to the game's hsync
localparam ASTART = 10'd120, SLOT = 10'd320;
reg  [1:0] cdiv;
reg  [9:0] ox;
reg        ghs_d, rd_line, gact_line;
reg  [8:0] gsrc, gacc, msrc, macc, gw_r;
always @(posedge clk) begin
    ce <= 0;
    cdiv <= cdiv + 2'd1;
    ghs_d <= g_hs;
    if (g_hs & ~ghs_d) begin
        // a new output line shows the game line that just ended (the buffer not being written now)
        ox <= 0; cdiv <= 0;
        vbl <= ~gact_line;
        rd_line <= ~gline;
        gw_r <= (gw > 9'd320 || gw == 0) ? 9'd320 : gw;
    end else if (cdiv == 2'd3) begin
        ce <= 1;
        if (ox != 10'd1023) ox <= ox + 10'd1;
    end
end

// the game line that ended had active pixels (output vblank one line late)
always @(posedge clk) if (g_ce && g_hbl && ~ghbl_d) gact_line <= gact;

wire in_g = ox >= ASTART && ox < ASTART + SLOT;
wire in_m = ox >= ASTART + SLOT && ox < ASTART + SLOT + SLOT;

// nearest-neighbour source position: step gw (or 256) per output pixel, one source pixel per 320
reg [23:0] gq;
reg  [5:0] mq;
always @(posedge clk) if (ce) begin
    if (ox == ASTART - 1'd1) begin gsrc <= 0; gacc <= 0; msrc <= 0; macc <= 0; end
    else if (in_g) begin
        if (gacc + gw_r >= SLOT) begin gacc <= gacc + gw_r - SLOT[8:0]; gsrc <= gsrc + 9'd1; end
        else gacc <= gacc + gw_r;
    end else if (in_m) begin
        if (macc + 9'd256 >= SLOT) begin macc <= macc + 9'd256 - SLOT[8:0]; msrc <= msrc + 9'd1; end
        else macc <= macc + 9'd256;
    end
end
always @(posedge clk) begin
    gq <= gbuf[{rd_line, gsrc}];
    mq <= mbuf[{rd_line, msrc[7:0]}];
end

reg in_g_d, in_m_d;
always @(posedge clk) if (ce) begin
    in_g_d <= in_g; in_m_d <= in_m;
    hbl <= ~(in_g | in_m);
    hs  <= ox < 10'd64;
    vs  <= g_vs;
end
always @(*) begin
    if (in_g_d)      {r, g, b} = gq;
    else if (in_m_d) {r, g, b} = {{4{mq[5:4]}}, {4{mq[3:2]}}, {4{mq[1:0]}}};
    else             {r, g, b} = 24'd0;
end

endmodule
