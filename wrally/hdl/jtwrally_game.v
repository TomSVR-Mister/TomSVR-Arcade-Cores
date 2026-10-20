/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * World Rally (Gaelco, 1993; MAME wrally.cpp): 68000, DS5002FP protection CPU sharing the
 * 68000 work RAM, two encrypted 16x16 tile maps, shadow sprites and an OKI M6295.
 * On JTFRAME (Jose Tejada, jotego); the 68000 bus and VRAM decryption follow his JTGAE1.
 * Personal build. */

module jtwrally_game(
    `include "jtframe_game_ports.inc"
);

wire [13:1] vaddr;
wire [15:0] cpu_dout;
wire [ 1:0] vbe;
wire [15:0] vram_din, vram_dout, pal_dout, spr_dout, sha_dout;
wire [15:0] scr0_y, scr0_x, scr1_y, scr1_x;
wire [31:0] vram0_q, vram1_q, vram0_v, vram1_v;
wire [10:0] vram0_va, vram1_va, spr_va;
wire [15:0] spr_v, pal_v;
wire [12:0] pal_va;
wire        vram_we, pal_cs, spr_cs, sha_cs, mem_we, flip;
wire [ 7:0] oki_din, oki_dout;
wire        oki_wrn;
wire [ 3:0] oki_bank;
wire [17:0] oki_core_addr;
reg  [ 1:0] mcu_cnt;
wire        cen_mcu = mcu_cnt==0;
wire [13:0] mcu_xa;
wire [ 7:0] mcu_xd;
wire        mcu_xw;
wire [15:0] sha_mcu_q;

assign dip_flip   = flip;
assign debug_view = 8'd0;
assign oki_addr   = oki_core_addr < 18'h30000 ? { 2'd0, oki_core_addr } : { oki_bank, oki_core_addr[15:0] };
assign oki_cs     = 1'b1;

always @(posedge clk) mcu_cnt <= mcu_cnt + 2'd1;    // 12 MHz

// VRAM: one 32-bit word per tile, {code, attributes}. Word offset bit 12 selects the layer.
wire [ 3:0] vwe = !vram_we ? 4'd0 : vaddr[1] ? { 2'b00, vbe } : { vbe, 2'b00 };
wire [31:0] vq  = vaddr[13] ? vram1_q : vram0_q;
assign vram_dout = vaddr[1] ? vq[15:0] : vq[31:16];

jtframe_dual_ram32 #(.AW(13)) u_vram0(
    .clk0 ( clk ), .data0 ( {vram_din,vram_din} ), .addr0 ( vaddr[12:2] ), .we0 ( vaddr[13] ? 4'd0 : vwe ), .q0 ( vram0_q ),
    .clk1 ( clk ), .data1 ( 32'd0 ), .addr1 ( vram0_va ), .we1 ( 4'd0 ), .q1 ( vram0_v ) );
jtframe_dual_ram32 #(.AW(13)) u_vram1(
    .clk0 ( clk ), .data0 ( {vram_din,vram_din} ), .addr0 ( vaddr[12:2] ), .we0 ( vaddr[13] ? vwe : 4'd0 ), .q0 ( vram1_q ),
    .clk1 ( clk ), .data1 ( 32'd0 ), .addr1 ( vram1_va ), .we1 ( 4'd0 ), .q1 ( vram1_v ) );
jtframe_dual_ram16 #(.AW(13)) u_pal(
    .clk0 ( clk ), .data0 ( cpu_dout ), .addr0 ( vaddr ), .we0 ( {2{pal_cs&mem_we}} & vbe ), .q0 ( pal_dout ),
    .clk1 ( clk ), .data1 ( 16'd0 ), .addr1 ( pal_va ), .we1 ( 2'd0 ), .q1 ( pal_v ) );
jtframe_dual_ram16 #(.AW(11)) u_spr(
    .clk0 ( clk ), .data0 ( cpu_dout ), .addr0 ( vaddr[11:1] ), .we0 ( {2{spr_cs&mem_we}} & vbe ), .q0 ( spr_dout ),
    .clk1 ( clk ), .data1 ( 16'd0 ), .addr1 ( spr_va ), .we1 ( 2'd0 ), .q1 ( spr_v ) );
// work RAM shared with the DS5002FP, which sees it big endian
jtframe_dual_ram16 #(.AW(13)) u_shared(
    .clk0 ( clk ), .data0 ( cpu_dout ), .addr0 ( vaddr ), .we0 ( {2{sha_cs&mem_we}} & vbe ), .q0 ( sha_dout ),
    .clk1 ( clk ), .data1 ( {mcu_xd,mcu_xd} ), .addr1 ( mcu_xa[13:1] ),
    .we1  ( mcu_xw ? (mcu_xa[0] ? 2'b01 : 2'b10) : 2'b00 ), .q1 ( sha_mcu_q ) );

jtwrally_main u_main(
    .clk        ( clk        ),
    .rst        ( rst        ),
    .lvbl       ( LVBL       ),
    .main_addr  ( main_addr  ),
    .main_cs    ( main_cs    ),
    .main_data  ( main_data  ),
    .main_ok    ( main_ok    ),
    .cpu_dout   ( cpu_dout   ),
    .vaddr      ( vaddr      ),
    .vdsn_we    ( vbe        ),
    .vram_we    ( vram_we    ),
    .vram_din   ( vram_din   ),
    .pal_cs     ( pal_cs     ),
    .spr_cs     ( spr_cs     ),
    .sha_cs     ( sha_cs     ),
    .mem_we     ( mem_we     ),
    .vram_dout  ( vram_dout  ),
    .pal_dout   ( pal_dout   ),
    .spr_dout   ( spr_dout   ),
    .sha_dout   ( sha_dout   ),
    .scr0_y     ( scr0_y     ),
    .scr0_x     ( scr0_x     ),
    .scr1_y     ( scr1_y     ),
    .scr1_x     ( scr1_x     ),
    .dipsw      ( dipsw[15:0]),
    .joystick1  ( joystick1[5:0] ),
    .joystick2  ( joystick2[5:0] ),
    .coin       ( coin[1:0]  ),
    .start      ( cab_1p[1:0]),
    .service    ( service    ),
    .dip_test   ( dip_test   ),
    .dip_pause  ( dip_pause  ),
    .flip       ( flip       ),
    .oki_din    ( oki_din    ),
    .oki_dout   ( oki_dout   ),
    .oki_wrn    ( oki_wrn    ),
    .oki_bank   ( oki_bank   )
);

jtwrally_mcu u_mcu(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .cen        ( cen_mcu    ),
    .x_addr     ( mcu_xa     ),
    .x_dout     ( mcu_xd     ),
    .x_wr       ( mcu_xw     ),
    .x_din      ( mcu_xa[0] ? sha_mcu_q[7:0] : sha_mcu_q[15:8] ),
    .prog_addr  ( prog_addr[14:0] ),
    .prog_data  ( prog_data  ),
    .prom_we    ( prom_we    )
);

jt6295 u_oki(
    .rst      ( rst           ),
    .clk      ( clk           ),
    .cen      ( cen_oki       ),
    .ss       ( 1'b1          ),
    .wrn      ( oki_wrn       ),
    .din      ( oki_din       ),
    .dout     ( oki_dout      ),
    .rom_addr ( oki_core_addr ),
    .rom_data ( oki_data      ),
    .rom_ok   ( oki_ok        ),
    .sound    ( pcm           ),
    .sample   (               )
);

jtwrally_video u_video(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .pxl_cen    ( pxl_cen    ),
    .gfx_en     ( gfx_en     ),
    .scr0_y     ( scr0_y     ),
    .scr0_x     ( scr0_x     ),
    .scr1_y     ( scr1_y     ),
    .scr1_x     ( scr1_x     ),
    .vram0_addr ( vram0_va   ),
    .vram0_dout ( vram0_v    ),
    .vram1_addr ( vram1_va   ),
    .vram1_dout ( vram1_v    ),
    .scr0_addr  ( scr0_addr  ),
    .scr0_data  ( scr0_data  ),
    .scr0_cs    ( scr0_cs    ),
    .scr0_ok    ( scr0_ok    ),
    .scr1_addr  ( scr1_addr  ),
    .scr1_data  ( scr1_data  ),
    .scr1_cs    ( scr1_cs    ),
    .scr1_ok    ( scr1_ok    ),
    .spr_addr   ( spr_va     ),
    .spr_dout   ( spr_v      ),
    .obj_addr   ( obj_addr   ),
    .obj_data   ( obj_data   ),
    .obj_cs     ( obj_cs     ),
    .obj_ok     ( obj_ok     ),
    .pal_addr   ( pal_va     ),
    .pal_dout   ( pal_v      ),
    .red        ( red        ),
    .green      ( green      ),
    .blue       ( blue       ),
    .LHBL       ( LHBL       ),
    .LVBL       ( LVBL       ),
    .HS         ( HS         ),
    .VS         ( VS         )
);

endmodule
