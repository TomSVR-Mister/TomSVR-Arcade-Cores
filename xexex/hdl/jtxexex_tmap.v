/*  This file is part of JTXEXEX.
    SPDX-License-Identifier: GPL-3.0-or-later
    Konami K054156/K054157 tilemap pair as used by Xexex, written from MAME's k054156_k054157_k056832.cpp
    and checked against MAME frames.

    Four layers (A-D) of 8x8 4bpp tiles. VRAM holds pages of 64x32 tiles, two words per tile
    (attribute, code). Xexex only uses page columns 0 and 1, so eight pages are kept:
    page = { grid row[1:0], grid column[0] }. Each layer spans (h+1) x (w+1) pages of the 4x4 grid,
    and a page belongs to the last layer (A..D order) that covers it.

    Xexex runs the chip with screen flip Y (register 0 bit 5). Measured against MAME, the layer row
    shown on screen line y is V = 15 + dy - y (modulo the layer height), with the page row counted
    from the bottom, and the column is X = 40 + x + scroll x - layer offset.

    Each layer renders the next line into a double line buffer while the current one is shown.
    Pixel output: { alpha flag, palette[6:0], pen[3:0] }, pen 0 is transparent. */

module jtxexex_tmap(
    input             rst,
    input             clk,
    input             pxl_cen,

    input      [ 8:0] hdump,       // 0-383 visible
    input      [ 8:0] vrender,     // line being rendered
    input             line_start,  // one clock, start of vrender

    // CPU interface
    input      [12:1] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input             cpu_we,
    input             reg_cs,      // 0C0000-0C003F
    input             ram_cs,      // 180000-183FFF
    output     [15:0] ram_dout,

    // colour bases from the K053251, in units of 16 colours
    input      [ 6:0] cb_b, cb_c, cb_d,

    // tile ROM
    output reg [20:2] rom_addr,
    output reg        rom_cs,
    input      [31:0] rom_data,
    input             rom_ok,

    output     [11:0] pxl_a, pxl_b, pxl_c, pxl_d,

    input      [ 3:0] gfx_en
);

reg  [15:0] regs[0:31];
wire [ 2:0] cpu_page;
wire [15:0] vram_q;
reg  [14:0] vram_addr;

// CPU register writes
always @(posedge clk, posedge rst) begin
    if( rst ) begin : clr
        integer k;
        for( k=0; k<32; k=k+1 ) regs[k] <= 0;
    end else if( reg_cs && cpu_we ) begin
        if( !cpu_dsn[1] ) regs[cpu_addr[5:1]][15:8] <= cpu_dout[15:8];
        if( !cpu_dsn[0] ) regs[cpu_addr[5:1]][ 7:0] <= cpu_dout[ 7:0];
    end
end

// CPU RAM bank (register 0x32): ---r r--c
assign cpu_page = { regs[25][4:3], regs[25][0] };

jtframe_dual_ram16 #(.AW(15)) u_vram(
    .clk0   ( clk       ),
    .data0  ( cpu_dout  ),
    .addr0  ( { cpu_page, cpu_addr[12:1] } ),
    .we0    ( ~cpu_dsn & {2{ram_cs & cpu_we}} ),
    .q0     ( ram_dout  ),
    .clk1   ( clk       ),
    .data1  ( 16'd0     ),
    .addr1  ( vram_addr ),
    .we1    ( 2'b0      ),
    .q1     ( vram_q    )
);

// page ownership: the last layer that covers a page of the 4x4 grid wins
reg [2:0] owner[0:15];      // { valid, layer }
always @* begin : assoc
    integer l, r, c;
    for( r=0; r<16; r=r+1 ) owner[r] = 3'd0;
    for( l=0; l<4; l=l+1 )
        for( r=0; r<4; r=r+1 )
            for( c=0; c<4; c=c+1 )
                if( r <= {30'd0,regs[8+l][1:0]} && c <= {30'd0,regs[12+l][1:0]} )
                    owner[ { regs[8+l][4:3]+r[1:0], regs[12+l][4:3]+c[1:0] } ] = { 1'b1, l[1:0] };
end

// VRAM time slots shared by the four layer engines
reg  [ 1:0] slot;
wire [14:0] eng_addr[0:3];
reg  [ 1:0] slot_l;

always @(posedge clk) begin
    slot      <= slot + 2'd1;
    slot_l    <= slot;
    vram_addr <= eng_addr[slot];
end

// ROM requests are served one at a time
wire [ 3:0] rq;
wire [20:2] eng_rom[0:3];
reg  [ 1:0] rsel;
reg         rbusy, armed;
reg  [ 3:0] rdone;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        armed  <= 0;
        rbusy  <= 0;
        rom_cs <= 0;
        rsel   <= 0;
        rdone  <= 0;
    end else begin
        rdone <= 0;
        armed <= rom_cs;    // rom_ok is only trusted one clock after the request
        if( !rbusy ) begin
            rom_cs <= 0;
            if( rq != 0 ) begin
                rsel     <= rq[0] ? 2'd0 : rq[1] ? 2'd1 : rq[2] ? 2'd2 : 2'd3;
                rom_addr <= rq[0] ? eng_rom[0] : rq[1] ? eng_rom[1] : rq[2] ? eng_rom[2] : eng_rom[3];
                rbusy    <= 1;
                rom_cs   <= 1;
            end
        end else if( rom_ok && rom_cs && armed ) begin
            rom_cs      <= 0;
            armed       <= 0;
            rdone[rsel] <= 1;
        end else if( !rom_cs ) begin
            rbusy <= 0;
        end
    end
end

reg [31:0] rom_latch;
always @(posedge clk) if( rom_ok && rom_cs && armed ) rom_latch <= rom_data;

wire [11:0] pxl[0:3];
assign pxl_a = gfx_en[0] ? pxl[0] : 12'd0;
assign pxl_b = gfx_en[1] ? pxl[1] : 12'd0;
assign pxl_c = gfx_en[2] ? pxl[2] : 12'd0;
assign pxl_d = gfx_en[3] ? pxl[3] : 12'd0;

wire [6:0] cbase[0:3];
assign cbase[0] = 7'h70;
assign cbase[1] = cb_b;
assign cbase[2] = cb_c;
assign cbase[3] = cb_d;

// per layer offsets (MAME set_layer_offs): -2, 2, 4, 6
wire [8:0] xoff[0:3];
assign xoff[0] = -9'd2;
assign xoff[1] =  9'd2;
assign xoff[2] =  9'd4;
assign xoff[3] =  9'd6;

genvar L;
generate for( L=0; L<4; L=L+1 ) begin : layer
    localparam [1:0] LL = L[1:0];
    localparam [3:0] IDLE=0, SCR=1, SCRW1=2, SCRW2=3, ATTR=4, ATTRW1=5, ATTRW2=6,
                     ATTRW3=7, ATTRW4=8, CODEW1=9, CODEW2=10, CODEW3=11, FETCH=12, ROMW=13, DRAW=14;
    reg  [ 3:0] st;
    reg  [14:0] addr;
    reg  [ 5:0] col;          // tile count, 49 per line
    reg  [10:0] xpos;         // layer X of the current tile
    reg  [ 9:0] vpos;
    reg  [ 8:0] bufx;
    reg  [15:0] attr, code;
    reg  [31:0] gfx;
    reg  [ 2:0] cnt;
    reg         we, valid, wbank, req;
    reg  [11:0] wdata;
    reg  [10:0] sx;
    wire [ 1:0] h = regs[8+L][1:0], w = regs[12+L][1:0];
    wire [ 1:0] y0 = regs[8+L][4:3], x0 = regs[12+L][4:3];
    wire [ 1:0] mode = regs[5][L*2+:2];
    wire [ 1:0] prow;
    wire [ 3:0] gpage;
    wire [ 3:0] pen, pen_fx;
    wire [ 9:0] vfull;
    wire [10:0] wmask = { w, 9'h1ff };
    wire [10:0] x0full = (11'd40 + sx - {{2{xoff[L][8]}},xoff[L]}) & wmask;
    wire        tflipx, tflipy;
    wire [ 2:0] trow;

    // V = 15 + dy - y, modulo 256*(h+1)
    assign vfull = 10'd15 + regs[16+L][9:0] - {1'b0,vrender};
    wire [10:0] vmod3 = vfull >= 10'd768 ? {1'b0,vfull} - 11'd768 : {1'b0,vfull};
    wire [ 9:0] vline = h==2 ? vmod3[9:0] : (vfull & {h,8'hff});
    assign prow   = h - vpos[9:8];
    assign gpage  = { y0 + prow, x0 + xpos[10:9] };
    assign tflipx = attr[0] & regs[1][L*2];
    assign tflipy = attr[1] & regs[1][L*2+1];
    assign trow   = vpos[2:0] ^ {3{tflipy}};
    // Quartus does not take functions inside generate loops: gfx nibbles in drawing order
    wire [3:0] nibs[0:7];
    assign nibs[0] = gfx[15:12]; assign nibs[1] = gfx[11: 8]; assign nibs[2] = gfx[ 7: 4]; assign nibs[3] = gfx[ 3: 0];
    assign nibs[4] = gfx[31:28]; assign nibs[5] = gfx[27:24]; assign nibs[6] = gfx[23:20]; assign nibs[7] = gfx[19:16];
    assign pen    = nibs[cnt];
    assign pen_fx = nibs[~cnt];
    assign eng_addr[L] = addr;
    assign eng_rom[L]  = { code, trow };
    assign rq[L]       = req;

    always @(posedge clk, posedge rst) begin
        if( rst ) begin
            st  <= IDLE;
            we  <= 0;
            req <= 0;
        end else begin
            we <= 0;
            case( st )
                IDLE: if( line_start ) begin
                    vpos  <= vline;
                    wbank <= vrender[0];
                    col   <= 0;
                    sx    <= regs[20+L][10:0];
                    // line scroll: page from register 0x30, 0x400 words per layer, two words per line
                    addr  <= { regs[24][4:3], regs[24][0], LL, vline[8:0] & {6'h3f, mode==2 ? 3'd0 : 3'd7}, 1'b1 };
                    st    <= mode==3 ? ATTR : SCR;
                end
                // VRAM reads: the address goes out on our slot, data is valid two clocks later
                SCR:   if( slot==LL ) st <= SCRW1;
                SCRW1: st <= SCRW2;
                SCRW2: begin
                    sx <= vram_q[10:0];
                    st <= ATTR;
                end
                ATTR: begin
                    if( col==0 ) begin
                        xpos <= x0full & ~11'd7;
                        bufx <= -{6'd0, x0full[2:0]};
                    end
                    st <= ATTRW1;
                end
                ATTRW1: begin
                    valid <= owner[gpage] == {1'b1, LL};
                    addr  <= { gpage[3:2], gpage[0], vpos[7:3], xpos[8:3], 1'b0 };
                    st    <= ATTRW2;
                end
                ATTRW2: if( slot==LL ) st <= ATTRW3;   // attribute address goes out
                ATTRW3: begin addr[0] <= 1; st <= ATTRW4; end
                ATTRW4: begin attr <= vram_q; st <= CODEW1; end
                CODEW1: if( slot==LL ) st <= CODEW2;   // code address goes out
                CODEW2: st <= CODEW3;
                CODEW3: begin code <= vram_q; st <= FETCH; end
                FETCH: begin
                    req <= valid;
                    cnt <= 0;
                    if( !valid ) begin
                        gfx <= 0;
                        st  <= DRAW;
                    end else st <= ROMW;
                end
                ROMW: if( rdone[L] ) begin
                    req <= 0;
                    gfx <= rom_latch;
                    st  <= DRAW;
                end
                DRAW: begin
                    we    <= 1;
                    wdata <= { attr[2], cbase[L] | {3'd0,attr[7:4]}, tflipx ? pen_fx : pen };
                    bufx  <= bufx + 9'd1;
                    cnt   <= cnt + 3'd1;
                    if( cnt==7 ) begin
                        col  <= col + 6'd1;
                        xpos <= (xpos + 11'd8) & wmask;
                        st   <= col==48 ? IDLE : ATTR;
                    end
                end
                default: st <= IDLE;
            endcase
        end
    end

    // keep the write address of the pixel being written
    reg [8:0] wx;
    always @(posedge clk) if( st==DRAW ) wx <= bufx;

    jtframe_dual_ram #(.DW(12),.AW(10)) u_line(
        .clk0   ( clk                ),
        .data0  ( wdata[3:0]!=0 ? wdata : 12'd0 ),
        .addr0  ( { wbank, wx }      ),
        .we0    ( we                 ),
        .q0     (                    ),
        .clk1   ( clk                ),
        .data1  ( 12'd0              ),
        .addr1  ( { ~wbank, hdump }  ),
        .we1    ( 1'b0               ),
        .q1     ( pxl[L]             )
    );
end endgenerate

endmodule
