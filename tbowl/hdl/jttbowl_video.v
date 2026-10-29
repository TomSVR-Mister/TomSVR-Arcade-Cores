/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Tecmo Bowl video (MAME tecmo/tbowl.cpp screen_update_left / right). Two monitors of 256 x 224 (MAME rows 16-239),
 * each 384 x 264 at 6 MHz. Every layer is drawn one line ahead into a 512 pixel line buffer: x 0-255 is the left
 * monitor, x 256-511 the right one (MAME adds 32*8 to the scroll of every layer, and to the sprite x, for the right
 * screen). The output reads that line either as 512 pixels at 12 MHz (side by side) or as 256 pixels at 6 MHz from
 * one half, with the same line timing.
 *   Layers, bottom to top: bg 1 (c000 RAM, palette 300-3ff), sprites (000-1ff), bg 2 (a000 RAM, 200-2ff, code ^ 400),
 *   text (e000 RAM, 100-1ff). Pen 0 is transparent everywhere; with nothing drawn the colour is 100.
 *   Palette RAM e000-efff on the sub CPU: 2048 colours of xBRG 444, big endian (only 000-3ff are used). */
module jttbowl_video(
    input              rst,
    input              clk,
    input       [ 1:0] mode,        // 0 side by side, 1 left monitor, 2 right monitor
    input       [ 3:0] gfx_en,
    output reg         pxl_cen,
    output reg         pxl2_cen,
    // main CPU: tile map RAM
    input       [12:0] main_addr,
    input       [ 7:0] main_dout,
    input              bg0_we, bg1_we, txt_we,
    output      [ 7:0] bg0_dout, bg1_dout, txt_dout,
    input       [10:0] scrx0, scrx1,
    input       [ 8:0] scry0, scry1,
    // sub CPU: sprite and palette RAM
    input       [11:0] sub_addr,
    input       [ 7:0] sub_dout,
    input              obj_we, pal_we,
    output      [ 7:0] obj_dout,
    output      [ 7:0] pal_dout,
    // graphics
    output      [18:2] bg0_addr,
    output             bg0_cs,
    input       [31:0] bg0_data,
    input              bg0_ok,
    output      [18:2] bg1_addr,
    output             bg1_cs,
    input       [31:0] bg1_data,
    input              bg1_ok,
    output      [15:2] txt_addr,
    output             txt_cs,
    input       [31:0] txt_data,
    input              txt_ok,
    output      [18:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,

    output reg         irq_vb,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 3:0] red,
    output reg  [ 3:0] green,
    output reg  [ 3:0] blue
);

localparam [9:0] HTOTAL=10'd767, HS_START=10'd600, HS_END=10'd664;  // 12 MHz units
localparam [8:0] VTOTAL=9'd263, VB_END=9'd16, VB_START=9'd240, VS_START=9'd244, VS_END=9'd247;

// ---------------- timing ----------------
reg  [ 1:0] cdiv=0;
reg  [ 9:0] h=0;
reg  [ 8:0] vdump=0, vrender=1;
reg         cen12, lvbl, line_start, clr_go;
reg  [ 1:0] hbl_sh, vbl_sh;
wire        dual  = mode==0;
wire        right = mode==2;
wire        rd_cen = dual ? cen12 : cen12 & h[0];
wire [ 8:0] rd_x  = dual ? h[8:0] : { right, h[8:1] };

assign LHBL = hbl_sh[1];
assign LVBL = vbl_sh[1];

always @(posedge clk) begin
    cdiv     <= cdiv + 1'd1;
    cen12    <= cdiv==3;
    pxl_cen  <= dual ? cdiv==3 : cdiv==3 && h[0];
    pxl2_cen <= dual ? cdiv[0] : cdiv==3;
end

always @(posedge clk) begin
    line_start <= 0;
    irq_vb     <= 0;
    clr_go     <= 0;
    if( cen12 ) begin
        clr_go <= h==10'd514;       // the last active pixel has been read
        h <= h==HTOTAL ? 10'd0 : h+10'd1;
        if( h==HTOTAL ) begin
            vdump      <= vrender;
            vrender    <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
            lvbl       <= vrender >= VB_END && vrender < VB_START;
            line_start <= 1;
            irq_vb     <= vrender==VB_START;
        end
        if( h==HS_START ) begin
            HS <= 1;
            if( vdump==VS_START ) VS <= 1;
            if( vdump==VS_END   ) VS <= 0;
        end
        if( h==HS_END ) HS <= 0;
    end
end

// ---------------- tile map RAM: codes and attributes kept apart ----------------
wire [ 7:0] c0, a0, c1, a1, ct, at, cpu_c0, cpu_a0, cpu_c1, cpu_a1, cpu_ct, cpu_at;
wire [11:0] va0, va1;
wire [10:0] vat;
reg         r12, r11;
always @(posedge clk) begin r12 <= main_addr[12]; r11 <= main_addr[11]; end
assign bg0_dout = r12 ? cpu_a0 : cpu_c0;
assign bg1_dout = r12 ? cpu_a1 : cpu_c1;
assign txt_dout = r11 ? cpu_at : cpu_ct;

jtframe_dual_ram #(.AW(12)) u_c0(
    .clk0( clk ), .data0( main_dout ), .addr0( main_addr[11:0] ), .we0( bg0_we && !main_addr[12] ), .q0( cpu_c0 ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( va0 ), .we1( 1'b0 ), .q1( c0 ) );
jtframe_dual_ram #(.AW(12)) u_a0(
    .clk0( clk ), .data0( main_dout ), .addr0( main_addr[11:0] ), .we0( bg0_we &&  main_addr[12] ), .q0( cpu_a0 ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( va0 ), .we1( 1'b0 ), .q1( a0 ) );
jtframe_dual_ram #(.AW(12)) u_c1(
    .clk0( clk ), .data0( main_dout ), .addr0( main_addr[11:0] ), .we0( bg1_we && !main_addr[12] ), .q0( cpu_c1 ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( va1 ), .we1( 1'b0 ), .q1( c1 ) );
jtframe_dual_ram #(.AW(12)) u_a1(
    .clk0( clk ), .data0( main_dout ), .addr0( main_addr[11:0] ), .we0( bg1_we &&  main_addr[12] ), .q0( cpu_a1 ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( va1 ), .we1( 1'b0 ), .q1( a1 ) );
jtframe_dual_ram #(.AW(11)) u_ct(
    .clk0( clk ), .data0( main_dout ), .addr0( main_addr[10:0] ), .we0( txt_we && !main_addr[11] ), .q0( cpu_ct ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( vat ), .we1( 1'b0 ), .q1( ct ) );
jtframe_dual_ram #(.AW(11)) u_at(
    .clk0( clk ), .data0( main_dout ), .addr0( main_addr[10:0] ), .we0( txt_we &&  main_addr[11] ), .q0( cpu_at ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( vat ), .we1( 1'b0 ), .q1( at ) );

// ---------------- sprite RAM d800-dfff: one byte lane per entry byte ----------------
wire [63:0] odata, cpu_olanes;
wire [ 7:0] oaddr;
reg  [ 2:0] olane;
always @(posedge clk) olane <= sub_addr[2:0];
assign obj_dout = cpu_olanes[ olane*8 +: 8 ];

genvar gi;
generate
    for( gi=0; gi<8; gi=gi+1 ) begin : obj_lanes
        jtframe_dual_ram #(.AW(8)) u_lane(
            .clk0( clk ), .data0( sub_dout ), .addr0( sub_addr[10:3] ), .we0( obj_we && sub_addr[2:0]==gi ),
            .q0( cpu_olanes[gi*8+:8] ),
            .clk1( clk ), .data1( 8'd0 ), .addr1( oaddr ), .we1( 1'b0 ), .q1( odata[gi*8+:8] ) );
    end
endgenerate

// ---------------- palette RAM: even (high) and odd (low) bytes ----------------
wire [ 7:0] pal_e, pal_o, ve, vo;
reg  [ 9:0] pal_idx;
reg         sa0;
always @(posedge clk) sa0 <= sub_addr[0];
assign pal_dout = sa0 ? pal_o : pal_e;

jtframe_dual_ram #(.AW(11)) u_pale(
    .clk0( clk ), .data0( sub_dout ), .addr0( sub_addr[11:1] ), .we0( pal_we && !sub_addr[0] ), .q0( pal_e ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( { 1'b0, pal_idx } ), .we1( 1'b0 ), .q1( ve ) );
jtframe_dual_ram #(.AW(11)) u_palo(
    .clk0( clk ), .data0( sub_dout ), .addr0( sub_addr[11:1] ), .we0( pal_we &&  sub_addr[0] ), .q0( pal_o ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( { 1'b0, pal_idx } ), .we1( 1'b0 ), .q1( vo ) );

// ---------------- layers ----------------
wire [ 9:0] rd_addr = { vdump[0], rd_x };
wire [ 7:0] bg0, bg1, txt;
wire [ 8:0] obj;

jttbowl_tile #(.BIG(1)) u_bg0(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .line_start ( line_start),
    .vrender    ( vrender   ),
    .scrx       ( scrx0     ),
    .scry       ( scry0     ),
    .vaddr      ( va0       ),
    .vcode      ( c0        ),
    .vattr      ( a0        ),
    .gfx_addr   ( bg0_addr  ),
    .gfx_cs     ( bg0_cs    ),
    .gfx_data   ( bg0_data  ),
    .gfx_ok     ( bg0_ok    ),
    .rd_addr    ( rd_addr   ),
    .pxl        ( bg0       )
);

jttbowl_tile #(.BIG(1),.XORC(12'h400)) u_bg1(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .line_start ( line_start),
    .vrender    ( vrender   ),
    .scrx       ( scrx1     ),
    .scry       ( scry1     ),
    .vaddr      ( va1       ),
    .vcode      ( c1        ),
    .vattr      ( a1        ),
    .gfx_addr   ( bg1_addr  ),
    .gfx_cs     ( bg1_cs    ),
    .gfx_data   ( bg1_data  ),
    .gfx_ok     ( bg1_ok    ),
    .rd_addr    ( rd_addr   ),
    .pxl        ( bg1       )
);

jttbowl_tile #(.BIG(0)) u_txt(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .line_start ( line_start),
    .vrender    ( vrender   ),
    .scrx       ( 11'd0     ),
    .scry       ( 9'd0      ),
    .vaddr      ( vat       ),
    .vcode      ( ct        ),
    .vattr      ( at        ),
    .gfx_addr   ( txt_addr  ),
    .gfx_cs     ( txt_cs    ),
    .gfx_data   ( txt_data  ),
    .gfx_ok     ( txt_ok    ),
    .rd_addr    ( rd_addr   ),
    .pxl        ( txt       )
);

jttbowl_obj u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .line_start ( line_start),
    .vrender    ( vrender   ),
    .clr_go     ( clr_go    ),
    .oaddr      ( oaddr     ),
    .odata      ( odata     ),
    .gfx_addr   ( obj_addr  ),
    .gfx_cs     ( obj_cs    ),
    .gfx_data   ( obj_data  ),
    .gfx_ok     ( obj_ok    ),
    .rd_addr    ( rd_addr   ),
    .pxl        ( obj       )
);

// ---------------- colour mixer ----------------
wire txt_op = txt[3:0]!=0 && gfx_en[0];
wire bg1_op = bg1[3:0]!=0 && gfx_en[1];
wire obj_op = obj[3:0]!=0 && gfx_en[3];
wire bg0_op = bg0[3:0]!=0 && gfx_en[2];

always @(posedge clk) if( rd_cen ) begin
    pal_idx <= txt_op ? { 2'b01, txt } :
               bg1_op ? { 2'b10, bg1 } :
               obj_op ? { 1'b0,  obj } :
               bg0_op ? { 2'b11, bg0 } : 10'h100;
    hbl_sh  <= { hbl_sh[0], h < 10'd512 };
    vbl_sh  <= { vbl_sh[0], lvbl };
    if( rst ) begin                 // black while the ROMs load
        red   <= 0;
        green <= 0;
        blue  <= 0;
    end else begin
        red   <= vo[7:4];
        green <= vo[3:0];
        blue  <= ve[3:0];
    end
end

endmodule
