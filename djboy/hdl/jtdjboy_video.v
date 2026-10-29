/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DJ Boy / Air Buster video (MAME djboy.cpp / airbustr.cpp screen_update):
 *   6 MHz pixel clock, 384 x 272 (57.4 Hz), visible 256 x 224 = MAME rows 16-239.
 *   DJ Boy:     one 64x32 tile layer (palette 000-0ff) under the Pandora sprites (100-1ff); xRGB_444, big endian.
 *               scroll x = { port 00 bits 7-6, port 08 } - 0x391, scroll y = { port 00 bit 5, port 06 }
 *   Air Buster: bg layer (palette 100-1ff), fg layer (000-0ff, pen 0 transparent), sprites (200-2ff); xGRB_555,
 *               little endian. Scroll = { high bit, low byte }, x - 0x94, y - 0x100 (MAME scrolldx/dy).
 *   Screen flip is not done (MAME does not flip DJ Boy either). */
module jtdjboy_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              abus,
    input       [ 3:0] gfx_en,
    // sub CPU access
    input       [11:0] cpu_addr,
    input       [ 7:0] cpu_dout,
    input              vram_we,
    output      [ 7:0] vram_dout,
    input              pal_we,
    output      [ 7:0] pal_dout,
    // registers
    input       [ 7:0] vreg,
    input       [ 7:0] scrx0, scry0, scrx1, scry1, scrhi,
    // sprite RAM copy
    output      [11:0] ovid_addr,
    input       [ 7:0] ovid_dout,
    output             ocopy,
    // graphics
    output      [19:2] scr0_addr,
    output             scr0_cs,
    input       [31:0] scr0_data,
    input              scr0_ok,
    output      [19:2] scr1_addr,
    output             scr1_cs,
    input       [31:0] scr1_data,
    input              scr1_ok,
    output      [20:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,

    output reg         irq_vb,
    output reg         irq_64,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd383, HS_START=9'd300, HS_END=9'd332;
localparam [8:0] VTOTAL=9'd271, VB_END=9'd16, VB_START=9'd240, VS_START=9'd250, VS_END=9'd253;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl, hs_l;
reg  [ 3:0] hbl_sh, vbl_sh;
wire        hs_start = pxl_cen && hdump==0 && !hs_l;

assign LHBL = hbl_sh[1];
assign LVBL = vbl_sh[1];

always @(posedge clk) if( pxl_cen ) hs_l <= hdump==0;

always @(posedge clk) begin
    irq_vb <= hs_start && vdump==VB_START;
    irq_64 <= hs_start && vdump==9'd64;
end

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    lhbl <= hdump==HTOTAL || hdump < 9'd255;
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[2:0], lhbl };
    vbl_sh <= { vbl_sh[2:0], lvbl };
end

// ---------------- tile map RAM: codes and attributes kept apart, one copy per layer ----------------
wire        vrole = abus ? cpu_addr[10] : cpu_addr[11];        // 1 = attribute
wire [10:0] vidx  = abus ? { cpu_addr[11], cpu_addr[9:0] } : cpu_addr[10:0];
wire [10:0] v0a, v1a, va0, va1;
wire [ 7:0] code0, attr0, code1, attr1, cpu_code, cpu_attr;
reg         vrole_l;

assign v0a = abus ? { 1'b1, va0[9:0] } : va0;     // airbustr bg = c800/cc00
assign v1a = { 1'b0, va1[9:0] };                  // airbustr fg = c000/c400
always @(posedge clk) vrole_l <= vrole;
assign vram_dout = vrole_l ? cpu_attr : cpu_code;

jtframe_dual_ram #(.AW(11)) u_code0(
    .clk0( clk ), .data0( cpu_dout ), .addr0( vidx ), .we0( vram_we && !vrole ), .q0( cpu_code ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( v0a ), .we1( 1'b0 ), .q1( code0 ) );
jtframe_dual_ram #(.AW(11)) u_attr0(
    .clk0( clk ), .data0( cpu_dout ), .addr0( vidx ), .we0( vram_we &&  vrole ), .q0( cpu_attr ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( v0a ), .we1( 1'b0 ), .q1( attr0 ) );
jtframe_dual_ram #(.AW(11)) u_code1(
    .clk0( clk ), .data0( cpu_dout ), .addr0( vidx ), .we0( vram_we && !vrole ), .q0(),
    .clk1( clk ), .data1( 8'd0 ), .addr1( v1a ), .we1( 1'b0 ), .q1( code1 ) );
jtframe_dual_ram #(.AW(11)) u_attr1(
    .clk0( clk ), .data0( cpu_dout ), .addr0( vidx ), .we0( vram_we &&  vrole ), .q0(),
    .clk1( clk ), .data1( 8'd0 ), .addr1( v1a ), .we1( 1'b0 ), .q1( attr1 ) );

// ---------------- palette RAM d000-dfff (also plain RAM past the palette), even / odd bytes ----------------
wire [ 7:0] pal_e, pal_o, ve, vo;
reg  [ 9:0] pal_idx;
reg         a0_l;
always @(posedge clk) a0_l <= cpu_addr[0];
assign pal_dout = a0_l ? pal_o : pal_e;

jtframe_dual_ram #(.AW(11)) u_pale(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[11:1] ), .we0( pal_we && !cpu_addr[0] ), .q0( pal_e ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( { 1'b0, pal_idx } ), .we1( 1'b0 ), .q1( ve ) );
jtframe_dual_ram #(.AW(11)) u_palo(
    .clk0( clk ), .data0( cpu_dout ), .addr0( cpu_addr[11:1] ), .we0( pal_we &&  cpu_addr[0] ), .q0( pal_o ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( { 1'b0, pal_idx } ), .we1( 1'b0 ), .q1( vo ) );

// ---------------- layers ----------------
wire [ 9:0] sx0 = abus ? { 1'b0, scrhi[2], scrx0 } - 10'h094 : { vreg[7:6], scrx0 } - 10'h391;
wire [ 8:0] sy0 = abus ? { ~scrhi[3], scry0 } : { vreg[5], scry0 };
wire [ 9:0] sx1 = { 1'b0, scrhi[0], scrx1 } - 10'h094;
wire [ 8:0] sy1 = { ~scrhi[1], scry1 };
wire [ 7:0] bg, fg, obj;

jtdjboy_tile u_bg(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .hs_start   ( hs_start  ),
    .vrender    ( vrender   ),
    .vdump      ( vdump     ),
    .hdump      ( hdump     ),
    .wide       ( ~abus     ),
    .lsb        ( abus      ),
    .scrx       ( sx0       ),
    .scry       ( sy0       ),
    .vaddr      ( va0       ),
    .vcode      ( code0     ),
    .vattr      ( attr0     ),
    .gfx_addr   ( scr0_addr ),
    .gfx_cs     ( scr0_cs   ),
    .gfx_data   ( scr0_data ),
    .gfx_ok     ( scr0_ok   ),
    .pxl        ( bg        )
);

jtdjboy_tile u_fg(
    .rst        ( rst | ~abus ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .hs_start   ( hs_start  ),
    .vrender    ( vrender   ),
    .vdump      ( vdump     ),
    .hdump      ( hdump     ),
    .wide       ( 1'b0      ),
    .lsb        ( 1'b1      ),
    .scrx       ( sx1       ),
    .scry       ( sy1       ),
    .vaddr      ( va1       ),
    .vcode      ( code1     ),
    .vattr      ( attr1     ),
    .gfx_addr   ( scr1_addr ),
    .gfx_cs     ( scr1_cs   ),
    .gfx_data   ( scr1_data ),
    .gfx_ok     ( scr1_ok   ),
    .pxl        ( fg        )
);

jtdjboy_obj u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .hs_start   ( hs_start  ),
    .vdump      ( vdump     ),
    .hdump      ( hdump     ),
    .abus       ( abus      ),
    .clr        ( ~abus | vreg[5] ),
    .ovid_addr  ( ovid_addr ),
    .ovid_dout  ( ovid_dout ),
    .ocopy      ( ocopy     ),
    .gfx_addr   ( obj_addr  ),
    .gfx_cs     ( obj_cs    ),
    .gfx_data   ( obj_data  ),
    .gfx_ok     ( obj_ok    ),
    .pxl        ( obj       )
);

// ---------------- colour mixer ----------------
wire obj_op = obj[3:0]!=0 && gfx_en[3];
wire fg_op  = abus && fg[3:0]!=0 && gfx_en[1];
wire [15:0] w = abus ? { vo, ve } : { ve, vo };

always @(posedge clk) if( pxl_cen ) begin
    pal_idx <= obj_op ? { abus, ~abus, obj } :
               fg_op  ? { 2'b00, fg } :
               { 1'b0, abus, gfx_en[0] ? bg : 8'd0 };
    if( rst ) begin                 // black while the ROMs load (the frame would show stale RAM)
        red   <= 0;
        green <= 0;
        blue  <= 0;
    end else if( abus ) begin
        red   <= w[ 9: 5];
        green <= w[14:10];
        blue  <= w[ 4: 0];
    end else begin
        red   <= { w[11:8], w[11] };
        green <= { w[ 7:4], w[ 7] };
        blue  <= { w[ 3:0], w[ 3] };
    end
end

endmodule
