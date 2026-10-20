/* SPDX-License-Identifier: GPL-3.0-or-later
   Seibu Dynamite Duke / The Double Dynamites (MAME dynduke.cpp) on JTFRAME (Jose Tejada, jotego). Personal build.
   Two V30 CPUs (the V30 model comes from the MiSTer Irem M72 core by Martin Donlon, GPL-2, see hdl/v30),
   Seibu sound (Z80 with SEI80BU decryption, YM3812, OKI 6295).
   Header byte 0: bit 0 The Double Dynamites (Japan) I/O map. */

module jtdynduke_game(
    `include "jtframe_game_ports.inc"
);

wire [10:1] txt_addr, bg_addr, fg_addr;
wire [11:1] obj_addr, pal_addr, sh_addr;
wire [15:0] txt_data, bg_data, fg_data, obj_data, pal_data, sh_dout, sh_din;
wire [ 1:0] sh_we;
wire [ 2:0] main_snd_addr;
wire [ 7:0] main_snd_dout, main_snd_din, ctrl;
wire [ 7:0] bgsy_hi, bgsy_lo, bgsx_hi, bgsx_lo, fgsy_hi, fgsy_lo, fgsx_hi, fgsx_lo;
wire        main_snd_we, bg_bank, fg_bank, vint;
reg         dbldynj = 0;

assign dip_flip   = 1'b0;
assign debug_view = { 6'd0, bg_bank, fg_bank };
always @(posedge clk) if( header && prog_we && prog_addr[1:0]==0 ) dbldynj <= prog_data[0];

`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

jtdynduke_main u_main(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .dbldynj    ( dbldynj       ),
    .vint       ( vint          ),
    .rom_addr   ( main_addr     ),
    .rom_cs     ( main_cs       ),
    .rom_data   ( main_data     ),
    .rom_ok     ( main_ok       ),
    .sh_addr    ( sh_addr       ),
    .sh_din     ( sh_din        ),
    .sh_we      ( sh_we         ),
    .sh_dout    ( sh_dout       ),
    .snd_addr   ( main_snd_addr ),
    .snd_dout   ( main_snd_dout ),
    .snd_we     ( main_snd_we   ),
    .snd_din    ( main_snd_din  ),
    .txt_addr   ( txt_addr      ),
    .txt_data   ( txt_data      ),
    .obj_addr   ( obj_addr      ),
    .obj_data   ( obj_data      ),
    .ctrl       ( ctrl          ),
    .bgsy_hi    ( bgsy_hi       ),
    .bgsy_lo    ( bgsy_lo       ),
    .bgsx_hi    ( bgsx_hi       ),
    .bgsx_lo    ( bgsx_lo       ),
    .fgsy_hi    ( fgsy_hi       ),
    .fgsy_lo    ( fgsy_lo       ),
    .fgsx_hi    ( fgsx_hi       ),
    .fgsx_lo    ( fgsx_lo       ),
    .joystick1  ( joystick1     ),
    .joystick2  ( joystick2     ),
    .cab_1p     ( cab_1p[1:0]   ),
    .dipsw      ( dipsw[15:0]   ),
    .dip_pause  ( dip_pause     )
);

jtdynduke_sub u_sub(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .vint       ( vint          ),
    .rom_addr   ( sub_addr      ),
    .rom_cs     ( sub_cs        ),
    .rom_data   ( sub_data      ),
    .rom_ok     ( sub_ok        ),
    .sh_addr    ( sh_addr       ),
    .sh_dout    ( sh_din        ),
    .sh_we      ( sh_we         ),
    .sh_din     ( sh_dout       ),
    .bg_addr    ( bg_addr       ),
    .bg_data    ( bg_data       ),
    .fg_addr    ( fg_addr       ),
    .fg_data    ( fg_data       ),
    .pal_addr   ( pal_addr      ),
    .pal_data   ( pal_data      ),
    .bg_bank    ( bg_bank       ),
    .fg_bank    ( fg_bank       ),
    .dip_pause  ( dip_pause     )
);

jtdynduke_sound u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .fm_cen     ( fm_cen        ),
    .oki_cen    ( oki_cen       ),
    .coin       ( coin[1:0]     ),
    .main_addr  ( main_snd_addr ),
    .main_dout  ( main_snd_dout ),
    .main_we    ( main_snd_we   ),
    .main_din   ( main_snd_din  ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .pcm_addr   ( adpcm_addr    ),
    .pcm_cs     ( adpcm_cs      ),
    .pcm_data   ( adpcm_data    ),
    .pcm_ok     ( adpcm_ok      ),
    .fm         ( fm            ),
    .pcm        ( pcm           )
);

jtdynduke_video u_video(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .pxl_cen        ( pxl_cen       ),
    .gfx_en         ( gfx_en        ),
    .debug_bus      ( debug_bus     ),
    .ctrl           ( ctrl          ),
    .bgsy_hi        ( bgsy_hi       ),
    .bgsy_lo        ( bgsy_lo       ),
    .bgsx_hi        ( bgsx_hi       ),
    .bgsx_lo        ( bgsx_lo       ),
    .fgsy_hi        ( fgsy_hi       ),
    .fgsy_lo        ( fgsy_lo       ),
    .fgsx_hi        ( fgsx_hi       ),
    .fgsx_lo        ( fgsx_lo       ),
    .bg_bank        ( bg_bank       ),
    .fg_bank        ( fg_bank       ),
    .txt_addr       ( txt_addr      ),
    .txt_data       ( txt_data      ),
    .bg_addr        ( bg_addr       ),
    .bg_data        ( bg_data       ),
    .fg_addr        ( fg_addr       ),
    .fg_data        ( fg_data       ),
    .obj_addr       ( obj_addr      ),
    .obj_data       ( obj_data      ),
    .pal_addr       ( pal_addr      ),
    .pal_data       ( pal_data      ),
    .txt_rom_addr   ( chr_addr      ),
    .txt_rom_cs     ( chr_cs        ),
    .txt_rom_data   ( chr_data      ),
    .txt_rom_ok     ( chr_ok        ),
    .bg_rom_addr    ( scr2_addr     ),
    .bg_rom_cs      ( scr2_cs       ),
    .bg_rom_data    ( scr2_data     ),
    .bg_rom_ok      ( scr2_ok       ),
    .fg_rom_addr    ( scr1_addr     ),
    .fg_rom_cs      ( scr1_cs       ),
    .fg_rom_data    ( scr1_data     ),
    .fg_rom_ok      ( scr1_ok       ),
    .spr_rom_addr   ( spr_addr      ),
    .spr_rom_cs     ( spr_cs        ),
    .spr_rom_data   ( spr_data      ),
    .spr_rom_ok     ( spr_ok        ),
    .vint           ( vint          ),
    .LHBL           ( LHBL          ),
    .LVBL           ( LVBL          ),
    .HS             ( HS            ),
    .VS             ( VS            ),
    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          )
);

endmodule
