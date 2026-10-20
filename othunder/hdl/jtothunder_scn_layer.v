/* SPDX-License-Identifier: GPL-3.0-or-later
   One TC0100SCN layer, drawn a line ahead into a double line buffer.
   Background layers (TXT=0): 64x64 map of {attr, code} word pairs, 8x8 4 bpp tiles from ROM
   (gfx_8x8x4_packed_msb, 32 bits per row). attr: 15 flip Y, 14 flip X, 7-0 colour.
   Text layer (TXT=1): 64x64 map of single words (15 flip Y, 14 flip X, 13-8 colour, 7-0 code),
   2 bpp 8x8 characters in the same RAM (one word per row, plane 0 in the upper byte). */

module jtothunder_scn_layer #(parameter TXT=0)(
    input             rst,
    input             clk,

    input             start,        // begin drawing line
    input             wr_bank,      // line buffer half to draw into
    input             rd_bank,
    input      [ 8:0] map_x0,       // map X sampled at screen x=0
    input      [ 8:0] map_y,
    input      [ 8:0] rd_addr,      // screen x being read out

    // tile RAM (one bank of the chip RAM)
    output reg [12:0] vram_addr,
    input      [15:0] vram_data,
    // column scroll (layer 1 only)
    output     [ 5:0] col_addr,
    input      [15:0] col_data,

    output reg [18:2] rom_addr,
    output reg        rom_cs,
    input             rom_ok,
    input      [31:0] rom_data,

    output     [11:0] pxl           // {colour, pen}
);

localparam [3:0] IDLE=0, COL=1, COLW=2, ATTR=3, AW=4, AR=5, CW=6, CR=7, GFX=8, TW=9, TR=10,
                 RW0=11, RW=12, DRAW=13;

reg  [ 3:0] st;
reg  [ 5:0] tcnt, tx;
reg  [ 8:0] bx, ty_eff;
reg  [ 2:0] pcnt;
reg  [15:0] attr, code;
reg  [31:0] pv;
reg  [ 7:0] pal;
reg         hflip;
wire [ 2:0] px  = pcnt ^ {3{hflip}};
wire [ 3:0] pen = pv[ {px,2'b0} +: 4 ];
wire        we  = st==DRAW;
wire [ 2:0] row = ty_eff[2:0] ^ {3{attr[15]}};

assign col_addr = tx;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; tcnt <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                tcnt <= 0;
                tx   <= map_x0[8:3];
                bx   <= -{6'd0, map_x0[2:0]};
                st   <= COL;
            end
            COL:  st <= COLW;   // column scroll RAM read
            COLW: begin
                // column scroll moves each 8-pixel column of the map vertically
                ty_eff <= map_y - (TXT ? 9'd0 : col_data[8:0]);
                st     <= ATTR;
            end
            ATTR: begin
                vram_addr <= TXT ? { 1'b0, ty_eff[8:3], tx } : { ty_eff[8:3], tx, 1'b0 };
                st <= AW;
            end
            AW: st <= AR;
            AR: begin
                attr <= vram_data;
                if( TXT ) st <= GFX;
                else begin
                    vram_addr[0] <= 1;
                    st <= CW;
                end
            end
            CW: st <= CR;
            CR: begin
                code <= vram_data;
                st   <= GFX;
            end
            GFX: begin
                hflip <= attr[14];
                pal   <= TXT ? { 2'd0, attr[13:8] } : attr[7:0];
                if( TXT ) begin
                    vram_addr <= { 2'b10, attr[7:0], row };   // chip RAM 6000-6fff
                    st <= TW;
                end else begin
                    rom_addr <= { code[13:0], row };
                    rom_cs   <= 1;
                    st <= RW0;
                end
            end
            TW: st <= TR;
            TR: begin
                // one word per row: plane 0 (pen MSB) in the high byte, leftmost pixel in bit 7
                pv <= { 2'd0, vram_data[ 8], vram_data[0], 2'd0, vram_data[ 9], vram_data[1],
                        2'd0, vram_data[10], vram_data[2], 2'd0, vram_data[11], vram_data[3],
                        2'd0, vram_data[12], vram_data[4], 2'd0, vram_data[13], vram_data[5],
                        2'd0, vram_data[14], vram_data[6], 2'd0, vram_data[15], vram_data[7] };
                pcnt <= 0;
                st   <= DRAW;
            end
            RW0: st <= RW;
            RW: if( rom_ok ) begin
                rom_cs <= 0;
                // packed, MSB first: pixels 0-3 in the first 16-bit word, high nibble first
                pv <= { rom_data[19:16], rom_data[23:20], rom_data[27:24], rom_data[31:28],
                        rom_data[ 3: 0], rom_data[ 7: 4], rom_data[11: 8], rom_data[15:12] };
                pcnt <= 0;
                st   <= DRAW;
            end
            DRAW: begin
                pcnt <= pcnt + 1'd1;
                bx   <= bx + 1'd1;
                if( pcnt==7 ) begin
                    tcnt <= tcnt + 1'd1;
                    tx   <= tx + 1'd1;
                    st   <= tcnt==40 ? IDLE : COL;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(12),.AW(10)) u_buf(
    .clk0   ( clk               ),
    .data0  ( { pal, pen }      ),
    .addr0  ( { wr_bank, bx }   ),
    .we0    ( we                ),
    .q0     (                   ),
    .clk1   ( clk               ),
    .data1  ( 12'd0             ),
    .addr1  ( { rd_bank, rd_addr } ),
    .we1    ( 1'b0              ),
    .q1     ( pxl               )
);

endmodule
