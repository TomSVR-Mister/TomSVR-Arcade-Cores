/* SPDX-License-Identifier: GPL-3.0-or-later
   Operation Thunderbolt video: 26.686 MHz / 4 pixel clock, 424 x 262, 320 x 240 visible.
   Layer line v holds MAME line v+1, so the visible window is lines 15-254.
   The board outputs a mirrored picture because the cabinet is viewed through a mirror, so every layer
   is read out right to left. */

module jtothunder_video(
    input             rst,
    input             clk,
    output            pxl_cen,
    output            pxl2_cen,

    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    input      [23:1] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input             cpu_rnw,
    input             scn_cs, ctl_cs, pcr_cs, obj_cs,
    output     [15:0] vid_dout,

    output     [18:2] bg0_addr,
    output            bg0_cs,
    input             bg0_ok,
    input      [31:0] bg0_data,
    output     [18:2] bg1_addr,
    output            bg1_cs,
    input             bg1_ok,
    input      [31:0] bg1_data,
    output     [18:2] smap_addr,
    output            smap_cs,
    input             smap_ok,
    input      [31:0] smap_data,
    output     [20:2] orom_addr,
    output            orom_cs,
    input             orom_ok,
    input      [31:0] orom_data,

    output     [ 4:0] red,
    output     [ 4:0] green,
    output     [ 4:0] blue,

    input      [ 3:0] gfx_en
);

wire [ 8:0] hdump, vdump, vrender, rd_x;
wire [11:0] bg0_pxl, bg1_pxl, txt_pxl;
wire [12:0] obj_pxl;
wire [15:0] scn_dout, obj_dout, pcr_dout;
wire [ 3:0] layer_ctl;
reg  [ 8:0] vr_l;
reg         obj_start;

// two pixels of pipeline between the layer read and the colour output; offsets checked against MAME
assign rd_x     = 9'd318 - hdump;
assign vid_dout = (scn_cs | ctl_cs) ? scn_dout : obj_cs ? obj_dout : pcr_dout;

always @(posedge clk) begin
    vr_l      <= vrender;
    obj_start <= vr_l != vrender;
end

jtframe_frac_cen #(.W(2)) u_cen(
    .clk    ( clk               ),
    .n      ( 10'd1             ),
    .m      ( 10'd4             ),
    .cen    ({pxl_cen,pxl2_cen} ),
    .cenb   (                   )
);

jtframe_vtimer #(
    .HCNT_START ( 9'd0      ),
    .HCNT_END   ( 9'd423    ),
    .HB_START   ( 9'd320    ),
    .HB_END     ( 9'd0      ),
    .HS_START   ( 9'd352    ),
    .HS_END     ( 9'd384    ),
    .V_START    ( 9'd0      ),
    .VCNT_END   ( 9'd261    ),
    .VB_START   ( 9'd255    ),
    .VB_END     ( 9'd15     ),
    .VS_START   ( 9'd258    ),
    .VS_END     ( 9'd261    )
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   (           ),
    .H          ( hdump     ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( lhbl      ),
    .LVBL       ( lvbl      ),
    .HS         ( hs        ),
    .VS         ( vs        )
);

jtothunder_scn u_scn(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .vrender    ( vrender   ),
    .vdump      ( vdump     ),
    .rd_x       ( rd_x      ),
    .cpu_addr   ( cpu_addr[15:1] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_rnw    ( cpu_rnw   ),
    .ram_cs     ( scn_cs    ),
    .ctl_cs     ( ctl_cs    ),
    .cpu_din    ( scn_dout  ),
    .bg0_addr   ( bg0_addr  ),
    .bg0_cs     ( bg0_cs    ),
    .bg0_ok     ( bg0_ok    ),
    .bg0_data   ( bg0_data  ),
    .bg1_addr   ( bg1_addr  ),
    .bg1_cs     ( bg1_cs    ),
    .bg1_ok     ( bg1_ok    ),
    .bg1_data   ( bg1_data  ),
    .bg0_pxl    ( bg0_pxl   ),
    .bg1_pxl    ( bg1_pxl   ),
    .txt_pxl    ( txt_pxl   ),
    .layer_ctl  ( layer_ctl )
);

jtothunder_obj u_obj(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .start      ( obj_start ),
    .vrender    ( vrender   ),
    .wr_bank    ( vrender[0]),
    .rd_bank    ( vdump[0]  ),
    .rd_x       ( rd_x      ),
    .pxl_cen    ( pxl_cen   ),
    .cpu_addr   ( cpu_addr[10:1] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_rnw    ( cpu_rnw   ),
    .obj_cs     ( obj_cs    ),
    .cpu_din    ( obj_dout  ),
    .map_addr   ( smap_addr ),
    .map_cs     ( smap_cs   ),
    .map_ok     ( smap_ok   ),
    .map_data   ( smap_data ),
    .rom_addr   ( orom_addr ),
    .rom_cs     ( orom_cs   ),
    .rom_ok     ( orom_ok   ),
    .rom_data   ( orom_data ),
    .pxl        ( obj_pxl   )
);

jtothunder_colmix u_colmix(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .cpu_addr   ( cpu_addr[2:1] ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_rnw    ( cpu_rnw   ),
    .pcr_cs     ( pcr_cs    ),
    .cpu_din    ( pcr_dout  ),
    .layer_ctl  ( layer_ctl ),
    .bg0        ( bg0_pxl   ),
    .bg1        ( bg1_pxl   ),
    .txt        ( txt_pxl   ),
    .obj        ( obj_pxl   ),
    .gfx_en     ( gfx_en    ),
    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      )
);

endmodule
