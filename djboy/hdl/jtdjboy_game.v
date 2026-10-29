/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DJ Boy (Kaneko 1989, MAME kaneko/djboy.cpp) and Air Buster (Kaneko 1990, MAME kaneko/airbustr.cpp) on JTFRAME
 * (Jose Tejada, jotego). Personal build. Three Z80s at 6 MHz, Kaneko Pandora sprites, YM2203 + OKI M6295.
 * Header byte 0: bit 0 = Air Buster board, bit 1 = ROM bank ^ 1f (djboyj, djboyja), bit 2 = CALC1 present
 * (airbustr, airbustrj; the bootleg has plain RAM there). */
module jtdjboy_game(
    `include "jtframe_game_ports.inc"
);

wire [15:0] sub_a;
wire [ 7:0] main_dout, sub_dout, sh0_dout, sh1_dout, oram_dout, vram_dout, pal_dout;
wire [ 7:0] p1, p2, sys, in0, vreg, scrx0, scry0, scrx1, scry1, scrhi;
wire [ 7:0] bst_dout, bst_status, reply;
wire [12:0] sh0_addr, sh1_addr;
wire [11:0] oram_addr;
wire        oram_we, sh0_we, sh1_we, vram_we, pal_we, ocopy, irq_vb, irq_64;
wire        wdog, main_nmi, sub_nmi, snd_wr, sndr_rd, bst_wr, bst_rd, snd_rd, reply_wr, sub_rstn;
reg  [ 7:0] snd_latch;
reg         abus = 0, bankxor = 0, calc_en = 0, snd_pend, reply_pend;
wire        cpu_cen = cen6 & dip_pause;
`ifdef AIRBUSTR
initial begin abus = 1; calc_en = 1; end    // simulation without a ROM download: the header is not seen
`endif

assign dip_flip   = 1'b0;
assign debug_view = { 5'd0, calc_en, bankxor, abus };

always @(posedge clk) if( header && prog_we && prog_addr[2:0]==0 ) { calc_en, bankxor, abus } <= prog_data[2:0];

// MAME inputs, active low. P1/P2: up, down, left, right, B1, B2 (DJ Boy B3), -, -
assign p1  = { 1'b1, abus | joystick1[6], joystick1[5], joystick1[4],
               joystick1[0], joystick1[1], joystick1[2], joystick1[3] };
assign p2  = { 1'b1, abus | joystick2[6], joystick2[5], joystick2[4],
               joystick2[0], joystick2[1], joystick2[2], joystick2[3] };
// Air Buster SYSTEM / DJ Boy IN0: start 1, start 2, coin 1, coin 2, -, (DJ Boy tilt), service, -
assign sys = { 1'b1, service, 2'b11, coin[1], coin[0], cab_1p[1], cab_1p[0] };
assign in0 = sys;

// ---------------- watchdog (CALC1 boards) ----------------
// MAME resets the machine (CPUs and latches, not the RAM) 3 s after the last CALC1 register 0 read. The game relies
// on it: the first power up only writes a signature to RAM and waits for the watchdog to start the warm boot.
reg  [ 7:0] wd_frames;
reg  [ 7:0] wd_hold;
reg         wd_rst;
wire        rst_wd = rst | wd_rst;

always @(posedge clk) begin
    if( rst ) begin
        wd_frames <= 0; wd_hold <= 0; wd_rst <= 0;
    end else begin
        if( wd_hold!=0 ) wd_hold <= wd_hold - 1'd1;
        wd_rst <= wd_hold!=0;
        if( wdog || !calc_en ) wd_frames <= 0;
        else if( irq_vb ) begin
            if( wd_frames==8'd171 ) begin   // 3 s at 57.4 Hz
                wd_frames <= 0;
                wd_hold   <= 8'hff;
            end else wd_frames <= wd_frames + 1'd1;
        end
    end
end

// ---------------- latches ----------------
always @(posedge clk) begin
    if( rst_wd ) begin
        snd_latch <= 0; snd_pend <= 0; reply_pend <= 0;
    end else begin
        if( snd_wr ) begin snd_latch <= sub_dout; snd_pend <= 1; end
        else if( snd_rd ) snd_pend <= 0;
        if( reply_wr ) reply_pend <= 1;
        else if( sndr_rd ) reply_pend <= 0;
    end
end

// ---------------- memories shared between CPUs ----------------
jtframe_dual_ram #(.AW(13)) u_shared(
    .clk0( clk ), .data0( main_dout ), .addr0( sh0_addr ), .we0( sh0_we ), .q0( sh0_dout ),
    .clk1( clk ), .data1( sub_dout  ), .addr1( sh1_addr ), .we1( sh1_we ), .q1( sh1_dout ) );

jtframe_dual_ram #(.AW(12)) u_oram(
    .clk0( clk ), .data0( main_dout ), .addr0( oram_addr ), .we0( oram_we ), .q0( oram_dout ),
    .clk1( clk ), .data1( 8'd0 ), .addr1( ovid_addr ), .we1( 1'b0 ), .q1( ovid_dout ) );

wire [11:0] ovid_addr;
wire [ 7:0] ovid_dout;

jtdjboy_main u_main(
    .rst        ( rst_wd        ),
    .clk        ( clk           ),
    .cen        ( cpu_cen       ),
    .abus       ( abus          ),
    .bankxor    ( bankxor       ),
    .calc_en    ( calc_en       ),
    .irq_vb     ( irq_vb        ),
    .irq_64     ( irq_64        ),
    .nmi        ( main_nmi      ),
    .sub_nmi    ( sub_nmi       ),
    .wdog       ( wdog          ),
    .cpu_dout   ( main_dout     ),
    .rom_addr   ( main_addr     ),
    .rom_cs     ( main_cs       ),
    .rom_data   ( main_data     ),
    .rom_ok     ( main_ok       ),
    .oram_addr  ( oram_addr     ),
    .oram_we    ( oram_we       ),
    .oram_dout  ( oram_dout     ),
    .ocopy      ( ocopy         ),
    .sh_addr    ( sh0_addr      ),
    .sh_we      ( sh0_we        ),
    .sh_dout    ( sh0_dout      )
);

jtdjboy_sub u_sub(
    .rst        ( rst_wd        ),
    .clk        ( clk           ),
    .cen        ( cpu_cen       ),
    .abus       ( abus          ),
    .rstn_beast ( sub_rstn      ),
    .irq_vb     ( irq_vb        ),
    .nmi        ( sub_nmi       ),
    .main_nmi   ( main_nmi      ),
    .A          ( sub_a         ),
    .cpu_dout   ( sub_dout      ),
    .p1         ( p1            ),
    .p2         ( p2            ),
    .sys        ( sys           ),
    .rom_addr   ( sub_addr      ),
    .rom_cs     ( sub_cs        ),
    .rom_data   ( sub_data      ),
    .rom_ok     ( sub_ok        ),
    .vram_we    ( vram_we       ),
    .vram_dout  ( vram_dout     ),
    .pal_we     ( pal_we        ),
    .pal_dout   ( pal_dout      ),
    .sh_addr    ( sh1_addr      ),
    .sh_we      ( sh1_we        ),
    .sh_dout    ( sh1_dout      ),
    .snd_wr     ( snd_wr        ),
    .sndr_rd    ( sndr_rd       ),
    .sndr_dout  ( reply         ),
    .snd_status ( { 5'd1, snd_pend, ~reply_pend } ),
    .bst_wr     ( bst_wr        ),
    .bst_rd     ( bst_rd        ),
    .bst_dout   ( bst_dout      ),
    .bst_status ( bst_status    ),
    .vreg       ( vreg          ),
    .scrx0      ( scrx0         ),
    .scry0      ( scry0         ),
    .scrx1      ( scrx1         ),
    .scry1      ( scry1         ),
    .scrhi      ( scrhi         )
);

jtdjboy_beast u_beast(
    .rst        ( rst_wd | abus ),
    .clk        ( clk           ),
    .clk_mcu    ( clk24         ),
    .cen        ( cen_mcu & dip_pause ),
    .in0        ( in0           ),
    .in1        ( p1            ),
    .in2        ( p2            ),
    .dsw1       ( dipsw[ 7:0]   ),
    .dsw2       ( dipsw[15:8]   ),
    .sub_dout   ( sub_dout      ),
    .sub_wr     ( bst_wr        ),
    .sub_rd     ( bst_rd        ),
    .sub_din    ( bst_dout      ),
    .status     ( bst_status    ),
    .sub_rstn   ( sub_rstn      ),
    .prog_addr  ( prog_addr[11:0] ),
    .prog_data  ( prog_data     ),
    .prom_we    ( prom_we       )
);

jtdjboy_snd u_snd(
    .rst        ( rst_wd        ),
    .clk        ( clk           ),
    .cen        ( cpu_cen       ),
    .cen_fm     ( cen3          ),
    .cen_oki    ( abus ? cen3 : cen1p5 ),
    .abus       ( abus          ),
    .dsw1       ( dipsw[ 7:0]   ),
    .dsw2       ( dipsw[15:8]   ),
    .latch      ( snd_latch     ),
    .pending    ( snd_pend      ),
    .latch_rd   ( snd_rd        ),
    .reply      ( reply         ),
    .reply_wr   ( reply_wr      ),
    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_data   ( snd_data      ),
    .rom_ok     ( snd_ok        ),
    .oki0_addr  ( oki0_addr     ),
    .oki0_data  ( oki0_data     ),
    .oki0_ok    ( oki0_ok       ),
    .oki1_addr  ( oki1_addr     ),
    .oki1_data  ( oki1_data     ),
    .oki1_ok    ( oki1_ok       ),
    .fm         ( fm            ),
    .psg        ( psg           ),
    .pcm_l      ( pcm_l         ),
    .pcm_r      ( pcm_r         )
);
assign oki0_cs = 1'b1;
assign oki1_cs = ~abus;

jtdjboy_video u_video(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .abus       ( abus          ),
    .gfx_en     ( gfx_en        ),
    .cpu_addr   ( sub_a[11:0]   ),
    .cpu_dout   ( sub_dout      ),
    .vram_we    ( vram_we       ),
    .vram_dout  ( vram_dout     ),
    .pal_we     ( pal_we        ),
    .pal_dout   ( pal_dout      ),
    .vreg       ( vreg          ),
    .scrx0      ( scrx0         ),
    .scry0      ( scry0         ),
    .scrx1      ( scrx1         ),
    .scry1      ( scry1         ),
    .scrhi      ( scrhi         ),
    .ovid_addr  ( ovid_addr     ),
    .ovid_dout  ( ovid_dout     ),
    .ocopy      ( ocopy         ),
    .scr0_addr  ( scr0_addr     ),
    .scr0_cs    ( scr0_cs       ),
    .scr0_data  ( scr0_data     ),
    .scr0_ok    ( scr0_ok       ),
    .scr1_addr  ( scr1_addr     ),
    .scr1_cs    ( scr1_cs       ),
    .scr1_data  ( scr1_data     ),
    .scr1_ok    ( scr1_ok       ),
    .obj_addr   ( obj_addr      ),
    .obj_cs     ( obj_cs        ),
    .obj_data   ( obj_data      ),
    .obj_ok     ( obj_ok        ),
    .irq_vb     ( irq_vb        ),
    .irq_64     ( irq_64        ),
    .LHBL       ( LHBL          ),
    .LVBL       ( LVBL          ),
    .HS         ( HS            ),
    .VS         ( VS            ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          )
);

`ifdef PCTRACE
integer ftr_sub, ftr_main, ftr_snd;
reg     m1s_l, m1m_l, m1a_l;
initial begin
    ftr_sub  = $fopen("pc_sub.txt","w");
    ftr_main = $fopen("pc_main.txt","w");
    ftr_snd  = $fopen("pc_snd.txt","w");
    ftr_mcu  = $fopen("pc_mcu.txt","w");
end
integer ftr_mcu;
reg [15:0] mcu_pc_l;
always @(posedge clk) begin
    if( bst_wr ) $fdisplay(ftr_mcu, "W %02X", sub_dout);
    if( bst_rd ) $fdisplay(ftr_mcu, "R %02X", bst_dout);
end
always @(posedge clk) if( u_beast.u_mcu.u_mcu.next_instruction && u_beast.u_mcu.u_mcu.cen ) begin
    $fdisplay(ftr_mcu, "%04X a=%02X bl=%02X p0=%02X p1=%02X", u_beast.u_mcu.u_mcu.pc, u_beast.u_mcu.u_mcu.u_regs.a, u_beast.blatch, u_beast.p0, u_beast.p1);
end
always @(posedge clk) begin
    m1s_l <= u_sub.m1_n;  m1m_l <= u_main.m1_n;  m1a_l <= u_snd.m1_n;
    if( !u_sub.m1_n  && m1s_l && u_sub.iorq_n  ) $fdisplay(ftr_sub,  "%04X", sub_a);
    if( !u_main.m1_n && m1m_l && u_main.iorq_n ) $fdisplay(ftr_main, "%04X", u_main.A);
    if( !u_snd.m1_n  && m1a_l && u_snd.iorq_n  ) $fdisplay(ftr_snd,  "%04X", u_snd.A);
end
`endif

`ifdef SIMULATION
// frame-by-frame activity report for the simulation log
reg [15:0] dbg_pal, dbg_vram, dbg_obj, dbg_snd;
reg        dbg_lvbl, dbg_m1l;
integer    dbg_frame=0, dbg_m1=0, dbg_cen=0;
always @(posedge clk) begin
    dbg_lvbl <= LVBL;
    if( pal_we  && cpu_cen ) dbg_pal  <= dbg_pal  + 1'd1;
    if( vram_we && cpu_cen ) dbg_vram <= dbg_vram + 1'd1;
    if( oram_we && cpu_cen ) dbg_obj  <= dbg_obj  + 1'd1;
    if( snd_wr ) dbg_snd <= dbg_snd + 1'd1;
    dbg_m1l <= u_main.m1_n;
    if( !u_main.m1_n && dbg_m1l ) dbg_m1 <= dbg_m1 + 1;
    if( cpu_cen ) dbg_cen <= dbg_cen + 1;
    if( !LVBL && dbg_lvbl ) begin
        $display("F%0d mcu %03x p0 %02x p3 %02x bp %b | main %04x sub %04x snd %04x pal %0d vram %0d obj %0d sndw %0d sub_rstn %b m1 %0d cen %0d", dbg_frame, u_beast.u_mcu.rom_addr, u_beast.p0, u_beast.p3, u_beast.bpend,
            u_main.u_cpu.A, sub_a, u_snd.A, dbg_pal, dbg_vram, dbg_obj, dbg_snd, sub_rstn, dbg_m1, dbg_cen);
        dbg_frame <= dbg_frame + 1;
        dbg_pal <= 0; dbg_vram <= 0; dbg_obj <= 0; dbg_m1 <= 0; dbg_cen <= 0;
    end
end
`endif

endmodule
