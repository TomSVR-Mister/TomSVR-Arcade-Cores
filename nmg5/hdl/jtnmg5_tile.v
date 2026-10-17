/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * YS-1300 tilemap (MAME nmg5.cpp): 64x64 tiles of 8x8x8, tile = video RAM word | bank << 16.
 *   Screen pixel (x, y) = map pixel (x + scrx, y + scry), map wraps at 512.
 * Graphics in SDRAM: one 64-bit row (two 32-bit words) per tile row: word { tile, row, w }.
 *   Pen bits from bytes (Puzzle Club order, the MRA arranges Multi 5's ROMs to match):
 *   7: byte 3, 6: byte 4, 5: byte 1, 4: byte 0, 3: byte 7, 2: byte 6, 1: byte 5, 0: byte 2; leftmost pixel in the MSB.
 *   big (16 MB, 2^18 tiles): byte address bit 23 selects the high SDRAM bus; otherwise 2^16 tiles (4 MB), low bus only.
 * The 41 tiles covering the next line are rendered into a 512-pixel ping-pong line buffer. */

module jtnmg5_tile(
    input              rst,
    input              clk,
    input              big,
    input       [ 1:0] bank,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,
    input       [ 8:0] vdump,
    input       [ 8:0] scrx,
    input       [ 8:0] scry,

    output      [12:1] vram_addr,
    input       [15:0] vram_dout,

    output      [22:2] lo_addr,
    output reg         lo_cs,
    input       [31:0] lo_data,
    input              lo_ok,
    output      [22:2] hi_addr,
    output reg         hi_cs,
    input       [31:0] hi_data,
    input              hi_ok,

    output      [ 7:0] pxl
);

localparam [2:0] IDLE=0, RD=1, FETCH=2, FWAIT=3, WRITE=4;

reg  [ 2:0] st;
reg  [ 8:0] mapy, sx[0:1];
reg  [ 5:0] col, cnt;
reg  [17:0] code;
reg  [23:2] addr;
reg         lbuf, wsel;
reg  [ 1:0] wcnt;
reg  [31:0] wa, wb;
reg  [ 2:0] px;
reg         start, hzero_l;
wire        use_hi = big && addr[23];
wire [31:0] rdata = use_hi ? hi_data : lo_data;
wire        rok   = use_hi ? hi_ok   : lo_ok;
wire [ 2:0] b = ~px;
wire [ 7:0] pen = { wa[24+b], wb[b], wa[8+b], wa[b], wb[24+b], wb[16+b], wb[8+b], wa[16+b] };
wire [ 8:0] rd_x = hdump + sx[vdump[0]];

assign vram_addr = { mapy[8:3], col };
assign lo_addr   = addr[22:2];
assign hi_addr   = addr[22:2];

always @(posedge clk) begin
    hzero_l <= hdump==0;
    start   <= hdump==0 && !hzero_l;
end

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; lo_cs <= 0; hi_cs <= 0;
    end else begin
        case( st )
            IDLE: if( start ) begin
                mapy <= vrender + scry;
                lbuf <= vrender[0];
                sx[vrender[0]] <= scrx;
                col  <= scrx[8:3];
                cnt  <= 0;
                wcnt <= 0;
                st   <= RD;
            end
            RD: begin       // two clocks of BRAM latency
                wcnt <= wcnt + 1'd1;
                if( wcnt==2 ) begin
                    code <= big ? { bank, vram_dout } : { 2'd0, vram_dout };
                    wsel <= 0;
                    st   <= FETCH;
                end
            end
            FETCH: begin
                addr  <= { code, mapy[2:0], wsel };
                wcnt  <= 0;
                st    <= FWAIT;
            end
            FWAIT: begin
                lo_cs <= !use_hi;
                hi_cs <=  use_hi;
                if( wcnt!=3 ) wcnt <= wcnt + 1'd1;
                else if( rok ) begin
                    lo_cs <= 0; hi_cs <= 0;
                    if( wsel ) begin wb <= rdata; px <= 0; st <= WRITE; end
                    else begin wa <= rdata; wsel <= 1; st <= FETCH; end
                end
            end
            WRITE: begin
                px <= px + 1'd1;
                if( px==7 ) begin
                    col  <= col + 1'd1;
                    cnt  <= cnt + 1'd1;
                    wcnt <= 0;
                    st   <= cnt==40 ? IDLE : RD;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(8),.AW(10)) u_lbuf(
    .clk0   ( clk       ),
    .data0  ( pen       ),
    .addr0  ( { lbuf, col, px } ),
    .we0    ( st==WRITE ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 8'd0      ),
    .addr1  ( { vdump[0], rd_x } ),
    .we1    ( 1'b0      ),
    .q1     ( pxl       )
);

endmodule
