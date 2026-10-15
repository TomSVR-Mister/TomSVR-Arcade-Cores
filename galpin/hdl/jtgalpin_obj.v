/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 2-1-2025
 * Based on jtgaiden_obj.v (jotego). Gals Pinball: 10-bit line buffer for the 512-pixel screen (2026 Tom Sveen) */

module jtgalpin_obj(
    input               rst,
    input               clk,
    input               pxl_cen,
    input               flip,
    input               lvbl,
    input               hs,
    input               frame,
    input        [ 9:0] hdump,
    input        [ 8:0] vrender,
    input        [ 8:0] yoffset,
    input        [ 3:0] hoffset,

    output       [11:1] ram_addr,
    input        [15:0] ram_dout,

    output              rom_cs,
    output       [17:2] rom_addr,
    input        [31:0] rom_data,
    input               rom_ok,

    output       [ 8:0] pxl         // {prio, pal, pen}
);

localparam       PXLW=11,CW=13;

wire   [CW+6:2] raw_addr;
wire   [19:2]   full_addr;
wire [PXLW-1:0] pre_pxl;
reg  [PXLW-1:0] dly[0:15];
wire          hflip, vflip, dr_draw, dr_busy, prio;
wire   [ 9:0] hpos;
wire   [12:0] code;
wire   [31:0] sorted;
wire   [ 3:0] pal;
wire   [ 3:0] ysub;
wire   [ 6:0] attr;
integer       i;

assign attr     = {2'd0,prio,pal};
assign rom_addr = full_addr[17:2];
assign pxl      = dly[hoffset][8:0];

jtframe_8x8x4_packed_msb u_conv(
    .raw    ( rom_data  ),
    .sorted ( sorted    )
);

jtgalpin_objscan u_scan(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .flip       ( flip      ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),
    .frame      ( frame     ),
    .vrender    ( vrender   ),
    .yoffset    ( yoffset   ),

    .ram_addr   ( ram_addr  ),
    .ram_dout   ( ram_dout  ),
    .raw_addr   ( raw_addr  ),
    .rom_addr   ( full_addr ),
    .hflip      ( hflip     ),
    .vflip      ( vflip     ),
    .ysub       ( ysub      ),
    .code       ( code      ),
    .pal        ( pal       ),
    .prio       ( prio      ),
    .hpos       ( hpos      ),
    .dr_draw    ( dr_draw   ),
    .dr_busy    ( dr_busy   )
);

jtframe_objdraw #(.AW(10),.CW(CW),.PW(PXLW),.LATCH(1),.HFIX(0)) u_draw(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .hs         ( hs        ),
    .flip       ( flip      ),
    .hdump      ( hdump     ),

    .draw       ( dr_draw   ),
    .busy       ( dr_busy   ),
    .code       ( code      ),
    .xpos       ( hpos      ),
    .ysub       ( ysub      ),
    .hzoom      ( 6'd0      ),
    .hz_keep    ( 1'b0      ),

    .hflip      ( hflip     ),
    .vflip      ( vflip     ),
    .pal        ( attr      ),

    .rom_addr   ( raw_addr  ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    ),
    .rom_data   ( sorted    ),

    .pxl        ( pre_pxl   )
);

// adjustable pixel delay (set from the video module)
always @(posedge clk) if(pxl_cen) begin
    dly[0] <= pre_pxl;
    for(i=1;i<16;i=i+1) dly[i] <= dly[i-1];
end

endmodule
