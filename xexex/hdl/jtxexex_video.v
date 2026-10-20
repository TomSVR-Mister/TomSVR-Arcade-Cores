/*  This file is part of JTXEXEX.
    SPDX-License-Identifier: GPL-3.0-or-later
    Xexex video: 8 MHz pixel clock, 512 x 289 (54 Hz). MAME shows bitmap X 40-423 and lines 0-255.
    hcnt/vcnt follow MAME's coordinates: line 256 starts vertical blank. */

module jtxexex_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,

    // CPU interface
    input      [14:1] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input             cpu_we,
    input             tmap_reg_cs,
    input             tmap_ram_cs,
    input             lvc_ram_cs,
    input             lvc_reg_cs,
    input             obj_ram_cs,
    input             obj_reg_cs,
    input             pal_cs,
    input             k251_cs,
    input             k338_cs,
    input             objcha_n,
    input             alpha_off,
    output     [15:0] tmap_dout,
    output     [15:0] lvc_dout,
    output     [ 7:0] lvc_reg_dout,
    output     [15:0] obj_dout,
    output     [15:0] pal_dout,
    output            dma_bsy,
    output reg        vb_start,   // one clock, line 256
    output     [ 8:0] vdump,

    // ROMs
    output     [20:2] tile_addr,
    output            tile_cs,
    input      [31:0] tile_data,
    input             tile_ok,
    output     [18:2] lvc_addr,
    output            lvc_cs,
    input      [31:0] lvc_data,
    input             lvc_ok,
    output     [21:2] obj_addr,
    output            obj_cs,
    input      [31:0] obj_data,
    input             obj_ok,

    output reg        LHBL,
    output reg        LVBL,
    output reg        HS,
    output reg        VS,
    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    input      [ 7:0] gfx_en,
    input      [ 7:0] debug_bus
);

parameter [8:0] HB_END=9'd40, HB_START=9'd424, HS_START=9'd448, HS_END=9'd480;
parameter [8:0] VTOTAL=9'd288, VB_START=9'd256, VS_START=9'd268, VS_END=9'd271;
parameter [9:0] OBJ_HOFFSET=10'd464;   // matched to MAME frames with the video bench
parameter [9:0] OBJ_VOFFSET=10'd33;

reg  [ 8:0] hcnt=0, vcnt=0, vrender=1;
reg         line_start;
wire [ 8:0] xvis = hcnt - HB_END;
wire [11:0] lyra, lyrb, lyrc, lyrd;
wire [ 8:0] lvc_pxl, obj_pxl;
wire [ 4:0] obj_pri;
wire [ 1:0] obj_shd;
wire [ 6:0] cb_b, cb_c, cb_d;
wire        lvc_behind;
wire [22:2] obj_full;

assign obj_addr = obj_full[21:2];
assign vdump    = vcnt;

always @(posedge clk) begin
    line_start <= 0;
    vb_start   <= 0;
    if( pxl_cen ) begin
        hcnt <= hcnt + 9'd1;   // 512 pixels per line
        if( hcnt==9'd511 ) begin
            vcnt    <= vcnt==VTOTAL ? 9'd0 : vcnt + 9'd1;
            vrender <= vrender==VTOTAL ? 9'd0 : vrender + 9'd1;
            line_start <= 1;
            if( vcnt==VB_START-9'd1 ) vb_start <= 1;
        end
        if( hcnt==HB_END-9'd1 ) LHBL <= 1;
        if( hcnt==HB_START-9'd1 ) LHBL <= 0;
        if( hcnt==HS_START ) HS <= 1;
        if( hcnt==HS_END   ) HS <= 0;
        if( hcnt==9'd511 ) begin
            if( vcnt==VTOTAL ) LVBL <= 1;
            if( vcnt==VB_START-9'd1 ) LVBL <= 0;
            if( vcnt==VS_START ) VS <= 1;
            if( vcnt==VS_END   ) VS <= 0;
        end
    end
end

jtxexex_tmap u_tmap(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .hdump      ( xvis          ),
    .vrender    ( vrender       ),
    .line_start ( line_start    ),
    .cpu_addr   ( cpu_addr[12:1]),
    .cpu_dout   ( cpu_dout      ),
    .cpu_dsn    ( cpu_dsn       ),
    .cpu_we     ( cpu_we        ),
    .reg_cs     ( tmap_reg_cs   ),
    .ram_cs     ( tmap_ram_cs   ),
    .ram_dout   ( tmap_dout     ),
    .cb_b       ( cb_b          ),
    .cb_c       ( cb_c          ),
    .cb_d       ( cb_d          ),
    .rom_addr   ( tile_addr     ),
    .rom_cs     ( tile_cs       ),
    .rom_data   ( tile_data     ),
    .rom_ok     ( tile_ok       ),
    .pxl_a      ( lyra          ),
    .pxl_b      ( lyrb          ),
    .pxl_c      ( lyrc          ),
    .pxl_d      ( lyrd          ),
    .gfx_en     ( gfx_en[3:0]   )
);

jtxexex_lvc u_lvc(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .hdump      ( xvis          ),
    .vdump      ( vcnt          ),
    .vb_start   ( vb_start      ),
    .cpu_addr   ( cpu_addr[12:1]),
    .cpu_dout   ( cpu_dout      ),
    .cpu_dsn    ( cpu_dsn       ),
    .cpu_we     ( cpu_we        ),
    .ram_cs     ( lvc_ram_cs    ),
    .reg_cs     ( lvc_reg_cs    ),
    .ram_dout   ( lvc_dout      ),
    .reg_dout   ( lvc_reg_dout  ),
    .rom_addr   ( lvc_addr      ),
    .rom_cs     ( lvc_cs        ),
    .rom_data   ( lvc_data      ),
    .rom_ok     ( lvc_ok        ),
    .pxl        ( lvc_pxl       ),
    .behind     ( lvc_behind    )
);

jtxexex_obj #(.SHADOW(1),.HOFFSET(OBJ_HOFFSET)) u_obj(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .ln_done    (               ),
    .pxl_cen    ( pxl_cen       ),
    .pxl2_cen   ( pxl2_cen      ),
    .simson     ( 1'b0          ),
    .hdump      ( hcnt          ),
    .vdump      ( vrender       ),
    .voffset    ( OBJ_VOFFSET   ),
    .hs         ( HS            ),
    .lvbl       ( LVBL          ),
    .ram_cs     ( obj_ram_cs    ),
    .reg_cs     ( obj_reg_cs    ),
    .mmr_we     ( cpu_we        ),
    .mmr_addr   ( { 1'b0, cpu_addr[2:1], 1'b0 } ),
    .mmr_din    ( cpu_dout      ),
    .mmr_dsn    ( cpu_dsn       ),
    .ram_din    ( cpu_dout      ),
    .ram_we     ( ~cpu_dsn & {2{cpu_we}} ),
    .ram_addr   ( cpu_addr      ),
    .cpu_din    ( obj_dout      ),
    .dma_bsy    ( dma_bsy       ),
    .rom_addr   ( obj_full      ),
    .rom_data   ( obj_data      ),
    .rom_cs     ( obj_cs        ),
    .rom_ok     ( obj_ok        ),
    .objcha_n   ( objcha_n      ),
    .shd        ( obj_shd       ),
    .prio       ( obj_pri       ),
    .pxl        ( obj_pxl       ),
    .gfx_en     ( { gfx_en[5], 3'd0 } ),
    .ioctl_ram  ( 1'b0          ),
    .ioctl_addr ( 14'd0         ),
    .dump_ram   (               ),
    .dump_reg   (               ),
    .debug_bus  ( debug_bus     )
);

jtxexex_colmix u_colmix(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .cpu_addr   ( cpu_addr[12:1]),
    .cpu_dout   ( cpu_dout      ),
    .cpu_dsn    ( cpu_dsn       ),
    .cpu_we     ( cpu_we        ),
    .pal_cs     ( pal_cs        ),
    .k251_cs    ( k251_cs       ),
    .k338_cs    ( k338_cs       ),
    .pal_dout   ( pal_dout      ),
    .alpha_off  ( alpha_off     ),
    .cb_b       ( cb_b          ),
    .cb_c       ( cb_c          ),
    .cb_d       ( cb_d          ),
    .lyra       ( lyra          ),
    .lyrb       ( lyrb          ),
    .lyrc       ( lyrc          ),
    .lyrd       ( lyrd          ),
    .lvc        ( lvc_pxl       ),
    .obj        ( obj_pxl       ),
    .obj_pri    ( obj_pri       ),
    .obj_shd    ( obj_shd       ),
    .gfx_en     ( gfx_en        ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          )
);

endmodule
