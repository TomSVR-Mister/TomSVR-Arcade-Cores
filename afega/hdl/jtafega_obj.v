/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Afega / NMK16 sprites (MAME nmk16spr.cpp with a colour/priority callback, so entry 0 ends on top).
 * Sprite DMA (MAME dma_callback): at line 241 the 4 kB at work RAM 0x8000 are copied to a buffer; the sprites shown
 *   are those of the previous copy (two buffers), so two ping-pong banks are enough.
 * Entry (8 words): w0 bit 0 visible   w1 { flipy, flipx, h[3:0], w[3:0] } (tiles - 1)   w3 code   w4 x (9 bits)
 *   w6 y (9 bits)   w7 colour[3:0]. Tile column i / row j (screen order) of a block uses code + i' + j' * (w + 1),
 *   where i' = flipx ? w - i : i, j' = flipy ? h - j : j. Coordinates wrap at 512.
 * Graphics: 16x16x4 (gfx_8x8x4_col_2x2_group_packed_msb), 128 bytes per tile, left half rows then right half rows.
 *   32-bit word at { tile, x[3], y[3:0] }, left pixel in the high nibble of the first byte. Pen 15 transparent.
 * Line buffer: { colour, pen }, cleared to pen 15 as it is read. */

module jtafega_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              omask,       // 1: 8192 tiles, 0: 4096
    input              oen,
    input       [ 8:0] hdump,
    input              hs_start,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,

    // DMA from work RAM
    output reg  [15:1] wram_addr,
    input       [15:0] wram_dout,

    output      [19:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [ 7:0] pxl
);

localparam [3:0] IDLE=0, A1=1, A2=2, A3=3, A4=4, B0=5, B1=6, B2=7, B3=8, TILE=9, FWAIT=10, WRITE=11, NEXT=12, DMA=13;

reg  [ 3:0] st;
reg  [ 8:0] line;
reg  [ 7:0] ent;
reg         lbuf, bank, dma_done;
reg  [ 2:0] wsel;
reg  [11:0] dcnt;
reg  [15:0] w1, code;
reg  [ 8:0] sx, x;
reg  [ 3:0] col, ysub, ci, nw;
reg  [ 4:0] jrow;
reg  [ 1:0] wcnt;
reg  [31:0] wa;
reg  [ 2:0] px;
reg         half, fx;
reg  [12:0] tile;
// buffer
reg  [11:0] buf_ra;
wire [15:0] buf_q;
reg  [10:0] dma_wa;
reg         dma_we;

wire [ 8:0] dy   = line - buf_q[8:0];                 // line - y (mod 512)
wire [ 3:0] hh   = w1[7:4];
wire        yhit = dy[8:4] <= { 1'b0, hh };
wire [ 2:0] pxf  = px ^ {3{fx}};
wire [ 3:0] pen  = wa[ { pxf[2:1], ~pxf[0], 2'd0 } +: 4 ];
wire [ 8:0] wx   = x + { 5'd0, half, px };

assign rom_addr = { omask ? tile[12] : 1'b0, tile[11:0], half ^ fx, ysub };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; bank <= 0; dma_we <= 0;
    end else begin
        dma_we <= 0;
        case( st )
            IDLE: begin
                if( hs_start ) begin
                    if( vrender == 9'd241 && !dma_done ) begin
                        dma_done <= 1;
                        dcnt <= 0;
                        st   <= DMA;
                    end else begin
                        if( vrender != 9'd241 ) dma_done <= 0;
                        line <= vrender;
                        lbuf <= vrender[0];
                        ent  <= 8'd255;
                        st   <= oen ? A1 : IDLE;
                    end
                end
            end
            // scan from the last entry so that entry 0 is drawn last
            A1: begin buf_ra <= { bank, ent, 3'd0 }; wcnt <= 0; st <= A2; end
            A2: begin
                buf_ra <= { bank, ent, 3'd1 };
                st <= A3;
            end
            A3: begin   // w0 arrives
                buf_ra <= { bank, ent, 3'd6 };
                if( !buf_q[0] ) st <= NEXT;
                else st <= A4;
            end
            A4: begin   // w1 arrives
                w1 <= buf_q;
                st <= B0;
            end
            B0: begin   // w6 arrives
                if( yhit ) begin
                    ysub   <= dy[3:0] ^ {4{w1[9]}};
                    jrow   <= { 1'b0, w1[9] ? hh - dy[7:4] : dy[7:4] };
                    buf_ra <= { bank, ent, 3'd3 };
                    st     <= B1;
                end else st <= NEXT;
            end
            B1: begin buf_ra <= { bank, ent, 3'd4 }; st <= B2; end
            B2: begin buf_ra <= { bank, ent, 3'd7 }; code <= buf_q; st <= B3; end    // w3
            B3: begin sx <= buf_q[8:0]; st <= TILE; wsel <= 0; end                    // w4
            TILE: begin
                if( wsel==0 ) begin  // w7 arrives on this clock
                    col  <= buf_q[3:0];
                    fx   <= w1[8];
                    nw   <= w1[3:0];
                    ci   <= 0;
                    x    <= sx;
                    wsel <= 1;
                    // code of the first column of this row
                    code <= code + jrow * ({ 12'd0, w1[3:0] } + 16'd1);
                end else begin
                    tile <= code[12:0] + { 9'd0, (fx ? nw - ci : ci) };
                    half <= 0;
                    wcnt <= 0;
                    st   <= FWAIT;
                end
            end
            FWAIT: begin
                rom_cs <= 1;
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    wa <= rom_data; px <= 0; st <= WRITE;
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                if( px==7 ) begin
                    wcnt <= 0;
                    if( !half ) begin half <= 1; st <= FWAIT; end
                    else begin
                        x  <= x + 9'd16;
                        ci <= ci + 1'd1;
                        if( ci == nw ) st <= NEXT;
                        else begin
                            tile <= code[12:0] + { 9'd0, (fx ? nw - ci - 4'd1 : ci + 4'd1) };
                            half <= 0;
                            st   <= FWAIT;
                        end
                    end
                end
            end
            NEXT: begin
                ent <= ent - 1'd1;
                st  <= ent == 0 ? IDLE : A1;
            end
            DMA: begin  // 2048 words from work RAM word 0x4000, two clocks of latency
                wram_addr <= { 4'h8, dcnt[10:0] };     // word 0x4000 (byte 0x8000)
                dma_wa    <= wram_addr[11:1];
                dcnt      <= dcnt + 1'd1;
                dma_we    <= dcnt != 0 && dcnt <= 12'd2048;
                if( dcnt == 12'd2049 ) begin
                    bank <= ~bank;
                    st   <= IDLE;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

// two banks: the DMA writes bank "bank" and then toggles it, the sprites are read from "bank" = the copy before (MAME old2)
jtframe_dual_ram #(.DW(16),.AW(12)) u_buf(
    .clk0   ( clk       ),
    .data0  ( wram_dout ),
    .addr0  ( { bank, dma_wa } ),
    .we0    ( dma_we    ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 16'd0     ),
    .addr1  ( buf_ra    ),
    .we1    ( 1'b0      ),
    .q1     ( buf_q     )
);

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { col, pen } ),
    .addr0  ( { lbuf, wx } ),
    .we0    ( st==WRITE && pen!=4'hf && !wx[8] ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'h0f     ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( pxl_cen   ),
    .q1     ( pxl       )
);

endmodule
