/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Pipe Dream / Hatris (Video System, 1990; MAME vsystem/pipedrm.cpp) on JTFRAME (Jose Tejada, jotego).
 * Sprite chip and GGA timing from Andrea Bogazzi's jtpspike (jotego/jtcores, GPL-3). Personal build.
 * Header byte 0 bit 0: Hatris board (no sprites, YM2608, port 21 = video control only). */
module jtpipedrm_game(
    `include "jtframe_game_ports.inc"
);

wire [ 7:0] snd_latch, sys, p1, p2;
wire [15:0] cpu_addr;
wire [ 8:0] scrx0, scry0, scrx1, scry1;
wire        snd_wr, snd_pending, flip, gga_we, crtc_irq_en;
reg         hatris = 0;
`ifdef HATRIS
initial hatris = 1;    // simulation without a ROM download: the header is not seen
`endif
wire [ 1:0] pcen;

assign dip_flip   = flip;
assign debug_view = { 7'd0, hatris };

// 14.318181 MHz from the 48 MHz clock (105/352 is exact to 1e-11), and half of it for the 7.159 MHz pixel
jtframe_frac_cen #(.W(2),.WC(10)) u_pxl(
    .clk    ( clk           ),
    .n      ( 10'd105       ),
    .m      ( 10'd352       ),
    .cen    ( pcen          ),
    .cenb   (               )
);
assign pxl2_cen = pcen[0];
assign pxl_cen  = pcen[1];

always @(posedge clk) if( header && prog_we && prog_addr[2:0]==0 ) hatris <= prog_data[0];

// MAME: P1/P2 up, down, left, right, button 1, button 2 (hatris also button 3), active low
// SYSTEM: coin 1, coin 2, start 1, start 2, -, -, service, -
assign p1  = { 1'b1, joystick1[6], joystick1[5], joystick1[4], joystick1[0], joystick1[1], joystick1[2], joystick1[3] };
assign p2  = { 1'b1, joystick2[6], joystick2[5], joystick2[4], joystick2[0], joystick2[1], joystick2[2], joystick2[3] };
assign sys = { 1'b1, service, 2'b11, cab_1p[1], cab_1p[0], coin[1], coin[0] };

assign vram0_addr = { cpu_addr[13:12]-2'd1, cpu_addr[11:0] };
assign vram1_addr = vram0_addr;
assign pall_addr  = cpu_addr[11:1];
assign palh_addr  = cpu_addr[11:1];
assign objl_addr  = cpu_addr[9:1];
assign objh_addr  = cpu_addr[9:1];

jtpipedrm_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .cen         ( cen_main     ),
    .lvbl        ( LVBL         ),
    .dip_pause   ( dip_pause    ),
    .hatris      ( hatris       ),
    .sys         ( sys          ),
    .p1          ( p1           ),
    .p2          ( p2           ),
    .dsw1        ( dipsw[ 7:0]  ),
    .dsw2        ( dipsw[15:8]  ),
    .cpu_dout    ( cpu_dout     ),
    .cpu_addr    ( cpu_addr     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .vram0_we    ( vram0_we     ),
    .vram1_we    ( vram1_we     ),
    .pall_we     ( pall_we      ),
    .palh_we     ( palh_we      ),
    .objl_we     ( objl_we      ),
    .objh_we     ( objh_we      ),
    .vram0_dout  ( vram0_dout   ),
    .vram1_dout  ( vram1_dout   ),
    .pall_dout   ( pall_dout    ),
    .palh_dout   ( palh_dout    ),
    .gga_we      ( gga_we       ),
    .flip        ( flip         ),
    .scrx0       ( scrx0        ),
    .scry0       ( scry0        ),
    .scrx1       ( scrx1        ),
    .scry1       ( scry1        ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       ),
    .snd_pending ( snd_pending  )
);

jtpipedrm_snd u_snd(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .cen         ( cen_snd      ),
    .fm_cen      ( fm_cen       ),
    .hatris      ( hatris       ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       ),
    .snd_pending ( snd_pending  ),
    .lvbl        ( LVBL         ),
    .crtc_irq_en ( crtc_irq_en  ),
    .rom_addr    ( snd_addr     ),
    .rom_cs      ( snd_cs       ),
    .rom_data    ( snd_data     ),
    .rom_ok      ( snd_ok       ),
    .pcma_addr   ( pcma_addr    ),
    .pcma_cs     ( pcma_cs      ),
    .pcma_data   ( pcma_data    ),
    .pcmb_addr   ( pcmb_addr    ),
    .pcmb_cs     ( pcmb_cs      ),
    .pcmb_data   ( pcmb_data    ),
    .fm          ( fm           ),
    .psg         ( psg          )
);

jtpipedrm_video u_video(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .pxl_cen     ( pxl_cen      ),
    .hatris      ( hatris       ),
    .gga_we      ( gga_we       ),
    .gga_addr    ( cpu_addr[0]  ),
    .gga_din     ( cpu_dout     ),
    .crtc_irq_en ( crtc_irq_en  ),
    .flip        ( flip         ),
    .scrx0       ( scrx0        ),
    .scry0       ( scry0        ),
    .scrx1       ( scrx1        ),
    .scry1       ( scry1        ),
    .v0_addr     ( v0_addr      ),
    .v0_dout     ( v0_dout      ),
    .v1_addr     ( v1_addr      ),
    .v1_dout     ( v1_dout      ),
    .pl_addr     ( pl_addr      ),
    .pl_dout     ( pl_dout      ),
    .ph_addr     ( ph_addr      ),
    .ph_dout     ( ph_dout      ),
    .ol_addr     ( ol_addr      ),
    .ol_dout     ( ol_dout      ),
    .oh_addr     ( oh_addr      ),
    .oh_dout     ( oh_dout      ),
    .scr0_addr   ( scr0_addr    ),
    .scr0_cs     ( scr0_cs      ),
    .scr0_data   ( scr0_data    ),
    .scr0_ok     ( scr0_ok      ),
    .scr1_addr   ( scr1_addr    ),
    .scr1_cs     ( scr1_cs      ),
    .scr1_data   ( scr1_data    ),
    .scr1_ok     ( scr1_ok      ),
    .obj_addr    ( obj_addr     ),
    .obj_cs      ( obj_cs       ),
    .obj_data    ( obj_data     ),
    .obj_ok      ( obj_ok       ),
    .gfx_en      ( gfx_en       ),
    .LHBL        ( LHBL         ),
    .LVBL        ( LVBL         ),
    .HS          ( HS           ),
    .VS          ( VS           ),
    .red         ( red          ),
    .green       ( green        ),
    .blue        ( blue         )
);

endmodule
