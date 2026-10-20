/* SPDX-License-Identifier: GPL-3.0-or-later
   Dynamite Duke tile layers, drawn one line ahead into a double line buffer (MAME dynduke.cpp).
   LAYER 0: text, 8x8, 32x32 map by rows, code {w[15:14], w[7:0]}, colour w[11:8], no scroll.
   LAYER 1: foreground, 16x16 4bpp, 32x32 map by columns, code w[11:0] + bank, colour w[15:12].
   LAYER 2: background, same map, 6bpp: pen bit 4 selects the upper palette half, bit 5 is the priority
            over sprites. Output {pri, extra, colour, pen[3:0]}.
   Graphics rows: each ROM pair gives a 16-bit word per row and 8 pixels; pixel x takes byte x[2] and
   bits 7-x[1:0] (plane +0) and 3-x[1:0] (plane +4). */

module jtdynduke_tiles #(parameter LAYER=0, RW=20)(
    input             rst,
    input             clk,
    input             start,
    input      [ 8:0] vpos,        // map line
    input      [ 8:0] hpos,        // horizontal scroll
    input             bank,
    input             wr_bank,
    input             rd_bank,
    input      [ 8:0] rd_x,

    output reg [10:1] vram_addr,
    input      [15:0] vram_data,

    output reg [RW-1:2] rom_addr,
    output reg        rom_cs,
    input             rom_ok,
    input      [31:0] rom_data,

    output reg [ 9:0] pxl
);

localparam TXT  = LAYER==0,
           BG   = LAYER==2,
           TS   = TXT ? 8 : 16,
           NT   = TXT ? 32 : 17;

localparam [3:0] IDLE=0, MAP=1, MAPW=2, ATTR=3, RD=4, RDW=5, RD2=6, RD2W=7, RD2W2=8, DRAW=9;

reg  [ 3:0] st;
reg  [ 5:0] t;
reg  [ 8:0] bx, hp;
reg  [ 4:0] col;
reg  [ 3:0] color;
reg  [ 2:0] x;
reg         half;
reg  [31:0] d0;
reg  [15:0] d1;
reg  [ 3:0] fine[0:1];
wire [ 1:0] p01, p23, p45;
wire [ 5:0] pen;
wire [ 9:0] buf_din, q;
wire        we = st==DRAW;
wire [ 3:0] yrow = TXT ? {1'b0, vpos[2:0]} : vpos[3:0];
wire [ 4:0] row  = TXT ? vpos[7:3] : vpos[8:4];
// ROM word addresses (32-bit words): text {code, row}; fg {bank, code, half, row}; bg {bank, code, half, row, lane}
wire [23:0] txt_ra = { 11'd0, vram_data[15:14], vram_data[7:0], yrow[2:0] };
wire [23:0] fg_ra  = { 6'd0, bank, vram_data[11:0], 1'b0, yrow };
wire [23:0] bg_ra  = { 5'd0, bank, vram_data[11:0], 1'b0, yrow, 1'b0 };

function [1:0] pair( input [15:0] w, input [2:0] px );
    reg [7:0] b;
    begin
        b    = px[2] ? w[15:8] : w[7:0];
        pair = { b[3-px[1:0]], b[7-px[1:0]] };
    end
endfunction

assign p01 = TXT ? pair(d0[31:16], x) : pair(d0[15:0], x);
assign p23 = TXT ? pair(d0[15:0], x)  : pair(d0[31:16], x);
assign p45 = pair(d1, x);
assign pen = { BG ? p45 : 2'b00, p23, p01 };
assign buf_din = BG ? { pen[5:4], color, pen[3:0] } : { 2'b00, color, pen[3:0] };

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0;
    end else if( start ) begin
        st     <= MAP;
        t      <= 0;
        hp     <= TXT ? 9'd0 : hpos;
        fine[wr_bank] <= TXT ? 4'd0 : hpos[3:0];
        rom_cs <= 0;
    end else case( st )
        IDLE:;
        MAP: begin
            col       <= TXT ? t[4:0] : hp[8:4] + t[4:0];
            st        <= MAPW;
        end
        MAPW: begin
            vram_addr <= TXT ? { row, col } : { col, row };
            st        <= ATTR;
            x         <= 0;
            half      <= 0;
        end
        ATTR: st <= RD;     // BRAM read latency
        RD: begin
            if( TXT ) begin
                color    <= vram_data[11:8];
                rom_addr <= txt_ra[RW-3:0];
            end else begin
                color    <= vram_data[15:12];
                rom_addr <= BG ? bg_ra[RW-3:0] : fg_ra[RW-3:0];
            end
            bx     <= { t[4:0], 4'd0 } >> (TXT ? 1 : 0);
            rom_cs <= 1;
            st     <= RDW;
        end
        RDW: st <= RD2;     // let rom_ok drop for the new address
        RD2: if( rom_ok ) begin
            d0 <= rom_data;
            if( BG ) begin
                rom_addr[2] <= 1;
                st <= RD2W;
            end else begin
                rom_cs <= 0;
                st <= DRAW;
            end
        end
        RD2W: st <= RD2W2;  // let rom_ok drop for the new address
        RD2W2: if( rom_ok ) begin
            d1     <= rom_data[15:0];
            rom_cs <= 0;
            st     <= DRAW;
        end
        DRAW: begin
            x  <= x + 3'd1;
            bx <= bx + 9'd1;
            if( x==7 ) begin
                if( !TXT && !half ) begin
                    half <= 1;
                    rom_addr[BG ? 7 : 6] <= 1;     // right half of the tile
                    if( BG ) rom_addr[2] <= 0;
                    rom_cs <= 1;
                    st <= RDW;
                end else begin
                    t  <= t + 6'd1;
                    st <= t==NT-1 ? IDLE : MAP;
                end
            end
        end
        default: st <= IDLE;
    endcase
end

always @(posedge clk) pxl <= q;

jtframe_dual_ram #(.DW(10),.AW(10)) u_buf(
    .clk0   ( clk                   ),
    .data0  ( buf_din               ),
    .addr0  ( { wr_bank, bx }       ),
    .we0    ( we                    ),
    .q0     (                       ),
    .clk1   ( clk                   ),
    .data1  ( 10'd0                 ),
    .addr1  ( { rd_bank, rd_x + {5'd0, fine[rd_bank]} } ),
    .we1    ( 1'b0                  ),
    .q1     ( q                     )
);

endmodule
