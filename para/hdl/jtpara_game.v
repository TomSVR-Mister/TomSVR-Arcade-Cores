/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Yun Sung Paradise / Paradise Deluxe / Paradise 2 Deluxe on JTFRAME (Jose Tejada, jotego). Personal build. */

module jtpara_game(
    `include "jtframe_game_ports.inc"
);

wire [ 7:0] prio, p1, p2, sys, oki1_dout, oki2_dout;
wire [ 3:0] bg_bank, pix_bank;
wire [10:0] vram_addr;
wire        flip, irq, lvbl_raw, oki1_wrn, oki2_wrn, oki2_bank;
wire [17:0] oki1_raw;
wire [17:0] oki2_raw;
// header (MRA): byte 0 = { tgt_vbl, fg1m, spr1m, tlay, tmap, inc4, tflip }, byte 1 = { mode, ... , bank_mask }
reg  [ 7:0] hdr0 = 0, hdr1 = 8'h0f;
wire        tflip   = hdr0[0];   // Target Ball family flip polarity
wire        inc4    = hdr0[1];   // sprites every 4 bytes
wire        tmap    = hdr0[2];   // Torus memory map, 512 sprites
wire        tlay    = hdr0[3];   // Torus sprite layout
wire        spr1m   = hdr0[4];   // 1 MB of sprites (Penky)
wire        fg1m    = hdr0[5];   // 1 MB fg tiles
wire        tgt_vbl = hdr0[6];   // vblank in system bit 3 (Target Ball)
wire [ 3:0] bank_mask = hdr1[3:0];
wire [ 1:0] vmode   = hdr1[5:4]; // 0 Paradise, 1 Torus, 2 Mad Ball

always @(posedge clk) if( header && prog_we ) begin
    if( prog_addr[1:0]==0 ) hdr0 <= prog_data;
    if( prog_addr[1:0]==1 ) hdr1 <= prog_data;
end

assign dip_flip   = 1'b0;     // flip is done in the layers; JTFRAME would flip the frame a second time
assign debug_view = prio;
`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

assign vram0_addr = vram_addr;
assign vram1_addr = vram_addr;
assign vram2_addr = vram_addr;

// P1/P2 (active low): up, down, left, right, button 1, button 2, -, start
assign p1  = { cab_1p[0], 1'b1, joystick1[5:0] };
assign p2  = { cab_1p[1], 1'b1, joystick2[5:0] };
// coin 1, coin 2, ..., bit 6 = vblank (active low)
// Coins are sent as 5-frame pulses per press (MAME PORT_IMPULSE(5)): Paradise Deluxe ignores a coin held down longer.
reg  [1:0] coin_l, coin_p;
reg  [2:0] coin_cnt[0:1];
reg        lvbl_l;
integer    ci;
always @(posedge clk) begin
    lvbl_l <= lvbl_raw;
    coin_l <= coin[1:0];
    for( ci=0; ci<2; ci=ci+1 ) begin
        if( rst ) begin
            coin_cnt[ci] <= 0;
            coin_p[ci]   <= 1;
        end else begin
            if( !coin[ci] && coin_l[ci] ) coin_cnt[ci] <= 3'd5;   // new press (active low)
            else if( !lvbl_raw && lvbl_l && coin_cnt[ci]!=0 ) coin_cnt[ci] <= coin_cnt[ci] - 3'd1;
            coin_p[ci] <= coin_cnt[ci]==0;
        end
    end
end
assign sys = tgt_vbl ? { 4'hf, lvbl_raw, 1'b1, coin_p } : { 1'b1, lvbl_raw, 4'hf, coin_p };

jtpara_main u_main(
    .rst         ( rst          ),
    .clk         ( clk          ),
    .cen6        ( cen6         ),
    .irq         ( irq          ),
    .lvbl        ( lvbl_raw     ),
    .tmap        ( tmap         ),
    .tflip       ( tflip        ),
    .bank_mask   ( bank_mask    ),
    .p1          ( p1           ),
    .p2          ( p2           ),
    .sys         ( sys          ),
    .dipsw       ( dipsw[15:0]  ),
    .cpu_dout    ( cpu_dout     ),
    .rom_addr    ( main_addr    ),
    .rom_cs      ( main_cs      ),
    .rom_data    ( main_data    ),
    .rom_ok      ( main_ok      ),
    .vram_addr   ( vram_addr    ),
    .vram0_we    ( vram0_we     ),
    .vram1_we    ( vram1_we     ),
    .vram2_we    ( vram2_we     ),
    .vram0_dout  ( vram0_dout   ),
    .vram1_dout  ( vram1_dout   ),
    .vram2_dout  ( vram2_dout   ),
    .objram_addr ( objram_addr  ),
    .objram_we   ( objram_we    ),
    .objram_dout ( objram_dout  ),
    .pix_addr    ( pix_addr     ),
    .pix_we      ( pix_we       ),
    .pix_dout    ( pix_dout     ),
    .pal_addr    ( palr_addr    ),
    .palr_we     ( palr_we      ),
    .palg_we     ( palg_we      ),
    .palb_we     ( palb_we      ),
    .palr_dout   ( palr_dout    ),
    .palg_dout   ( palg_dout    ),
    .palb_dout   ( palb_dout    ),
    .prio        ( prio         ),
    .flip        ( flip         ),
    .bg_bank     ( bg_bank      ),
    .pix_bank    ( pix_bank     ),
    .oki1_wrn    ( oki1_wrn     ),
    .oki2_wrn    ( oki2_wrn     ),
    .oki1_dout   ( oki1_dout    ),
    .oki2_dout   ( oki2_dout    ),
    .oki2_bank   ( oki2_bank    )
);
assign palg_addr = palr_addr;
assign palb_addr = palr_addr;

// two OKI M6295 at 1 MHz, pin 7 high. OKI 2 has two 256 kB banks.
assign oki1_cs   = 1'b1;
assign oki2_cs   = 1'b1;
assign oki1_addr = oki1_raw;
assign oki2_addr = { oki2_bank, oki2_raw };

jt6295 #(.INTERPOL(0)) u_oki1(
    .rst      ( rst       ),
    .clk      ( clk       ),
    .cen      ( cen1      ),
    .ss       ( 1'b1      ),
    .wrn      ( oki1_wrn  ),
    .din      ( cpu_dout  ),
    .dout     ( oki1_dout ),
    .rom_addr ( oki1_raw  ),
    .rom_data ( oki1_data ),
    .rom_ok   ( oki1_ok   ),
    .sound    ( pcm1      ),
    .sample   (           )
);

jt6295 #(.INTERPOL(0)) u_oki2(
    .rst      ( rst       ),
    .clk      ( clk       ),
    .cen      ( cen1      ),
    .ss       ( 1'b1      ),
    .wrn      ( oki2_wrn  ),
    .din      ( cpu_dout  ),
    .dout     ( oki2_dout ),
    .rom_addr ( oki2_raw  ),
    .rom_data ( oki2_data ),
    .rom_ok   ( oki2_ok   ),
    .sound    ( pcm2      ),
    .sample   (           )
);

jtpara_video u_video(
    .rst                ( rst               ),
    .clk                ( clk               ),
    .pxl_cen            ( pxl_cen           ),
    .gfx_en             ( gfx_en            ),
    .flip               ( flip              ),
    .prio               ( prio              ),
    .bg_bank            ( bg_bank           ),
    .pix_bank           ( pix_bank          ),
    .mode               ( vmode             ),
    .inc4               ( inc4              ),
    .many               ( tmap              ),
    .tlay               ( tlay              ),
    .spr1m              ( spr1m             ),
    .fg1m               ( fg1m              ),
    .vram0_video_addr   ( vram0_video_addr  ),
    .vram1_video_addr   ( vram1_video_addr  ),
    .vram2_video_addr   ( vram2_video_addr  ),
    .vram0_video_dout   ( vram0_video_dout  ),
    .vram1_video_dout   ( vram1_video_dout  ),
    .vram2_video_dout   ( vram2_video_dout  ),
    .objram_video_addr  ( objram_video_addr ),
    .objram_video_dout  ( objram_video_dout ),
    .pix_video_addr     ( pix_video_addr    ),
    .pix_video_dout     ( pix_video_dout    ),
    .pal_video_addr     ( palr_video_addr   ),
    .palr_video_dout    ( palr_video_dout   ),
    .palg_video_dout    ( palg_video_dout   ),
    .palb_video_dout    ( palb_video_dout   ),
    .bgt_addr           ( bgt_addr          ),
    .bgt_cs             ( bgt_cs            ),
    .bgt_data           ( bgt_data          ),
    .bgt_ok             ( bgt_ok            ),
    .fgt_addr           ( fgt_addr          ),
    .fgt_cs             ( fgt_cs            ),
    .fgt_data           ( fgt_data          ),
    .fgt_ok             ( fgt_ok            ),
    .mgt_addr           ( mgt_addr          ),
    .mgt_cs             ( mgt_cs            ),
    .mgt_data           ( mgt_data          ),
    .mgt_ok             ( mgt_ok            ),
    .obj_addr           ( obj_addr          ),
    .obj_cs             ( obj_cs            ),
    .obj_data           ( obj_data          ),
    .obj_ok             ( obj_ok            ),
    .irq                ( irq               ),
    .lvbl_raw           ( lvbl_raw          ),
    .LHBL               ( LHBL              ),
    .LVBL               ( LVBL              ),
    .HS                 ( HS                ),
    .VS                 ( VS                ),
    .red                ( red               ),
    .green              ( green             ),
    .blue               ( blue              )
);
assign palg_video_addr = palr_video_addr;
assign palb_video_addr = palr_video_addr;

endmodule
