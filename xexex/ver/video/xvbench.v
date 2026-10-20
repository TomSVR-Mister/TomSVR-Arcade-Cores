// Video-only test bench: the C++ side writes chip state from a MAME dump and serves the ROMs
module xvbench #(parameter [9:0] OHOFF=10'd464, OVOFF=10'd33)(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,
    input      [14:1] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input             cpu_we,
    input      [ 8:0] cs,       // tmap_reg, tmap_ram, lvc_ram, lvc_reg, obj_ram, obj_reg, pal, k251, k338
    input             alpha_off,
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
    output            LHBL, LVBL, HS, VS,
    output     [ 7:0] red, green, blue,
    output            dma_bsy,
    input      [ 7:0] gfx_en
);
jtxexex_video #(.OBJ_HOFFSET(OHOFF),.OBJ_VOFFSET(OVOFF)) u_video(
    .rst(rst), .clk(clk), .pxl_cen(pxl_cen), .pxl2_cen(pxl2_cen),
    .cpu_addr(cpu_addr), .cpu_dout(cpu_dout), .cpu_dsn(cpu_dsn), .cpu_we(cpu_we),
    .tmap_reg_cs(cs[0]), .tmap_ram_cs(cs[1]), .lvc_ram_cs(cs[2]), .lvc_reg_cs(cs[3]),
    .obj_ram_cs(cs[4]), .obj_reg_cs(cs[5]), .pal_cs(cs[6]), .k251_cs(cs[7]), .k338_cs(cs[8]),
    .objcha_n(1'b1), .alpha_off(alpha_off),
    .tmap_dout(), .lvc_dout(), .lvc_reg_dout(), .obj_dout(), .pal_dout(), .dma_bsy(dma_bsy), .vb_start(),
    .tile_addr(tile_addr), .tile_cs(tile_cs), .tile_data(tile_data), .tile_ok(tile_ok),
    .lvc_addr(lvc_addr), .lvc_cs(lvc_cs), .lvc_data(lvc_data), .lvc_ok(lvc_ok),
    .obj_addr(obj_addr), .obj_cs(obj_cs), .obj_data(obj_data), .obj_ok(obj_ok),
    .LHBL(LHBL), .LVBL(LVBL), .HS(HS), .VS(VS), .red(red), .green(green), .blue(blue),
    .gfx_en(gfx_en), .debug_bus(8'd0)
);
endmodule
