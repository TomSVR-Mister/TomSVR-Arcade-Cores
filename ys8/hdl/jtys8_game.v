/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung 8-bit (Rock Tris, Magix / Rock, Cannon Ball) on JTFRAME (Jose Tejada, jotego). Personal build. */

module jtys8_game(
    `include "jtframe_game_ports.inc"
);

wire [ 7:0] sys, p1, p2;
wire [10:0] vaddr;
wire [ 1:0] layers;
wire        flip, snd_wr, vbl_irq;
reg         bgbig = 1;      // header byte 0 bit 0: 2 MB background (Magix, Rock Tris, Cannon Ball vertical)

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif
always @(posedge clk) if( header && prog_we && prog_addr[1:0]==0 ) bgbig <= prog_data[0];

// coin and service are 1-frame pulses (MAME PORT_IMPULSE(1))
reg  [1:0] in_l, pulse;
reg        lvbl_l, pend_c, pend_s;
always @(posedge clk) begin
    lvbl_l <= vbl_irq;
    in_l   <= { service, coin[0] };
    if( rst ) begin
        pulse <= 0; pend_c <= 0; pend_s <= 0;
    end else begin
        if( !coin[0] && in_l[0] ) pend_c <= 1;
        if( !service && in_l[1] ) pend_s <= 1;
        if( !vbl_irq && lvbl_l ) begin     // one pulse per frame, starting at vblank
            pulse  <= { pend_s, pend_c };
            pend_c <= 0;
            pend_s <= 0;
        end
    end
end

// system: -, start 2, -, start 1, -, service, -, coin (active low)
assign sys = { ~pulse[0], 1'b1, ~pulse[1], 1'b1, cab_1p[0], 1'b1, cab_1p[1], 1'b1 };
// players: up, down, left, right, button 1, button 2, button 3, -
assign p1  = { joystick1[3], joystick1[2], joystick1[1], joystick1[0], joystick1[4], joystick1[5], joystick1[6], 1'b1 };
assign p2  = { joystick2[3], joystick2[2], joystick2[1], joystick2[0], joystick2[4], joystick2[5], joystick2[6], 1'b1 };

assign t0lo_addr = vaddr, t0hi_addr = vaddr, t1lo_addr = vaddr, t1hi_addr = vaddr;
assign c0_addr = vaddr, c1_addr = vaddr, plo_addr = vaddr, phi_addr = vaddr;

jtys8_main u_main(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen8       ( cen8        ),
    .lvbl       ( vbl_irq     ),
    .sys        ( sys         ),
    .p1         ( p1          ),
    .p2         ( p2          ),
    .dsw1       ( dipsw[ 7:0] ),
    .dsw2       ( dipsw[15:8] ),
    .cpu_dout   ( cpu_dout    ),
    .rom_addr   ( main_addr   ),
    .rom_cs     ( main_cs     ),
    .rom_data   ( main_data   ),
    .rom_ok     ( main_ok     ),
    .vaddr      ( vaddr       ),
    .t0lo_we    ( t0lo_we     ),
    .t0hi_we    ( t0hi_we     ),
    .t1lo_we    ( t1lo_we     ),
    .t1hi_we    ( t1hi_we     ),
    .c0_we      ( c0_we       ),
    .c1_we      ( c1_we       ),
    .plo_we     ( plo_we      ),
    .phi_we     ( phi_we      ),
    .t0lo_dout  ( t0lo_dout   ),
    .t0hi_dout  ( t0hi_dout   ),
    .t1lo_dout  ( t1lo_dout   ),
    .t1hi_dout  ( t1hi_dout   ),
    .c0_dout    ( c0_dout     ),
    .c1_dout    ( c1_dout     ),
    .plo_dout   ( plo_dout    ),
    .phi_dout   ( phi_dout    ),
    .layers     ( layers      ),
    .flip       ( flip        ),
    .snd_wr     ( snd_wr      )
);

jtys8_sound u_sound(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen4       ( cen4        ),
    .cen_adpcm  ( cen_adpcm   ),
    .main_dout  ( cpu_dout    ),
    .snd_wr     ( snd_wr      ),
    .rom_addr   ( snd_addr    ),
    .rom_cs     ( snd_cs      ),
    .rom_data   ( snd_data    ),
    .rom_ok     ( snd_ok      ),
    .fm         ( fm          ),
    .pcm        ( pcm         )
);

jtys8_video u_video(
    .rst              ( rst              ),
    .clk              ( clk              ),
    .pxl_cen          ( pxl_cen          ),
    .gfx_en           ( gfx_en           ),
    .flip             ( flip             ),
    .layers           ( layers           ),
    .bgbig            ( bgbig            ),
    .t0lo_video_addr  ( t0lo_video_addr  ),
    .t0hi_video_addr  ( t0hi_video_addr  ),
    .c0_video_addr    ( c0_video_addr    ),
    .t0lo_video_dout  ( t0lo_video_dout  ),
    .t0hi_video_dout  ( t0hi_video_dout  ),
    .c0_video_dout    ( c0_video_dout    ),
    .t1lo_video_addr  ( t1lo_video_addr  ),
    .t1hi_video_addr  ( t1hi_video_addr  ),
    .c1_video_addr    ( c1_video_addr    ),
    .t1lo_video_dout  ( t1lo_video_dout  ),
    .t1hi_video_dout  ( t1hi_video_dout  ),
    .c1_video_dout    ( c1_video_dout    ),
    .plo_video_addr   ( plo_video_addr   ),
    .phi_video_addr   ( phi_video_addr   ),
    .plo_video_dout   ( plo_video_dout   ),
    .phi_video_dout   ( phi_video_dout   ),
    .bgt_addr         ( bgt_addr         ),
    .bgt_cs           ( bgt_cs           ),
    .bgt_data         ( bgt_data         ),
    .bgt_ok           ( bgt_ok           ),
    .fgt_addr         ( fgt_addr         ),
    .fgt_cs           ( fgt_cs           ),
    .fgt_data         ( fgt_data         ),
    .fgt_ok           ( fgt_ok           ),
    .vbl_irq          ( vbl_irq          ),
    .LHBL             ( LHBL             ),
    .LVBL             ( LVBL             ),
    .HS               ( HS               ),
    .VS               ( VS               ),
    .red              ( red              ),
    .green            ( green            ),
    .blue             ( blue             )
);

endmodule
