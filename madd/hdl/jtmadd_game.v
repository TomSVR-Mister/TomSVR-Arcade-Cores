/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Promat / Tuning VISYS board (Mad Donna, Komo Como) on JTFRAME (Jose Tejada, jotego). Personal build.
 * Header byte 0 bit 0: Komo Como layer order (bg, mid, fg) instead of Mad Donna's (mid, fg, bg). */

module jtmadd_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] scroll1;
wire [ 7:0] p1, p2, credits, snd_latch;
wire        snd_wr, vbl_irq;
wire [ 7:0] snd_dout;
reg         order = 0;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
always @(posedge clk) if( header && prog_we && prog_addr[1:0]==0 ) order <= prog_data[0];

`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

// active high: up, down, left, right, button 1, button 2
assign p1 = { 2'b00, ~joystick1[5], ~joystick1[4], ~joystick1[0], ~joystick1[1], ~joystick1[2], ~joystick1[3] };
assign p2 = { 2'b00, ~joystick2[5], ~joystick2[4], ~joystick2[0], ~joystick2[1], ~joystick2[2], ~joystick2[3] };
// coin 1 bit 3, coin 2 bit 4, start 1 bit 5, start 2 bit 6
assign credits = { 1'b0, ~cab_1p[1], ~cab_1p[0], ~coin[1], ~coin[0], 3'b000 };

jtmadd_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .lvbl        ( vbl_irq      ),
    .dip_pause   ( dip_pause    ),
    .p1          ( p1           ),
    .p2          ( p2           ),
    .credits     ( credits      ),
    .dipsw       ( dipsw[15:0]  ),
    .cpu_dout    ( cpu_dout     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .wram_addr   ( wram_addr    ),
    .wram_we     ( wram_we      ),
    .wram_dout   ( wram_dout    ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .objram_addr ( objram_addr  ),
    .objram_we   ( objram_we    ),
    .objram_dout ( objram_dout  ),
    .vmid_addr   ( vmid_addr    ),
    .vmid_we     ( vmid_we      ),
    .vmid_dout   ( vmid_dout    ),
    .vfg_addr    ( vfg_addr     ),
    .vfg_we      ( vfg_we       ),
    .vfg_dout    ( vfg_dout     ),
    .vbg_addr    ( vbg_addr     ),
    .vbg_we      ( vbg_we       ),
    .vbg_dout    ( vbg_dout     ),
    .scroll1     ( scroll1      ),
    .snd_latch   ( snd_latch    ),
    .snd_wr      ( snd_wr       )
);

jtmadd_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen_snd    ( cen_snd       ),
    .main_dout  ( cpu_dout[7:0] ),
    .snd_wr     ( snd_wr        ),
    .latch      ( snd_latch     ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .fm         ( fm            )
);

jtmadd_video u_video(
    .rst                ( rst               ),
    .clk                ( clk               ),
    .pxl_cen            ( pxl_cen           ),
    .gfx_en             ( gfx_en            ),
    .order              ( order             ),
    .scroll1            ( scroll1           ),
    .vbg_video_addr     ( vbg_video_addr    ),
    .vbg_video_dout     ( vbg_video_dout    ),
    .vmid_video_addr    ( vmid_video_addr   ),
    .vmid_video_dout    ( vmid_video_dout   ),
    .vfg_video_addr     ( vfg_video_addr    ),
    .vfg_video_dout     ( vfg_video_dout    ),
    .objram_video_addr  ( objram_video_addr ),
    .objram_video_dout  ( objram_video_dout ),
    .pal_video_addr     ( pal_video_addr    ),
    .pal_video_dout     ( pal_video_dout    ),
    .bgt_addr           ( bgt_addr          ),
    .bgt_cs             ( bgt_cs            ),
    .bgt_data           ( bgt_data          ),
    .bgt_ok             ( bgt_ok            ),
    .mgt_addr           ( mgt_addr          ),
    .mgt_cs             ( mgt_cs            ),
    .mgt_data           ( mgt_data          ),
    .mgt_ok             ( mgt_ok            ),
    .fgt_addr           ( fgt_addr          ),
    .fgt_cs             ( fgt_cs            ),
    .fgt_data           ( fgt_data          ),
    .fgt_ok             ( fgt_ok            ),
    .obj_addr           ( obj_addr          ),
    .obj_cs             ( obj_cs            ),
    .obj_data           ( obj_data          ),
    .obj_ok             ( obj_ok            ),
    .vbl_irq            ( vbl_irq           ),
    .LHBL               ( LHBL              ),
    .LVBL               ( LVBL              ),
    .HS                 ( HS                ),
    .VS                 ( VS                ),
    .red                ( red               ),
    .green              ( green             ),
    .blue               ( blue              )
);

endmodule
