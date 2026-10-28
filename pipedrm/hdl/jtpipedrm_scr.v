/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Video System "fromance" tile layer (MAME vsystem/fromance_v.cpp): 64x64 map of 8x4 tiles, 4 bpp, 512x256 pixels.
 * Map RAM (one 16 kB block per layer, CPU d000-ffff): 0000 colour (bit 7 = code bit 16, bits 6-0 palette),
 * 1000 code bits 15-8, 2000 code bits 7-0. Tile index = row * 64 + column (TILEMAP_SCAN_ROWS).
 * gfx (bglayout): 16 bytes per tile, 4 bytes per pixel row, leftmost pixel in the low nibble of byte 0.
 * The code wraps at the size of the gfx region (RGN_FRAC), given as cmask.
 *
 * Line based: while line N is shown, line N+1 is drawn into the other half of a 2 x 512 line buffer, 45 tiles
 * from the scroll position. Screen flip mirrors the whole tilemap (MAME set_flip_all), see the flip terms below. */
module jtpipedrm_scr(
    input               rst,
    input               clk,
    input               hs,
    input               flip,
    input      [ 8:0]   vrender,     // line drawn now, shown after the next HS
    input      [ 8:0]   hdump,       // pixel shown now
    input      [ 8:0]   scrx,
    input      [ 8:0]   scry,
    input      [15:0]   cmask,

    output reg [13:0]   vram_addr,
    input      [ 7:0]   vram_dout,

    output     [19:2]   rom_addr,
    output reg          rom_cs,
    input      [31:0]   rom_data,
    input               rom_ok,

    output reg [10:0]   pxl          // { colour, pen }
);

localparam [5:0] NTILES = 6'd45;

reg  [10:0] lbuf[0:1023];
reg         half, hs_l, busy;
reg  [ 3:0] st;
reg  [ 5:0] k, col;
reg  [ 7:0] colour, hi;
reg  [15:0] code;
reg  [ 1:0] sub;
reg  [ 5:0] row;
reg  [ 2:0] fine, px;
reg  [31:0] gfx;
reg  [ 8:0] wpos;
reg  [ 1:0] wait_cnt;
reg         we;
reg  [ 9:0] waddr;
reg  [10:0] wdata;

// MAME (tilemap_t::effective_rowscroll/colscroll, mirrored around the 352x240 visible area): flipped, screen
// (x, y) shows map pixel (351 - x + sx, 239 - y + sy), with sx/sy the scroll values the game wrote while flipped
wire [7:0] ymap  = flip ? 8'd239 - vrender[7:0] + scry[7:0] : vrender[7:0] + scry[7:0];
wire [8:0] xmap0 = flip ? 9'd351 + scrx : scrx;   // map x of screen pixel 0

assign rom_addr = { code, sub };

always @(posedge clk) begin
    if( we ) lbuf[waddr] <= wdata;
    pxl <= lbuf[{ ~half, hdump }];
end

// in flipped mode the map is walked right to left, so tile k covers screen pixels ending at k*8 - fine
wire [8:0] mx = flip ? xmap0 - { k, 3'd0 } : xmap0 + { k, 3'd0 };

always @(posedge clk) begin
    hs_l <= hs;
    we   <= 0;
    if( rst ) begin
        half <= 0; busy <= 0; st <= 0; rom_cs <= 0; k <= 0;
    end else if( hs && !hs_l ) begin
        half <= ~half;
        busy <= 1;
        st   <= 0;
        k    <= 0;
        rom_cs <= 0;
        row  <= ymap[7:2];
        sub  <= ymap[1:0];
        fine <= flip ? ~xmap0[2:0] : xmap0[2:0];
    end else if( busy ) begin
        case( st )
            0: begin
                col       <= mx[8:3];
                vram_addr <= { 2'd0, row, mx[8:3] };
                st <= 1;
            end
            1: begin vram_addr <= { 2'd1, row, col }; st <= 2; end
            2: begin vram_addr <= { 2'd2, row, col }; colour <= vram_dout; st <= 3; end
            3: begin hi <= vram_dout; st <= 4; end
            4: begin
                code     <= { hi, vram_dout } & cmask;
                rom_cs   <= 1;
                wait_cnt <= 2'd2;
                st <= 5;
            end
            5: begin
                if( wait_cnt!=0 ) wait_cnt <= wait_cnt - 2'd1;
                else if( rom_ok ) begin
                    gfx    <= rom_data;
                    rom_cs <= 0;
                    px     <= 0;
                    wpos   <= { k, 3'd0 } - { 6'd0, fine };
                    st     <= 6;
                end
            end
            6: begin
                // flipped, each tile is mirrored too: its rightmost pixel lands first
                we    <= 1;
                waddr <= { half, wpos };
                wdata <= { colour[6:0], flip ? gfx[{~px,2'd0}+:4] : gfx[{px,2'd0}+:4] };
                wpos  <= wpos + 9'd1;
                px    <= px + 3'd1;
                if( px==3'd7 ) begin
                    if( k==NTILES-6'd1 ) busy <= 0;
                    else begin k <= k + 6'd1; st <= 0; end
                end
            end
            default: st <= 0;
        endcase
    end
end

endmodule
