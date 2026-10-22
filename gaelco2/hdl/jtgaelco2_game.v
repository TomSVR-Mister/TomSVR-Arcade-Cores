/*  This file is part of JTGAELCO2.
    SPDX-License-Identifier: GPL-3.0-or-later

    Gaelco 2 boards (MAME gaelco2.cpp, GAE1 video/sound chip): Maniac Square first.
    CPU, bus, RAM and inputs: JTFRAME (jotego) as in our JTWRALLY.
    Video pipeline and GAE1 sound: aligator_* modules from jlrh's gaelco-fpga (GPLv3),
    https://github.com/jlrh/gaelco-fpga (Alligator Hunt core), with small TomSVR changes.

    Download layout (after the 8-byte header):
      0x000000  68000 program (up to 1 MB)
      0x100000  graphics: 32-bit words, word a = { plane2[a], plane3[a], plane0[a], plane1[a] }
                (bytes 3..0), as the jlrh Alligator Hunt MRA builds it
    Header (MRA rom index 0, first 8 bytes):
      byte 0 bits 2-0: plane size = 0x80000 << n bytes (0 Maniac Square, 3 Alligator Hunt)
      byte 1: planes 2 and 3 read as zero from word (byte1 << 16) up; 0 = never
      byte 2: sound bank map, 2 bits per bank: plane used by bank 0..3 (MAME set_bank_offsets) */

module jtgaelco2_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire        clkg = clk48;
reg   [2:0] pxdiv = 0;
reg   [2:0] psize;
reg   [7:0] hilim, bank_map;

always @(posedge clkg) pxdiv <= pxdiv + 3'd1;
assign pxl_cen  = pxdiv==0;
assign pxl2_cen = pxdiv==0 || pxdiv==4;
assign dip_flip   = 1'b0;
assign debug_view = 8'd0;

`ifdef SIMULATION
// without -load the header is not downloaded: Maniac Square values
initial begin psize = 0; hilim = 8'h02; bank_map = 8'h04; end
`endif

always @(posedge clk) if( header && prog_we ) begin
    if( prog_addr[2:0]==0 ) psize    <= prog_data[2:0];
    if( prog_addr[2:0]==1 ) hilim    <= prog_data;
    if( prog_addr[2:0]==2 ) bank_map <= prog_data;
end

// word address mask for one plane
wire [21:0] amask = { 3'd0, {19{1'b1}} } << psize | 22'h7ffff;

// ---------------- CPU
wire [15:0] cpu_dout, vram_dout, pal_dout, snd_dout, wram_dout, shram_dout;
wire [15:1] cpu_addr;
wire [ 1:0] cpu_dsn;
wire        cpu_we, vram_cs, pal_cs, sreg_cs, wram_cs, shram_cs, vblank_irq;
wire [15:0] vreg0, vreg1, vreg2;
reg         sreg_cs_l;

jtgaelco2_main u_main(
    .clk        ( clkg      ),
    .rst        ( rst       ),
    .lvbl       ( ~vblank_irq ),     // jtframe_edge catches the one-clock pulse
    .main_addr  ( main_addr ),
    .main_cs    ( main_cs   ),
    .main_data  ( main_data ),
    .main_ok    ( main_ok   ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_addr   ( cpu_addr  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_we     ( cpu_we    ),
    .vram_cs    ( vram_cs   ),
    .pal_cs     ( pal_cs    ),
    .snd_cs     ( sreg_cs   ),
    .vram_dout  ( vram_dout ),
    .pal_dout   ( pal_dout  ),
    .snd_dout   ( snd_dout  ),
    .vreg0      ( vreg0     ),
    .vreg1      ( vreg1     ),
    .vreg2      ( vreg2     ),
    .wram_cs    ( wram_cs   ),
    .shram_cs   ( shram_cs  ),
    .wram_dout  ( wram_dout ),
    .shram_dout ( shram_dout),
    .dipsw      ( dipsw[15:0] ),
    .joystick1  ( joystick1[6:0] ),
    .joystick2  ( joystick2[6:0] ),
    .coin       ( coin[1:0] ),
    .start      ( cab_1p[1:0] ),
    .service    ( service   ),
    .dip_test   ( dip_test  ),
    .dip_pause  ( dip_pause )
);

// work RAM and shared RAM (32 kB each)
wire [1:0] wwe = (wram_cs  & cpu_we) ? cpu_dsn : 2'b0;
wire [1:0] swe = (shram_cs & cpu_we) ? cpu_dsn : 2'b0;
jtframe_ram16 #(.AW(14)) u_wram(
    .clk( clkg ), .data( cpu_dout ), .addr( cpu_addr[14:1] ), .we( wwe ), .q( wram_dout )
);
jtframe_ram16 #(.AW(14)) u_shram(
    .clk( clkg ), .data( cpu_dout ), .addr( cpu_addr[14:1] ), .we( swe ), .q( shram_dout )
);

// ---------------- video memories
wire [13:0] tp0_idx, tp1_idx;
wire [31:0] tp0_q, tp1_q;
wire [14:0] wrd_a, spr_a;
wire [15:0] wrd_q, spr_q, pal_q;
wire [11:0] pal_a;

jtgaelco2_vmem u_vmem(
    .clk        ( clkg      ),
    .clk96      ( clk96     ),
    .cpu_addr   ( cpu_addr  ),
    .cpu_dsn    ( cpu_dsn   ),
    .cpu_we     ( cpu_we    ),
    .cpu_dout   ( cpu_dout  ),
    .vram_cs    ( vram_cs   ),
    .pal_cs     ( pal_cs    ),
    .vram_dout  ( vram_dout ),
    .pal_dout   ( pal_dout  ),
    .tp0_idx    ( tp0_idx   ),
    .tp0_q      ( tp0_q     ),
    .tp1_idx    ( tp1_idx   ),
    .tp1_q      ( tp1_q     ),
    .wrd_a      ( wrd_a     ),
    .wrd_q      ( wrd_q     ),
    .spr_a      ( spr_a     ),
    .spr_q      ( spr_q     ),
    .pal_a      ( pal_a     ),
    .pal_q      ( pal_q     )
);

// ---------------- video (jlrh)
wire [21:0] rom_a0, rom_a1, rom_as, rom_asnd;
wire [ 4:0] r5, g5, b5;
wire        hs_w, vs_w, hb_w, vb_w, de_w;

// planes 2-3 beyond their ROM size read as zero (Maniac Square: 128 kB ROMs in 512 kB planes)
function [31:0] hicut(input [31:0] d, input [21:0] a);
    hicut = (hilim!=0 && a[21:16] >= hilim[5:0]) ? { 16'd0, d[15:0] } : d;
endfunction

aligator_video_top u_video(
    .clk        ( clkg      ),
    .clk96      ( clk96     ),
    .rst        ( rst       ),
    .ce_pix     ( pxl_cen   ),
    .vreg0      ( vreg0     ),
    .vreg1      ( vreg1     ),
    .vreg2      ( vreg2     ),
    .tp0_idx    ( tp0_idx   ), .tp0_q( tp0_q ),
    .tp1_idx    ( tp1_idx   ), .tp1_q( tp1_q ),
    .wrd_a      ( wrd_a     ), .wrd_q( wrd_q ),
    .spr_a      ( spr_a     ), .spr_q( spr_q ),
    .pal_a      ( pal_a     ), .pal_q( pal_q ),
    .rom_a0     ( rom_a0    ), .gfx0_data( hicut(gfx0_data, gfx0_addr) ), .gfx0_ok( gfx0_ok ),
    .rom_a1     ( rom_a1    ), .gfx1_data( hicut(gfx1_data, gfx1_addr) ), .gfx1_ok( gfx1_ok ),
    .rom_as     ( rom_as    ), .gfxs_data( hicut(gfxs_data, gfxs_addr) ), .gfxs_ok( gfxs_ok ),
    .vga_r      ( r5        ),
    .vga_g      ( g5        ),
    .vga_b      ( b5        ),
    .hsync      ( hs_w      ),
    .vsync      ( vs_w      ),
    .hblank     ( hb_w      ),
    .vblank     ( vb_w      ),
    .de         ( de_w      ),
    .vblank_irq ( vblank_irq )
);

assign gfx0_addr = rom_a0 & amask;  assign gfx0_cs = 1'b1;
assign gfx1_addr = rom_a1 & amask;  assign gfx1_cs = 1'b1;
assign gfxs_addr = rom_as & amask;  assign gfxs_cs = 1'b1;

assign red   = r5;
assign green = g5;
assign blue  = b5;
assign HS    = hs_w;
assign VS    = vs_w;
assign LHBL  = ~hb_w;
assign LVBL  = ~vb_w;

// ---------------- sound (jlrh GAE1 sound, register writes as one-clock pulses)
wire signed [15:0] snd_l, snd_r;
wire snd_we = sreg_cs & cpu_we & ~sreg_cs_l;
always @(posedge clkg) sreg_cs_l <= sreg_cs;

aligator_gae1_sound u_snd(
    .clk        ( clkg      ),
    .rst        ( rst       ),
    .cs_sound   ( sreg_cs   ),
    .cpu_aw     ( cpu_addr[7:1] ),
    .cpu_we     ( snd_we    ),
    .cpu_uds    ( cpu_dsn[1]),
    .cpu_lds    ( cpu_dsn[0]),
    .cpu_wdata  ( cpu_dout  ),
    .cpu_rdata  ( snd_dout  ),
    .bank_map   ( bank_map  ),
    .rom_addr   ( rom_asnd  ),
    .rom_cs     ( snd_cs    ),
    .rom_data   ( snd_data  ),
    .rom_ok     ( snd_ok    ),
    .snd_l      ( snd_l     ),
    .snd_r      ( snd_r     ),
    .sample     ( sample    )
);
assign snd_addr  = rom_asnd & amask;
assign snd_left  = snd_l;
assign snd_right = snd_r;

`ifdef SIMULATION
integer nv=0, np=0, nf=0, nfe=0, cyc=0, pfirst=-1, plast=-1, pn=0; reg lvbl_l=0, mok_l=0, pw_l=0;
// palette write timing relative to the vblank IRQ (clk48 cycles; one frame = 812k)
always @(posedge clkg) begin
    pw_l <= pal_cs & cpu_we;
    if( vblank_irq ) begin
        if( nf>=380 && nf<=470 && pn>0 ) $display("PALT frame %0d writes %0d first %0d last %0d", nf, pn, pfirst, plast);
        cyc <= 0; pn <= 0; pfirst <= -1; plast <= -1;
    end else begin
        cyc <= cyc + 1;
        if( pal_cs & cpu_we & ~pw_l ) begin pn <= pn+1; if( pfirst<0 ) pfirst <= cyc; plast <= cyc; end
    end
end
always @(posedge clkg) begin
    mok_l <= main_ok & main_cs;
    if( main_cs & main_ok & ~mok_l && nfe<120 ) begin
        nfe <= nfe+1;
        $display("FETCH %h -> %h", {main_addr,1'b0}, main_data);
    end
end
always @(posedge clkg) begin
    lvbl_l <= LVBL;
    if( vram_cs & cpu_we ) nv <= nv+1;
    if( pal_cs  & cpu_we ) np <= np+1;
    if( lvbl_l & ~LVBL ) begin
        nf <= nf+1;
        if( nf<40 || nf%50==0 ) $display("G2 frame %0d pc~%h vram_wr=%0d pal_wr=%0d vregs=%h %h %h", nf,
            {main_addr,1'b0}, nv, np, vreg0, vreg1, vreg2);
    end
end
`endif
endmodule
