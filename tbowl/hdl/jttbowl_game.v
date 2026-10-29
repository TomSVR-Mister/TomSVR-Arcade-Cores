/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Tecmo Bowl (Tecmo 1987, MAME tecmo/tbowl.cpp) on JTFRAME (Jose Tejada, jotego). Personal build.
 * Boards 6206B (main Z80, tile layers, inputs), 6206C (sub Z80, sprites, palette) and 6206A (sound Z80, two YM3812,
 * two MSM5205). Four players, two monitors (see jttbowl_video). OSD status bits 22-21: 0 side by side, 1 left monitor,
 * 2 right monitor. */
module jttbowl_game(
    `include "jtframe_game_ports.inc"
);

wire [12:0] main_a;
wire [11:0] sub_a;
wire [ 7:0] main_dout, sub_dout, sh0_dout, sh1_dout, obj_dout, pal_dout, bg0_dout, bg1_dout, txt_dout;
wire [ 7:0] p1, p2, p3, p4, sys;
wire [ 9:0] sh0_addr, sh1_addr;
wire [10:0] scrx0, scrx1;
wire [ 8:0] scry0, scry1;
wire        sh0_we, sh1_we, bg0_we, bg1_we, txt_we, obj_we, pal_we, irq_vb, main_nmi, snd_wr, snd_ack;
reg  [ 7:0] snd_latch;
reg         snd_pend;
wire        cpu_cen = cen8 & dip_pause;
wire [ 1:0] mode    = status[22:21]==3 ? 2'd1 : status[22:21];

assign dip_flip   = 1'b0;
assign debug_view = { 6'd0, mode };

// MAME inputs, active low: right, left, down, up, B1, B2, service n, start n
// The game joins a player with button 1 (the board has no start buttons): Start acts as button 1 too
assign p1  = { cab_1p[0], 1'b1, joystick1[5], joystick1[4] & cab_1p[0], joystick1[3:0] };
assign p2  = { cab_1p[1], 1'b1, joystick2[5], joystick2[4] & cab_1p[1], joystick2[3:0] };
assign p3  = { cab_1p[2], 1'b1, joystick3[5], joystick3[4] & cab_1p[2], joystick3[3:0] };
assign p4  = { cab_1p[3], 1'b1, joystick4[5], joystick4[4] & cab_1p[3], joystick4[3:0] };
// coins 1-4, general service
assign sys = { 3'b111, service, coin[3:0] };

// ---------------- sound latch (MAME generic_latch_8 with separate acknowledge) ----------------
always @(posedge clk) begin
    if( rst ) begin
        snd_latch <= 0; snd_pend <= 0;
    end else begin
        if( snd_wr ) begin snd_latch <= main_dout; snd_pend <= 1; end
        else if( snd_ack ) snd_pend <= 0;
    end
end

// ---------------- RAM shared between main and sub (f800-fbff) ----------------
jtframe_dual_ram #(.AW(10)) u_shared(
    .clk0( clk ), .data0( main_dout ), .addr0( sh0_addr ), .we0( sh0_we ), .q0( sh0_dout ),
    .clk1( clk ), .data1( sub_dout  ), .addr1( sh1_addr ), .we1( sh1_we ), .q1( sh1_dout ) );

jttbowl_main u_main(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cpu_cen       ),
    .irq_vb     ( irq_vb        ),
    .nmi        ( main_nmi      ),
    .cpu_dout   ( main_dout     ),
    .cpu_addr   ( main_a        ),
    .p1         ( p1            ),
    .p2         ( p2            ),
    .p3         ( p3            ),
    .p4         ( p4            ),
    .sys        ( sys           ),
    .dipsw      ( dipsw[23:0]   ),
    .rom_addr   ( main_addr     ),
    .rom_cs     ( main_cs       ),
    .rom_data   ( main_data     ),
    .rom_ok     ( main_ok       ),
    .bg1_we     ( bg1_we        ),
    .bg0_we     ( bg0_we        ),
    .txt_we     ( txt_we        ),
    .bg1_dout   ( bg1_dout      ),
    .bg0_dout   ( bg0_dout      ),
    .txt_dout   ( txt_dout      ),
    .scrx0      ( scrx0         ),
    .scrx1      ( scrx1         ),
    .scry0      ( scry0         ),
    .scry1      ( scry1         ),
    .sh_addr    ( sh0_addr      ),
    .sh_we      ( sh0_we        ),
    .sh_dout    ( sh0_dout      ),
    .snd_wr     ( snd_wr        )
);

jttbowl_sub u_sub(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cpu_cen       ),
    .irq_vb     ( irq_vb        ),
    .main_nmi   ( main_nmi      ),
    .cpu_dout   ( sub_dout      ),
    .cpu_addr   ( sub_a         ),
    .rom_addr   ( sub_addr      ),
    .rom_cs     ( sub_cs        ),
    .rom_data   ( sub_data      ),
    .rom_ok     ( sub_ok        ),
    .obj_we     ( obj_we        ),
    .obj_dout   ( obj_dout      ),
    .pal_we     ( pal_we        ),
    .pal_dout   ( pal_dout      ),
    .sh_addr    ( sh1_addr      ),
    .sh_we      ( sh1_we        ),
    .sh_dout    ( sh1_dout      )
);

jttbowl_snd u_snd(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .cen        ( cen4 & dip_pause ),
    .cen_fm     ( cen4          ),
    .cen_pcm    ( cen384        ),
    .latch      ( snd_latch     ),
    .pending    ( snd_pend      ),
    .ack        ( snd_ack       ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .pcm0_addr  ( pcm0_addr     ),
    .pcm0_cs    ( pcm0_cs       ),
    .pcm0_data  ( pcm0_data     ),
    .pcm0_ok    ( pcm0_ok       ),
    .pcm1_addr  ( pcm1_addr     ),
    .pcm1_cs    ( pcm1_cs       ),
    .pcm1_data  ( pcm1_data     ),
    .pcm1_ok    ( pcm1_ok       ),
    .fm0        ( fm0           ),
    .fm1        ( fm1           ),
    .pcm0       ( pcm0          ),
    .pcm1       ( pcm1          )
);

jttbowl_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .mode       ( mode          ),
    .gfx_en     ( gfx_en        ),
    .pxl_cen    ( pxl_cen       ),
    .pxl2_cen   ( pxl2_cen      ),
    .main_addr  ( main_a        ),
    .main_dout  ( main_dout     ),
    .bg0_we     ( bg0_we        ),
    .bg1_we     ( bg1_we        ),
    .txt_we     ( txt_we        ),
    .bg0_dout   ( bg0_dout      ),
    .bg1_dout   ( bg1_dout      ),
    .txt_dout   ( txt_dout      ),
    .scrx0      ( scrx0         ),
    .scrx1      ( scrx1         ),
    .scry0      ( scry0         ),
    .scry1      ( scry1         ),
    .sub_addr   ( sub_a         ),
    .sub_dout   ( sub_dout      ),
    .obj_we     ( obj_we        ),
    .pal_we     ( pal_we        ),
    .obj_dout   ( obj_dout      ),
    .pal_dout   ( pal_dout      ),
    .bg0_addr   ( bg0_addr      ),
    .bg0_cs     ( bg0_cs        ),
    .bg0_data   ( bg0_data      ),
    .bg0_ok     ( bg0_ok        ),
    .bg1_addr   ( bg1_addr      ),
    .bg1_cs     ( bg1_cs        ),
    .bg1_data   ( bg1_data      ),
    .bg1_ok     ( bg1_ok        ),
    .txt_addr   ( txt_addr      ),
    .txt_cs     ( txt_cs        ),
    .txt_data   ( txt_data      ),
    .txt_ok     ( txt_ok        ),
    .obj_addr   ( obj_addr      ),
    .obj_cs     ( obj_cs        ),
    .obj_data   ( obj_data      ),
    .obj_ok     ( obj_ok        ),
    .irq_vb     ( irq_vb        ),
    .LHBL       ( LHBL          ),
    .LVBL       ( LVBL          ),
    .HS         ( HS            ),
    .VS         ( VS            ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          )
);

`ifdef SIMULATION
// frame-by-frame activity report for the simulation log
reg [15:0] dbg_pal, dbg_vram, dbg_obj, dbg_snd;
integer    st_main=0, st_sub=0, st_cen=0;
always @(posedge clk) if( cpu_cen ) begin
    st_cen <= st_cen + 1;
    if( main_cs && !main_ok ) st_main <= st_main + 1;
    if( sub_cs  && !sub_ok  ) st_sub  <= st_sub  + 1;
end
reg        dbg_lvbl;
integer    dbg_frame=0;
always @(posedge clk) begin
    dbg_lvbl <= LVBL;
    if( pal_we && cpu_cen ) dbg_pal  <= dbg_pal  + 1'd1;
    if( (bg0_we|bg1_we|txt_we) && cpu_cen ) dbg_vram <= dbg_vram + 1'd1;
    if( obj_we && cpu_cen ) dbg_obj  <= dbg_obj  + 1'd1;
    if( snd_wr ) dbg_snd <= dbg_snd + 1'd1;
    if( !LVBL && dbg_lvbl ) begin
        $display("F%0d main %04x sub %04x snd %04x pal %0d vram %0d obj %0d sndw %0d stall main %0d sub %0d of %0d", dbg_frame,
            u_main.A, u_sub.A, u_snd.A, dbg_pal, dbg_vram, dbg_obj, dbg_snd, st_main, st_sub, st_cen);
        st_main <= 0; st_sub <= 0; st_cen <= 0;
        dbg_frame <= dbg_frame + 1;
        dbg_pal <= 0; dbg_vram <= 0; dbg_obj <= 0; dbg_snd <= 0;
    end
end
`endif

endmodule
