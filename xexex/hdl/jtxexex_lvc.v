/*  This file is part of JTXEXEX.
    SPDX-License-Identifier: GPL-3.0-or-later
    Konami K053250 "LVC" line-based background, written from MAME's k053250.cpp (normal orientation only).

    The CPU writes 4K words of RAM. Clearing bit 1 of register 4 copies the first 2K words into one of
    two line buffers; the screen then shows the copy made by the previous DMA (MAME's DMA delay). Each screen line takes
    four words from the buffer: colour (0xFFFF skips the line), ROM offset in 256-nibble units, zoom
    (64 = 1:1) and a signed scroll. Pixel x reads nibble ((x + scroll) * zoom + 32) >> 6 of the line's
    ROM data, either wrapped by the source size or clipped to it (register 4 bit 2 selects wrap).

    Lines are rendered ahead of the beam into a 32-line ring buffer, starting at the beginning of
    vertical blank, because zoomed-out lines need one ROM read per pixel.
    Pixel output: { colour[4:0], pen[3:0] }, pen 0 is transparent. */

module jtxexex_lvc(
    input             rst,
    input             clk,

    input      [ 8:0] hdump,      // 0-383 visible
    input      [ 8:0] vdump,      // 0-255 visible
    input             vb_start,   // one clock at the start of vertical blank

    // CPU interface
    input      [12:1] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input             cpu_we,
    input             ram_cs,     // 0C6000-0C7FFF
    input             reg_cs,     // 0C8000-0C800F, low byte
    output     [15:0] ram_dout,
    output     [ 7:0] reg_dout,

    // ROM, 512 kB
    output reg [18:2] rom_addr,
    output reg        rom_cs,
    input      [31:0] rom_data,
    input             rom_ok,

    output     [ 8:0] pxl,
    output reg        behind      // debug: the renderer did not finish a line in time
);

reg  [ 7:0] regs[0:7];
reg         page;
wire [15:0] cram_q, lram_q;
reg  [11:0] dma_cnt;
reg         dma_bsy, dma_we;
reg  [10:0] dma_wa;
reg  [10:0] lram_addr;

assign reg_dout = regs[cpu_addr[3:1]];

always @(posedge clk, posedge rst) begin
    if( rst ) begin : clr
        integer k;
        for( k=0; k<8; k=k+1 ) regs[k] <= 0;
        dma_bsy <= 0;
        dma_cnt <= 0;
        page    <= 0;
        dma_we  <= 0;
    end else begin
        dma_we <= 0;
        if( reg_cs && cpu_we && !cpu_dsn[0] ) begin
            regs[cpu_addr[3:1]] <= cpu_dout[7:0];
            if( cpu_addr[3:1]==4 && !cpu_dout[1] && regs[4][1] && !dma_bsy ) begin
                // the screen switches to the other buffer, which holds the previous copy,
                // and the copy goes into the buffer that was on screen
                dma_bsy <= 1;
                dma_cnt <= 0;
                page    <= ~page;
            end
        end
        if( dma_bsy ) begin
            // the CPU RAM is read at dma_cnt on this edge and its data written at the next one
            dma_cnt <= dma_cnt + 12'd1;
            dma_wa  <= dma_cnt[10:0];
            dma_we  <= !dma_cnt[11];
            if( dma_cnt == 12'h800 ) dma_bsy <= 0;
        end
    end
end

jtframe_dual_ram16 #(.AW(12)) u_cram(
    .clk0   ( clk       ),
    .data0  ( cpu_dout  ),
    .addr0  ( cpu_addr  ),
    .we0    ( ~cpu_dsn & {2{ram_cs & cpu_we}} ),
    .q0     ( ram_dout  ),
    .clk1   ( clk       ),
    .data1  ( 16'd0     ),
    .addr1  ( dma_cnt   ),
    .we1    ( 2'b0      ),
    .q1     ( cram_q    )
);

// line buffers: the renderer reads buffer "page", the DMA writes the other one
jtframe_dual_ram16 #(.AW(12)) u_lines(
    .clk0   ( clk       ),
    .data0  ( cram_q    ),
    .addr0  ( { ~page, dma_wa } ),
    .we0    ( {2{dma_we}} ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 16'd0     ),
    .addr1  ( { page, lram_addr } ),
    .we1    ( 2'b0      ),
    .q1     ( lram_q    )
);

// ------------- renderer
localparam [3:0] IDLE=0, RD0=1, RD1=2, RD2=3, RD3=4, RD4=5, RD5=6, CALC=7, CALC2=8, PIX=9, FETCH=10, FETCHW=11, NEXT=12;

wire [15:0] scrx = { regs[0], regs[1] } + 16'd5;    // MAME map_scrollx = reg - offx (-5)
wire [15:0] scry = { regs[2], regs[3] } + 16'd16;   // map_scrolly = reg - offy (-16)
wire [ 7:0] ctrl = regs[4];
reg  [ 9:0] wrapmask;
reg  [ 3:0] st;
reg  [ 8:0] rline, x;
reg  [ 1:0] rdcnt;
reg  [15:0] color, offset, zoom, lscroll;
reg  signed [31:0] acc;    // (x + scroll) * zoom + 32
reg  signed [15:0] kbase, k;
reg  [16:0] lastw;
reg         lastv, skip, clip, wr, armed;
reg  [31:0] gfx;
reg  [ 8:0] wdata;
reg  [ 8:0] wx;
reg  [ 4:0] wl;
reg         active;         // rendering allowed (from vertical blank)
wire signed [31:0] src = acc >>> 6;
wire [19:0] nib = { offset[11:0], 8'd0 } + (clip ? src[19:0] : {10'd0, src[9:0] & wrapmask});
wire signed [31:0] kend   = acc - 32'sd32 + $signed({16'd0,zoom});      // (k+1)*zoom
wire signed [31:0] climit = $signed({16'd0,6'd0,wrapmask} + 32'd1) <<< 6;
wire        in_src = !clip || ( !k[15] && (zoom==0 ? k <= $signed({6'd0,wrapmask}) : kend <= climit) );
wire [ 8:0] disp_limit = vdump >= 9'd256 ? 9'd31 : vdump + 9'd31;
wire [ 3:0] pen = gfx_nib(nib[2:0]);

function [3:0] gfx_nib(input [2:0] n);
    case( n )
        0: gfx_nib = gfx[ 7: 4]; 1: gfx_nib = gfx[ 3: 0]; 2: gfx_nib = gfx[15:12]; 3: gfx_nib = gfx[11: 8];
        4: gfx_nib = gfx[23:20]; 5: gfx_nib = gfx[19:16]; 6: gfx_nib = gfx[31:28]; 7: gfx_nib = gfx[27:24];
    endcase
endfunction

always @* begin
    case( ctrl[7:5] )
        0, 4:    wrapmask = 10'h0ff;
        1:       wrapmask = 10'h1ff;
        default: wrapmask = 10'h3ff;
    endcase
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st     <= IDLE;
        rline  <= 0;
        active <= 0;
        rom_cs <= 0;
        wr     <= 0;
        behind <= 0;
        armed  <= 0;
    end else begin
        wr    <= 0;
        armed <= rom_cs;
        if( vb_start ) begin
            rline  <= 0;
            active <= 1;
            st     <= IDLE;
            rom_cs <= 0;
        end else case( st )
            IDLE: if( active && rline < 9'd256 && rline <= disp_limit ) begin
                lram_addr <= ( {scry[8:0], 2'd0} + {rline, 2'd0} ) & 11'h7ff;
                rdcnt <= 0;
                st    <= RD0;
            end else if( active && rline==9'd256 ) active <= 0;
            RD0: begin lram_addr[1:0] <= 2'd1; st <= RD1; end
            RD1: begin lram_addr[1:0] <= 2'd2; st <= RD2; color  <= lram_q; end
            RD2: begin lram_addr[1:0] <= 2'd3; st <= RD3; offset <= lram_q; end
            RD3: begin st <= RD4; zoom <= lram_q; end
            RD4: begin
                lscroll <= lram_q;
                st <= CALC;
            end
            CALC: begin
                skip  <= color==16'hffff || (color[7:0]==0 && offset==0) || !ctrl[0];
                clip  <= !ctrl[2];
                // wrap500: in mode 4 scroll values from 0x500 are negative
                kbase <= lscroll + ((ctrl[7:5]==4 && $signed(lscroll) >= 16'sh500) ? -16'sh800 : 16'sh0)
                         + scrx + 16'd40;
                st    <= CALC2;
            end
            CALC2: begin
`ifdef XVDEBUG
                if( rline[3:0]==0 ) $display("LVC line %d color %h offset %h zoom %h scroll %h kbase %d skip %b clip %b ctrl %h",
                    rline, color, offset, zoom, lscroll, kbase, skip, clip, ctrl);
`endif
                acc   <= kbase * $signed({1'b0,zoom}) + 32'sd32;
                k     <= kbase;
                lastv <= 0;
                x     <= 0;
                st    <= PIX;
            end
            PIX: begin
                if( skip || !in_src ) begin
                    wdata <= 0;
                    wr    <= 1;
                    st    <= NEXT;
                end else if( !lastv || lastw != nib[19:3] ) begin
                    rom_addr <= nib[19:3];
                    rom_cs   <= 1;
                    st       <= FETCHW;
                end else begin
                    wdata <= pen==0 ? 9'd0 : { color[4:0], pen };
                    wr    <= 1;
                    st    <= NEXT;
                end
                wx <= x;
                wl <= rline[4:0];
            end
            FETCHW: if( rom_ok && armed ) begin
                rom_cs <= 0;
                gfx    <= rom_data;
                lastw  <= rom_addr;
                lastv  <= 1;
                st     <= PIX;
            end
            NEXT: begin
                acc <= acc + $signed({16'd0,zoom});
                k   <= k + 16'sd1;
                x   <= x + 9'd1;
                if( x==9'd383 ) begin
                    rline <= rline + 9'd1;
                    st    <= IDLE;
                    if( rline < vdump && vdump < 9'd256 ) behind <= 1;
                end else st <= PIX;
            end
            default: st <= IDLE;
        endcase
    end
end

jtframe_dual_ram #(.DW(9),.AW(14)) u_ring(
    .clk0   ( clk           ),
    .data0  ( wdata         ),
    .addr0  ( { wl, wx }    ),
    .we0    ( wr            ),
    .q0     (               ),
    .clk1   ( clk           ),
    .data1  ( 9'd0          ),
    .addr1  ( { vdump[4:0], hdump } ),
    .we1    ( 1'b0          ),
    .q1     ( pxl           )
);

endmodule
