/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Super Qix hardware (MAME superqix.cpp): Super Qix with its i8751 MCU, the no-MCU bootleg and Perestroika Girls.
 * Header byte 0: bit 0 Perestroika Girls ROM byte shuffle, bit 1 i8751 MCU fitted.
 * On JTFRAME (Jose Tejada, jotego). Personal build. */

module jtsqix_game(
    `include "jtframe_game_ports.inc"
);

wire [ 7:0] p1, p2, system;
wire [ 8:0] vdump;
wire [ 1:0] tbank;
wire        bpage, hs_start;
wire        z80_sem, mcu_sem;
reg         shuf, mcu;

always @(posedge clk) if( header && prog_we && prog_addr[1:0]==0 ) { mcu, shuf } <= prog_data[1:0];
// e000-e0ff (sprites) is mirrored into a second RAM for the sprite engine
wire        spr_wr = ram_we && ram_addr[12:8]==0;

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
assign spr_addr   = { 2'd0, ram_addr[7:0] };
assign spr_we     = spr_wr;

// active low: up, down, left, right, button 1, button 2
assign p1     = { dip_test, LVBL, joystick1[5], joystick1[4], joystick1[0], joystick1[1], joystick1[2], joystick1[3] };
assign p2     = { z80_sem, mcu_sem, joystick2[5], joystick2[4], joystick2[0], joystick2[1], joystick2[2], joystick2[3] };
assign system = { 1'b0, dip_test, tilt, service, cab_1p[1], cab_1p[0], coin[1], coin[0] };

jtsqix_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .cen_6       ( cen_6        ),
    .cen_1p5     ( cen_1p5      ),
    .vdump       ( vdump        ),
    .hs_start    ( hs_start     ),
    .lvbl        ( LVBL         ),
    .p1          ( p1           ),
    .p2          ( p2           ),
    .system      ( system       ),
    .dsw1        ( dipsw[ 7:0]  ),
    .dsw2        ( dipsw[15:8]  ),
    .shuf        ( shuf         ),
    .mcu         ( mcu          ),
    .z80_sem     ( z80_sem      ),
    .mcu_sem     ( mcu_sem      ),
    .cen_mcu     ( cen_6        ),
    .prog_addr   ( prog_addr[11:0] ),
    .prog_data   ( prog_data    ),
    .prom_we     ( prom_we      ),
    .cpu_dout    ( cpu_dout     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .ram_addr    ( ram_addr     ),
    .ram_we      ( ram_we       ),
    .ram_dout    ( ram_dout     ),
    .pal_addr    ( pal_addr     ),
    .pal_we      ( pal_we       ),
    .pal_dout    ( pal_dout     ),
    .bmp0_addr   ( bmp0_addr    ),
    .bmp0_we     ( bmp0_we      ),
    .bmp0_dout   ( bmp0_dout    ),
    .bmp1_addr   ( bmp1_addr    ),
    .bmp1_we     ( bmp1_we      ),
    .bmp1_dout   ( bmp1_dout    ),
    .tbank       ( tbank        ),
    .bpage       ( bpage        ),
    .psg0        ( psg0         ),
    .psg1        ( psg1         )
);

jtsqix_video u_video(
    .rst             ( rst             ),
    .clk             ( clk             ),
    .pxl_cen         ( pxl_cen         ),
    .gfx_en          ( gfx_en          ),
    .tbank           ( tbank           ),
    .bpage           ( bpage           ),
    .shuf            ( shuf            ),
    .ram_video_addr  ( ram_video_addr  ),
    .ram_video_dout  ( ram_video_dout  ),
    .spr_video_addr  ( spr_video_addr  ),
    .spr_video_dout  ( spr_video_dout  ),
    .bmp0_video_addr ( bmp0_video_addr ),
    .bmp0_video_dout ( bmp0_video_dout ),
    .bmp1_video_addr ( bmp1_video_addr ),
    .bmp1_video_dout ( bmp1_video_dout ),
    .pal_video_addr  ( pal_video_addr  ),
    .pal_video_dout  ( pal_video_dout  ),
    .gfx_addr        ( gfx_addr        ),
    .gfx_cs          ( gfx_cs          ),
    .gfx_data        ( gfx_data        ),
    .gfx_ok          ( gfx_ok          ),
    .sprom_addr      ( sprom_addr      ),
    .sprom_cs        ( sprom_cs        ),
    .sprom_data      ( sprom_data      ),
    .sprom_ok        ( sprom_ok        ),
    .vdump           ( vdump           ),
    .hs_start        ( hs_start        ),
    .LHBL            ( LHBL            ),
    .LVBL            ( LVBL            ),
    .HS              ( HS              ),
    .VS              ( VS              ),
    .red             ( red             ),
    .green           ( green           ),
    .blue            ( blue            )
);

endmodule
