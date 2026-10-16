/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Zero Zone video (MAME zerozone.cpp): one opaque 64x32 tilemap of 8x8x4 tiles (column order), no scroll.
 *   word = { colour, bank select, code[10:0] }; code += tilebank*0x800 when bit 11 is set.
 *   8 MHz pixel clock, 512x260 total (60 Hz), MAME visible area X 8-375, Y 16-239.
 *   Palette: 256 words RRRRGGGGBBBBRGBx. Graphics: 32-bit SDRAM words, one tile row each, leftmost pixel = high nibble of byte 0. */

module jtzero_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 2:0] tilebank,

    output      [13:1] vram_addr,
    input       [15:0] vram_dout,
    output reg  [ 8:1] pal_addr,
    input       [15:0] pal_dout,

    output reg  [18:2] rom_addr,
    output reg         rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output             vbl_irq,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd511, HS_START=9'd420, HS_END=9'd452;
localparam [8:0] VTOTAL=9'd259, VB_END=9'd16, VB_START=9'd240, VS_START=9'd244, VS_END=9'd247;
localparam [2:0] IDLE=0, RD=1, FETCH=2, FWAIT=3, WRITE=4;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl;
reg  [ 2:0] hbl_sh, vbl_sh;
reg  [ 2:0] st, px;
reg  [ 7:0] line;
reg  [ 5:0] col;
reg  [15:0] attr;
reg  [ 1:0] wcnt;
reg  [31:0] w;
reg         lbuf, start, hzero_l;
wire [ 7:0] pxl;
wire [ 3:0] pen = w[ { px[2:1], ~px[0], 2'd0 } +: 4 ];
wire [13:0] code = { attr[11] ? tilebank : 3'd0, attr[10:0] };

assign LHBL      = hbl_sh[1];
assign LVBL      = vbl_sh[1];
assign vbl_irq   = lvbl;
assign vram_addr = 13'h700 + { 2'd0, col, line[7:3] };

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    lhbl <= hdump >= 9'd7 && hdump < 9'd375;   // value for the next hdump
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[1:0], lhbl };
    vbl_sh <= { vbl_sh[1:0], lvbl };
end

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

// render the next line into a ping-pong line buffer
always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                line <= vrender[7:0];
                lbuf <= vrender[0];
                col  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin attr <= vram_dout; st <= FETCH; end
            end
            FETCH: begin
                rom_addr <= { code, line[2:0] };
                rom_cs   <= 1;
                wcnt     <= 0;
                st       <= FWAIT;
            end
            FWAIT: begin
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rom_ok ) begin
                    rom_cs <= 0;
                    w      <= rom_data;
                    px     <= 0;
                    st     <= WRITE;
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                if( px==7 ) begin
                    col  <= col + 1'd1;
                    wcnt <= 0;
                    st   <= col==63 ? IDLE : RD;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( { attr[15:12], pen } ),
    .addr0  ( { lbuf, col, px } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], hdump } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

always @(posedge clk) if( pxl_cen ) begin
    pal_addr <= gfx_en[0] ? pxl : 8'd0;
    red      <= { pal_dout[15:12], pal_dout[3] };
    green    <= { pal_dout[11: 8], pal_dout[2] };
    blue     <= { pal_dout[ 7: 4], pal_dout[1] };
end

endmodule
