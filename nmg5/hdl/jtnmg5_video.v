/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * YS-1300 video: 8 MHz pixel clock, 512x260 total (60 Hz; 512x284 = 55 Hz for Search Eye Plus), MAME visible area 320x240 at (0,0).
 * Palette: 1024 words xBGR_555. Tilemap 0 (opaque): 0x100 + pen; tilemap 1: pen (0 transparent);
 *   sprites: 0x200 + colour * 32 + pen; pixel layer: 0x300 + pixel (0 transparent), screen (x, y) = layer (x + 12, y + 9).
 * Scroll: tilemap 0 (x + 3, y + 9), tilemap 1 (x - 1, y + 9).
 * Order over tilemap 0 by the priority register: 0 spr tm1 pix; 1 pix spr tm1; 2 spr pix tm1; 3 tm1 spr pix;
 *   7 tm1 pix spr; 4-6 nothing else. */

module jtnmg5_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input              tbig,
    input              obig,
    input              osmall,
    input              hz55,
    input       [ 1:0] gfx_bank,
    input       [ 2:0] prio,
    input       [ 8:0] scr0x, scr0y, scr1x, scr1y,

    output      [12:1] vram0_video_addr,
    input       [15:0] vram0_video_dout,
    output      [12:1] vram1_video_addr,
    input       [15:0] vram1_video_dout,
    output      [10:1] objram_video_addr,
    input       [15:0] objram_video_dout,
    output      [15:1] pix_video_addr,
    input       [15:0] pix_video_dout,
    output reg  [10:1] pal_video_addr,
    input       [15:0] pal_video_dout,

    output      [22:2] t0l_addr,
    output             t0l_cs,
    input       [31:0] t0l_data,
    input              t0l_ok,
    output      [22:2] t1l_addr,
    output             t1l_cs,
    input       [31:0] t1l_data,
    input              t1l_ok,
    output      [22:2] t0h_addr,
    output             t0h_cs,
    input       [31:0] t0h_data,
    input              t0h_ok,
    output      [22:2] t1h_addr,
    output             t1h_cs,
    input       [31:0] t1h_data,
    input              t1h_ok,
    output      [20:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,
    output      [18:0] ob5_addr,
    output             ob5_cs,
    input       [ 7:0] ob5_data,
    input              ob5_ok,

    output             vbl_irq,     // low during vblank (undelayed)
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output reg  [ 4:0] red,
    output reg  [ 4:0] green,
    output reg  [ 4:0] blue
);

localparam [8:0] HTOTAL=9'd511, HS_START=9'd400, HS_END=9'd432;
localparam [8:0] VTOTAL=9'd259, VTOTAL55=9'd283, VB_START=9'd240, VS_START=9'd246, VS_END=9'd249;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl, odd;
reg  [ 3:0] hbl_sh, vbl_sh;
wire [ 7:0] tm0_q, tm1_q;
wire [ 8:0] obj_pxl;
reg  [ 7:0] tm0, tm1;
reg  [ 3:0] pix;
reg  [ 9:0] idx;
wire [ 8:0] sx0 = scr0x + 9'd3, sy0 = scr0y + 9'd9, sx1 = scr1x - 9'd1, sy1 = scr1y + 9'd9;
wire [ 8:0] pxx = hdump + 9'd12;
wire [ 7:0] pxy = vdump[7:0] + 8'd9;

assign LHBL    = hbl_sh[2];
assign LVBL    = vbl_sh[2];
assign vbl_irq = lvbl;
assign pix_video_addr = { pxy, pxx[8:2] };

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==(hz55 ? VTOTAL55 : VTOTAL) ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender < VB_START;
        if( vrender==(hz55 ? VTOTAL55 : VTOTAL) ) odd <= ~odd;
    end
    lhbl <= hdump==HTOTAL || hdump < 9'd319;   // value for the next hdump
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[2:0], lhbl };
    vbl_sh <= { vbl_sh[2:0], lvbl };
end

jtnmg5_tile u_tm0(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .big        ( tbig             ),
    .bank       ( gfx_bank         ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scrx       ( sx0            ),
    .scry       ( sy0            ),
    .vram_addr  ( vram0_video_addr ),
    .vram_dout  ( vram0_video_dout ),
    .lo_addr    ( t0l_addr       ),
    .lo_cs      ( t0l_cs         ),
    .lo_data    ( t0l_data       ),
    .lo_ok      ( t0l_ok         ),
    .hi_addr    ( t0h_addr       ),
    .hi_cs      ( t0h_cs         ),
    .hi_data    ( t0h_data       ),
    .hi_ok      ( t0h_ok         ),
    .pxl        ( tm0_q          )
);

jtnmg5_tile u_tm1(
    .rst        ( rst              ),
    .clk        ( clk              ),
    .big        ( tbig             ),
    .bank       ( gfx_bank         ),
    .hdump      ( hdump            ),
    .vrender    ( vrender          ),
    .vdump      ( vdump            ),
    .scrx       ( sx1            ),
    .scry       ( sy1            ),
    .vram_addr  ( vram1_video_addr ),
    .vram_dout  ( vram1_video_dout ),
    .lo_addr    ( t1l_addr       ),
    .lo_cs      ( t1l_cs         ),
    .lo_data    ( t1l_data       ),
    .lo_ok      ( t1l_ok         ),
    .hi_addr    ( t1h_addr       ),
    .hi_cs      ( t1h_cs         ),
    .hi_data    ( t1h_data       ),
    .hi_ok      ( t1h_ok         ),
    .pxl        ( tm1_q          )
);

jtnmg5_obj u_obj(
    .rst        ( rst               ),
    .clk        ( clk               ),
    .pxl_cen    ( pxl_cen           ),
    .big        ( obig              ),
    .osm        ( osmall            ),
    .odd        ( odd               ),
    .hdump      ( hdump             ),
    .vrender    ( vrender           ),
    .vdump      ( vdump             ),
    .ram_addr   ( objram_video_addr ),
    .ram_dout   ( objram_video_dout ),
    .rom_addr   ( obj_addr          ),
    .rom_cs     ( obj_cs            ),
    .rom_data   ( obj_data          ),
    .rom_ok     ( obj_ok            ),
    .p5_addr    ( ob5_addr          ),
    .p5_cs      ( ob5_cs            ),
    .p5_data    ( ob5_data          ),
    .p5_ok      ( ob5_ok            ),
    .pxl        ( obj_pxl           )
);

wire       t1_on = gfx_en[1] && tm1!=0;
wire       s_on  = gfx_en[3] && obj_pxl[4:0]!=0;
wire       p_on  = gfx_en[2] && pix!=0;
wire [9:0] t1_i  = { 2'd0, tm1 };
wire [9:0] s_i   = { 1'b1, obj_pxl };
wire [9:0] p_i   = { 6'b110000, pix };

always @* begin
    idx = gfx_en[0] ? { 2'd1, tm0 } : 10'd0;
    case( prio )
        0: begin if(s_on) idx=s_i; if(t1_on) idx=t1_i; if(p_on) idx=p_i; end
        1: begin if(p_on) idx=p_i; if(s_on) idx=s_i; if(t1_on) idx=t1_i; end
        2: begin if(s_on) idx=s_i; if(p_on) idx=p_i; if(t1_on) idx=t1_i; end
        3: begin if(t1_on) idx=t1_i; if(s_on) idx=s_i; if(p_on) idx=p_i; end
        7: begin if(t1_on) idx=t1_i; if(p_on) idx=p_i; if(s_on) idx=s_i; end
        default:;
    endcase
end

always @(posedge clk) if( pxl_cen ) begin
    tm0  <= tm0_q;
    tm1  <= tm1_q;
    case( pxx[1:0] )     // pixel of the current address, whose data arrives now
        0: pix <= pix_video_dout[15:12];
        1: pix <= pix_video_dout[11: 8];
        2: pix <= pix_video_dout[ 7: 4];
        3: pix <= pix_video_dout[ 3: 0];
    endcase
    pal_video_addr <= idx;
    red      <= pal_video_dout[ 4: 0];
    green    <= pal_video_dout[ 9: 5];
    blue     <= pal_video_dout[14:10];
end

endmodule
