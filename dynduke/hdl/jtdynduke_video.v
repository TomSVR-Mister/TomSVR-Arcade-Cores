/* SPDX-License-Identifier: GPL-3.0-or-later
   Dynamite Duke video: 6 MHz pixel clock, 384 x 262 total (59.6 Hz), MAME visible area X 0-255, Y 16-239.
   hdump/vdump are MAME screen coordinates. Tile layers render the next line (vrender) from hdump 0 into one
   half of their line buffers while the other half is shown. */

module jtdynduke_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input       [ 7:0] debug_bus,

    input       [ 7:0] ctrl,
    input       [ 7:0] bgsy_hi, bgsy_lo, bgsx_hi, bgsx_lo,
                       fgsy_hi, fgsy_lo, fgsx_hi, fgsx_lo,
    input              bg_bank, fg_bank,

    output      [10:1] txt_addr,
    input       [15:0] txt_data,
    output      [10:1] bg_addr,
    input       [15:0] bg_data,
    output      [10:1] fg_addr,
    input       [15:0] fg_data,
    output      [11:1] obj_addr,
    input       [15:0] obj_data,
    output      [11:1] pal_addr,
    input       [15:0] pal_data,

    output      [14:2] txt_rom_addr,
    output             txt_rom_cs,
    input       [31:0] txt_rom_data,
    input              txt_rom_ok,
    output      [20:2] bg_rom_addr,
    output             bg_rom_cs,
    input       [31:0] bg_rom_data,
    input              bg_rom_ok,
    output      [19:2] fg_rom_addr,
    output             fg_rom_cs,
    input       [31:0] fg_rom_data,
    input              fg_rom_ok,
    output      [20:2] spr_rom_addr,
    output             spr_rom_cs,
    input       [31:0] spr_rom_data,
    input              spr_rom_ok,

    output reg         vint,        // one clock at the start of V-blank
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output      [ 3:0] red,
    output      [ 3:0] green,
    output      [ 3:0] blue
);

localparam [8:0] HTOTAL=9'd383, HB_START=9'd256, HS_START=9'd304, HS_END=9'd336;
localparam [8:0] VTOTAL=9'd261, VB_END=9'd16, VB_START=9'd240, VS_START=9'd248, VS_END=9'd251;
parameter  [8:0] TXT_DX=9'd0, SCR_DX=9'd0, OBJ_DX=9'd0;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl, lvbl_l;
reg  [ 2:0] hbl_sh, vbl_sh;
wire [ 9:0] txt_pxl, bg_pxl, fg_pxl;
wire [10:0] obj_pxl;
reg         line_start;     // one clock after vrender moves to the next line
// MAME: ((hi & 0x30) << 4) + ((lo & 0x7f) << 1) + (lo >> 7), of which the tilemap uses 9 bits
wire [ 8:0] bgsy = { bgsy_hi[4], bgsy_lo[6:0], bgsy_lo[7] };
wire [ 8:0] bgsx = { bgsx_hi[4], bgsx_lo[6:0], bgsx_lo[7] };
wire [ 8:0] fgsy = { fgsy_hi[4], fgsy_lo[6:0], fgsy_lo[7] };
wire [ 8:0] fgsx = { fgsx_hi[4], fgsx_lo[6:0], fgsx_lo[7] };

assign LHBL = hbl_sh[1];
assign LVBL = vbl_sh[1];

always @(posedge clk) begin
    vint   <= 0;
    line_start <= pxl_cen && hdump==HTOTAL;
    lvbl_l <= lvbl;
    if( lvbl_l && !lvbl ) vint <= 1;
    if( pxl_cen ) begin
        hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
        if( hdump==HTOTAL ) begin
            vdump   <= vrender;
            vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
            lvbl    <= vrender >= VB_END && vrender < VB_START;
        end
        lhbl <= hdump==HTOTAL || hdump < HB_START-9'd1;   // value for the next hdump
        if( hdump==HS_START ) begin
            HS <= 1;
            if( vdump==VS_START ) VS <= 1;
            if( vdump==VS_END   ) VS <= 0;
        end
        if( hdump==HS_END ) HS <= 0;
        hbl_sh <= { hbl_sh[1:0], lhbl };
        vbl_sh <= { vbl_sh[1:0], lvbl };
    end
end

jtdynduke_tiles #(.LAYER(0),.RW(15)) u_txt(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .start      ( line_start    ),
    .vpos       ( vrender       ),
    .hpos       ( 9'd0          ),
    .bank       ( 1'b0          ),
    .wr_bank    ( vrender[0]    ),
    .rd_bank    ( vdump[0]      ),
    .rd_x       ( hdump + TXT_DX ),
    .vram_addr  ( txt_addr      ),
    .vram_data  ( txt_data      ),
    .rom_addr   ( txt_rom_addr  ),
    .rom_cs     ( txt_rom_cs    ),
    .rom_ok     ( txt_rom_ok    ),
    .rom_data   ( txt_rom_data  ),
    .pxl        ( txt_pxl       )
);

jtdynduke_tiles #(.LAYER(1),.RW(20)) u_fg(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .start      ( line_start    ),
    .vpos       ( vrender + fgsy ),
    .hpos       ( fgsx          ),
    .bank       ( fg_bank       ),
    .wr_bank    ( vrender[0]    ),
    .rd_bank    ( vdump[0]      ),
    .rd_x       ( hdump + SCR_DX ),
    .vram_addr  ( fg_addr       ),
    .vram_data  ( fg_data       ),
    .rom_addr   ( fg_rom_addr   ),
    .rom_cs     ( fg_rom_cs     ),
    .rom_ok     ( fg_rom_ok     ),
    .rom_data   ( fg_rom_data   ),
    .pxl        ( fg_pxl        )
);

jtdynduke_tiles #(.LAYER(2),.RW(21)) u_bg(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .start      ( line_start    ),
    .vpos       ( vrender + bgsy ),
    .hpos       ( bgsx          ),
    .bank       ( bg_bank       ),
    .wr_bank    ( vrender[0]    ),
    .rd_bank    ( vdump[0]      ),
    .rd_x       ( hdump + SCR_DX ),
    .vram_addr  ( bg_addr       ),
    .vram_data  ( bg_data       ),
    .rom_addr   ( bg_rom_addr   ),
    .rom_cs     ( bg_rom_cs     ),
    .rom_ok     ( bg_rom_ok     ),
    .rom_data   ( bg_rom_data   ),
    .pxl        ( bg_pxl        )
);

jtdynduke_obj #(.DX(OBJ_DX)) u_obj(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .hs         ( HS            ),
    .vint       ( vint          ),
    .en         ( 1'b1          ),
    .hdump      ( hdump         ),
    .vrender    ( vrender       ),
    .ram_addr   ( obj_addr      ),
    .ram_dout   ( obj_data      ),
    .rom_addr   ( spr_rom_addr  ),
    .rom_cs     ( spr_rom_cs    ),
    .rom_data   ( spr_rom_data  ),
    .rom_ok     ( spr_rom_ok    ),
    .pxl        ( obj_pxl       )
);

jtdynduke_colmix u_colmix(
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .gfx_en     ( gfx_en        ),
    .ctrl       ( ctrl          ),
    .bg         ( bg_pxl        ),
    .fg         ( fg_pxl        ),
    .txt        ( txt_pxl       ),
    .obj        ( obj_pxl       ),
    .pal_addr   ( pal_addr      ),
    .pal_data   ( pal_data      ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          )
);

endmodule
