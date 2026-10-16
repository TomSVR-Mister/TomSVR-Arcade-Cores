/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Paradise video: 6 MHz pixel clock, 384x289 total (54 Hz), 256x224 visible (MAME rows 16-239) */

module jtpara_video(
    input              rst,
    input              clk,
    input              pxl_cen,
    input       [ 3:0] gfx_en,
    input              flip,
    input       [ 7:0] prio,
    input       [ 3:0] bg_bank, pix_bank,
    input       [ 1:0] mode,         // 0 Paradise, 1 Torus, 2 Mad Ball
    input              inc4, many, tlay, spr1m, fg1m,

    output      [10:0] vram0_video_addr, vram1_video_addr, vram2_video_addr,
    input       [ 7:0] vram0_video_dout, vram1_video_dout, vram2_video_dout,
    output      [10:0] objram_video_addr,
    input       [ 7:0] objram_video_dout,
    output      [14:0] pix_video_addr,
    input       [ 7:0] pix_video_dout,
    output      [10:0] pal_video_addr,
    input       [ 7:0] palr_video_dout, palg_video_dout, palb_video_dout,

    output      [17:2] bgt_addr,
    output             bgt_cs,
    input       [31:0] bgt_data,
    input              bgt_ok,
    output      [19:2] fgt_addr,
    output             fgt_cs,
    input       [31:0] fgt_data,
    input              fgt_ok,
    output      [19:2] mgt_addr,
    output             mgt_cs,
    input       [31:0] mgt_data,
    input              mgt_ok,
    output      [19:2] obj_addr,
    output             obj_cs,
    input       [31:0] obj_data,
    input              obj_ok,

    output reg         irq,
    output             lvbl_raw,
    output             LHBL,
    output             LVBL,
    output reg         HS,
    output reg         VS,
    output      [ 7:0] red,
    output      [ 7:0] green,
    output      [ 7:0] blue
);

localparam [8:0] HTOTAL=9'd383, HS_START=9'd300, HS_END=9'd328;
localparam [8:0] VTOTAL=9'd288, VB_END=9'd16, VB_START=9'd240, VS_START=9'd256, VS_END=9'd259;

reg  [ 8:0] hdump=0, vdump=0, vrender=1;
reg         lhbl, lvbl, pix_x0;
reg  [ 2:0] hbl_sh, vbl_sh;
reg  [ 8:0] irq_cnt=0;
wire [ 7:0] bg, mid, fg, obj;
wire [ 7:0] rd_h = flip ? ~hdump[7:0] : hdump[7:0];
wire [ 7:0] rd_v = flip ? ~vdump[7:0] : vdump[7:0];

assign LHBL     = hbl_sh[1];
assign LVBL     = vbl_sh[1];
assign lvbl_raw = lvbl;
assign pix_video_addr = { rd_v, rd_h[7:1] };

always @(posedge clk) pix_x0 <= rd_h[0];

always @(posedge clk) if( pxl_cen ) begin
    hdump <= hdump==HTOTAL ? 9'd0 : hdump+9'd1;
    if( hdump==HTOTAL ) begin
        vdump   <= vrender;
        vrender <= vrender==VTOTAL ? 9'd0 : vrender+9'd1;
        lvbl    <= vrender >= VB_END && vrender < VB_START;
    end
    lhbl <= hdump < 9'd255 || hdump==HTOTAL;
    if( hdump==HS_START ) begin
        HS <= 1;
        if( vdump==VS_START ) VS <= 1;
        if( vdump==VS_END   ) VS <= 0;
    end
    if( hdump==HS_END ) HS <= 0;
    hbl_sh <= { hbl_sh[1:0], lhbl };
    vbl_sh <= { vbl_sh[1:0], lvbl };
end

// 4 interrupts per frame (MAME: 4*54 Hz), the first 300 are not generated
always @(posedge clk) begin
    irq <= 0;
    if( rst ) irq_cnt <= 0;
    else if( pxl_cen && hdump==0 && (vdump==0 || vdump==72 || vdump==144 || vdump==216) ) begin
        if( irq_cnt < 300 ) irq_cnt <= irq_cnt + 1'd1;
        else irq <= 1;
    end
end

jtpara_tile #(.B8(0),.AW(18)) u_bg(
    .rst(rst), .clk(clk), .flip(flip), .hdump(hdump), .vrender(vrender), .vdump(vdump), .hsize(18'h3ffff),
    .vram_addr(vram0_video_addr), .vram_dout(vram0_video_dout),
    .rom_addr(bgt_addr), .rom_cs(bgt_cs), .rom_data(bgt_data), .rom_ok(bgt_ok), .pxl(bg) );

jtpara_tile #(.B8(1),.AW(20),.HALF(20'h80000)) u_mid(
    .rst(rst), .clk(clk), .flip(flip), .hdump(hdump), .vrender(vrender), .vdump(vdump), .hsize(20'h7ffff),
    .vram_addr(vram1_video_addr), .vram_dout(vram1_video_dout),
    .rom_addr(mgt_addr), .rom_cs(mgt_cs), .rom_data(mgt_data), .rom_ok(mgt_ok), .pxl(mid) );

jtpara_tile #(.B8(1),.AW(20),.HALF(20'h80000)) u_fg(
    .rst(rst), .clk(clk), .flip(flip), .hdump(hdump), .vrender(vrender), .vdump(vdump), .hsize(fg1m ? 20'h7ffff : 20'h1ffff),
    .vram_addr(vram2_video_addr), .vram_dout(vram2_video_dout),
    .rom_addr(fgt_addr), .rom_cs(fgt_cs), .rom_data(fgt_data), .rom_ok(fgt_ok), .pxl(fg) );

jtpara_obj u_obj(
    .rst(rst), .clk(clk), .flip(flip), .hdump(hdump), .vrender(vrender), .vdump(vdump),
    .inc4(inc4), .many(many), .tlay(tlay), .spr1m(spr1m),
    .ram_addr(objram_video_addr), .ram_dout(objram_video_dout),
    .rom_addr(obj_addr), .rom_cs(obj_cs), .rom_data(obj_data), .rom_ok(obj_ok), .pxl(obj) );

jtpara_colmix u_colmix(
    .clk        ( clk            ),
    .pxl_cen    ( pxl_cen        ),
    .gfx_en     ( gfx_en         ),
    .prio       ( prio           ),
    .mode       ( mode           ),
    .bg_bank    ( bg_bank        ),
    .pix_bank   ( pix_bank       ),
    .bg         ( bg             ),
    .mid        ( mid            ),
    .fg         ( fg             ),
    .obj        ( obj            ),
    .pix        ( pix_x0 ? pix_video_dout[3:0] : pix_video_dout[7:4] ),
    .pal_addr   ( pal_video_addr ),
    .palr       ( palr_video_dout),
    .palg       ( palg_video_dout),
    .palb       ( palb_video_dout),
    .red        ( red            ),
    .green      ( green          ),
    .blue       ( blue           )
);

endmodule
