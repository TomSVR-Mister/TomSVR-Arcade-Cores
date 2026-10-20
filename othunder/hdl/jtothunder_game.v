/* SPDX-License-Identifier: GPL-3.0-or-later
   JTOTHUNDER: Taito Operation Thunderbolt (1988), from MAME othunder.cpp. Built on JTFRAME, jotego's
   68000/Z80 wrappers, jt10 (YM2610) and the TC0140SYT model from jotego's Taito X core */

module jtothunder_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire [23:1] cpu_addr;
wire [ 1:0] cpu_dsn;
wire        cpu_rnw, cpu_cen, scn_cs, ctl_cs, pcr_cs, obj_cs, syt_cs;
wire [15:0] vid_dout;
wire [ 3:0] syt_dout;
wire [ 7:0] st_main, eep_dout;
reg  [ 7:0] adc_x1, adc_y1, adc_x2, adc_y2;
wire        eep_we = prom_we;   // the PROM area only holds the 128-byte EEPROM image

assign dip_flip   = 0;
assign debug_view = st_main;
assign ioctl_din  = eep_dout;

// guns: the ADC reads the native (unmirrored) X, MAME crosshair Y offset -0.057
function [7:0] gun_x( input [8:0] gx );
    reg [17:0] m;
    begin
        m     = (9'd319 - (gx > 9'd319 ? 9'd319 : gx)) * 9'd205;
        gun_x = m[15:8];
    end
endfunction

function [7:0] gun_y( input [8:0] gy );
    reg [12:0] m;
    begin
        m     = {gy, 4'd0} + {4'd0, gy} + 13'd240;   // y*17/16 + 15
        gun_y = m[12:4] > 9'd255 ? 8'hff : m[11:4];
    end
endfunction

always @(posedge clk) begin
    adc_x1 <= gun_x( gun_1p_x );
    adc_y1 <= gun_y( gun_1p_y );
    adc_x2 <= gun_x( gun_2p_x );
    adc_y2 <= gun_y( gun_2p_y );
end

jtothunder_main u_main(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .LVBL       ( LVBL          ),
    .cpu_cen    ( cpu_cen       ),
    .cpu_addr   ( cpu_addr      ),
    .cpu_dout   ( cpu_dout      ),
    .cpu_rnw    ( cpu_rnw       ),
    .cpu_dsn    ( cpu_dsn       ),
    .rom_cs     ( main_cs       ),
    .rom_addr   ( main_addr     ),
    .rom_data   ( main_data     ),
    .rom_ok     ( main_ok       ),
    .ram_we     ( ram_we        ),
    .ram_dout   ( ram_dout      ),
    .scn_cs     ( scn_cs        ),
    .ctl_cs     ( ctl_cs        ),
    .pcr_cs     ( pcr_cs        ),
    .obj_cs     ( obj_cs        ),
    .vid_dout   ( vid_dout      ),
    .syt_cs     ( syt_cs        ),
    .syt_dout   ( syt_dout      ),
    .joystick1  ( joystick1[5:0]),
    .joystick2  ( joystick2[5:0]),
    .cab_1p     ( cab_1p[1:0]   ),
    .coin       ( coin[1:0]     ),
    .service    ( service       ),
    .dip_pause  ( dip_pause     ),
    .dipsw      ( dipsw[15:0]   ),
    .adc0       ( adc_x1        ),
    .adc1       ( adc_y1        ),
    .adc2       ( adc_x2        ),
    .adc3       ( adc_y2        ),
    .prog_addr  ( ioctl_ram ? ioctl_addr[6:0] : prog_addr[6:0] ),
    .prog_data  ( ioctl_ram ? ioctl_dout : prog_data ),
    .prog_we    ( ioctl_ram ? ioctl_wr : eep_we ),
    .prog_din   ( eep_dout      ),
    .st_dout    ( st_main       )
);

jtothunder_snd u_snd(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen8       ( cen8          ),
    .snd_cen    ( snd_cen       ),
    .main_cen   ( cpu_cen       ),
    .syt_cs     ( syt_cs        ),
    .main_addr  ( cpu_addr[1]   ),
    .main_dout  ( cpu_dout[3:0] ),
    .main_din   ( syt_dout      ),
    .main_rnw   ( cpu_rnw       ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_ok     ( snd_ok        ),
    .rom_data   ( snd_data      ),
    .adpcma_addr( adpcma_addr   ),
    .adpcma_cs  ( adpcma_cs     ),
    .adpcma_data( adpcma_data   ),
    .adpcmb_addr( adpcmb_addr   ),
    .adpcmb_cs  ( adpcmb_cs     ),
    .adpcmb_data( adpcmb_data   ),
    .sup_l      ( sup_l         ),
    .sup_r      ( sup_r         ),
    .psg        ( psg           )
);

jtothunder_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .pxl2_cen   ( pxl2_cen      ),
    .lhbl       ( LHBL          ),
    .lvbl       ( LVBL          ),
    .hs         ( HS            ),
    .vs         ( VS            ),
    .cpu_addr   ( cpu_addr      ),
    .cpu_dout   ( cpu_dout      ),
    .cpu_dsn    ( cpu_dsn       ),
    .cpu_rnw    ( cpu_rnw       ),
    .scn_cs     ( scn_cs        ),
    .ctl_cs     ( ctl_cs        ),
    .pcr_cs     ( pcr_cs        ),
    .obj_cs     ( obj_cs        ),
    .vid_dout   ( vid_dout      ),
    .bg0_addr   ( bg0_addr      ),
    .bg0_cs     ( bg0_cs        ),
    .bg0_ok     ( bg0_ok        ),
    .bg0_data   ( bg0_data      ),
    .bg1_addr   ( bg1_addr      ),
    .bg1_cs     ( bg1_cs        ),
    .bg1_ok     ( bg1_ok        ),
    .bg1_data   ( bg1_data      ),
    .smap_addr  ( smap_addr     ),
    .smap_cs    ( smap_cs       ),
    .smap_ok    ( smap_ok       ),
    .smap_data  ( smap_data     ),
    .orom_addr  ( orom_addr     ),
    .orom_cs    ( orom_cs       ),
    .orom_ok    ( orom_ok       ),
    .orom_data  ( orom_data     ),
    .orom2_addr ( orom2_addr    ),
    .orom2_cs   ( orom2_cs      ),
    .orom2_ok   ( orom2_ok      ),
    .orom2_data ( orom2_data    ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          ),
    .gfx_en     ( gfx_en        )
);

endmodule
