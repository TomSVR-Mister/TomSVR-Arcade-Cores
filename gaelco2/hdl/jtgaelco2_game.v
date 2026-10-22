/*  This file is part of JTGAELCO2.
    SPDX-License-Identifier: GPL-3.0-or-later

    Gaelco 2 boards (MAME gaelco2.cpp, GAE1 video/sound chip): Maniac Square first.
    CPU, bus, RAM and inputs: JTFRAME (jotego) as in our JTWRALLY.
    Video pipeline and GAE1 sound: aligator_* modules from jlrh's gaelco-fpga (GPLv3),
    https://github.com/jlrh/gaelco-fpga (Alligator Hunt core), with small TomSVR changes.

    Download layout (after the 8-byte header):
      0x000000  68000 program (up to 1 MB)
      0x100000  graphics: 32-bit words, word a = { plane2[a], plane3[a], plane0[a], plane1[a] }
                (bytes 3..0), as the jlrh Alligator Hunt MRA builds it (SDRAM bank 1, up to 16 MB)
      0x1100000 fifth plane, one byte per word address (5 bpp games only; SDRAM bank 2, up to 4 MB)
      0x1500000 DS5002FP program (protected sets only; BRAM)
    Header (MRA rom index 0, first 8 bytes):
      byte 0 bits 2-0: plane size = 0x80000 << n bytes (0 Maniac Square, 3 Alligator Hunt)
      byte 1: planes 2 and 3 read as zero from word (byte1 << 16) up; 0 = never
      byte 2: sound bank map, 2 bits per bank: plane used by bank 0..3 (MAME set_bank_offsets)
      byte 3: bit 0 DS5002FP protection CPU present; bit 1 Snow Board board (map, 15 MHz, EEPROM, protection);
              bit 2 384-pixel wide screen; bit 3 fifth graphics plane present (5 bpp)
      byte 4: planes 0 and 1 read as zero from word (byte4 << 16) up; 0 = never
      byte 5: the fifth plane reads as zero from word (byte5 << 16) up; 0 = never */

module jtgaelco2_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire        clkg = clk48;
reg   [2:0] pxdiv = 0;
reg   [2:0] psize;
reg   [7:0] hilim, lolim, p4lim, bank_map;
reg         mcu_en, snow, wide, bpp5;
reg   [1:0] mcu_cnt = 0;

// pixel clock 48/8 = 6 MHz (384-pixel lines); wide screen 48/7 = 6.86 MHz (440-pixel lines, same 15.6 kHz)
always @(posedge clkg) pxdiv <= (wide && pxdiv==6) ? 3'd0 : pxdiv + 3'd1;
assign pxl_cen  = pxdiv==0;
assign pxl2_cen = pxdiv==0 || pxdiv==4;
assign dip_flip   = 1'b0;
assign debug_view = 8'd0;

`ifdef SIMULATION
// without -load the header is not downloaded: Maniac Square values
initial begin psize = 0; hilim = 8'h02; lolim = 0; p4lim = 0; bank_map = 8'h04;
    mcu_en = 0; snow = 0; wide = 0; bpp5 = 0;
`ifdef SIM_SNOW
    psize = 3; hilim = 8'h20; lolim = 8'h30; p4lim = 8'h20; bank_map = 8'h04; snow = 1; wide = 1; bpp5 = 1;
`endif
`ifdef SIM_MCU
    mcu_en = 1;     // protected sets: jtsim -d SIM_MCU, mcu.bin in the sim folder
`endif
end
`endif

always @(posedge clk) if( header && prog_we ) begin
    if( prog_addr[2:0]==0 ) psize    <= prog_data[2:0];
    if( prog_addr[2:0]==1 ) hilim    <= prog_data;
    if( prog_addr[2:0]==2 ) bank_map <= prog_data;
    if( prog_addr[2:0]==3 ) { bpp5, wide, snow, mcu_en } <= prog_data[3:0];
    if( prog_addr[2:0]==4 ) lolim    <= prog_data;
    if( prog_addr[2:0]==5 ) p4lim    <= prog_data;
end

// word address mask for one plane
wire [21:0] amask = { 3'd0, {19{1'b1}} } << psize | 22'h7ffff;

// ---------------- CPU
wire [15:0] cpu_dout, vram_dout, pal_dout, snd_dout, wram_dout, shram_dout;
wire [15:1] cpu_addr;
wire [ 1:0] cpu_dsn;
wire        cpu_we, vram_cs, pal_cs, sreg_cs, wram_cs, shram_cs, vblank_irq, spr_done;
wire [15:0] vreg0, vreg1, vreg2;
reg         sreg_cs_l;

jtgaelco2_main u_main(
    .clk        ( clkg      ),
    .rst        ( rst       ),
    .lvbl       ( ~spr_done ),       // vblank IRQ once the sprite snapshot is taken
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
    .dip_pause  ( dip_pause ),
    .snow       ( snow      ),
    .xram_cs    ( xram_cs   ),
    .xram_dout  ( xram_dout ),
    .eep_di     ( eep_di    ),
    .eep_clk    ( eep_clk   ),
    .eep_cs     ( eep_cs    ),
    .eep_do     ( eep_do    )
);

// Snow Board: extra RAM at 212000-213FFF and the 93C66 EEPROM (256 x 16 bits) on the LS259 latch
wire        xram_cs, eep_di, eep_clk, eep_cs, eep_do;
wire [15:0] xram_dout;
wire [ 1:0] xwe = (xram_cs & cpu_we) ? cpu_dsn : 2'b0;
jtframe_ram16 #(.AW(12)) u_xram(
    .clk( clkg ), .data( cpu_dout ), .addr( cpu_addr[12:1] ), .we( xwe ), .q( xram_dout )
);
jt9346 #(.AW(8),.DW(16)) u_eeprom(
    .rst        ( rst       ),
    .clk        ( clkg      ),
    .sclk       ( eep_clk   ),
    .sdi        ( eep_di    ),
    .sdo        ( eep_do    ),
    .scs        ( eep_cs    ),
    .dump_clk   ( clkg      ),
    .dump_addr  ( 8'd0      ),
    .dump_we    ( 1'b0      ),
    .dump_din   ( 16'd0     ),
    .dump_dout  (           ),
    .dump_clr   ( 1'b0      ),
    .dump_flag  (           )
);

// work RAM and shared RAM (32 kB each)
wire [1:0] wwe = (wram_cs  & cpu_we) ? cpu_dsn : 2'b0;
wire [1:0] swe = (shram_cs & cpu_we) ? cpu_dsn : 2'b0;
jtframe_ram16 #(.AW(14)) u_wram(
    .clk( clkg ), .data( cpu_dout ), .addr( cpu_addr[14:1] ), .we( wwe ), .q( wram_dout )
);
// shared RAM: the DS5002FP sees it as bytes, big endian
wire [14:0] mcu_sa;
wire [ 7:0] mcu_sd;
wire        mcu_sw;
wire [15:0] sh_mcu_q;
jtframe_dual_ram16 #(.AW(14)) u_shram(
    .clk0( clkg ), .data0( cpu_dout ), .addr0( cpu_addr[14:1] ), .we0( swe ), .q0( shram_dout ),
    .clk1( clkg ), .data1( {mcu_sd, mcu_sd} ), .addr1( mcu_sa[14:1] ),
    .we1 ( mcu_sw ? (mcu_sa[0] ? 2'b01 : 2'b10) : 2'b00 ), .q1( sh_mcu_q )
);

// DS5002FP (protected sets only), 12 MHz
always @(posedge clkg) mcu_cnt <= mcu_cnt + 2'd1;

jtgaelco2_mcu u_mcu(
    .rst        ( rst | ~mcu_en ),
    .clk        ( clkg      ),
    .clk96      ( clk       ),
    .cen        ( mcu_cnt==0 ),
    .sh_addr    ( mcu_sa    ),
    .sh_dout    ( mcu_sd    ),
    .sh_wr      ( mcu_sw    ),
    .sh_din     ( mcu_sa[0] ? sh_mcu_q[7:0] : sh_mcu_q[15:8] ),
    .prog_addr  ( prog_addr[14:0] ),
    .prog_data  ( prog_data ),
    .prom_we    ( prom_we   )
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
    .vb_start   ( vblank_irq),
    .copy_done  ( spr_done  ),
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
// planes beyond their ROMs read as zero, as MAME's ROM_FILL (bytes 3-2 = planes 2-3, 1-0 = planes 0-1)
function [31:0] hicut(input [31:0] d, input [21:0] a);
    hicut = { (hilim!=0 && a[21:16] >= hilim[5:0]) ? 16'd0 : d[31:16],
              (lolim!=0 && a[21:16] >= lolim[5:0]) ? 16'd0 : d[15: 0] };
endfunction
function [7:0] p4cut(input [7:0] d, input [21:0] a);
    p4cut = (!bpp5 || (p4lim!=0 && a[21:16] >= p4lim[5:0])) ? 8'd0 : d;
endfunction
// a fetch is complete when both the 32-bit word and (5 bpp games) the fifth-plane byte are there
wire g0ok = gfx0_ok & (p4t0_ok | ~bpp5);
wire g1ok = gfx1_ok & (p4t1_ok | ~bpp5);
wire gsok = gfxs_ok & (p4s_ok  | ~bpp5);

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
    .rom_a0     ( rom_a0    ), .gfx0_data( hicut(gfx0_data, gfx0_addr) ), .gfx0_ok( g0ok ),
    .rom_a1     ( rom_a1    ), .gfx1_data( hicut(gfx1_data, gfx1_addr) ), .gfx1_ok( g1ok ),
    .rom_as     ( rom_as    ), .gfxs_data( hicut(gfxs_data, gfxs_addr) ), .gfxs_ok( gsok ),
    .p4_0       ( p4cut(p4t0_data, p4t0_addr) ),
    .p4_1       ( p4cut(p4t1_data, p4t1_addr) ),
    .p4_s       ( p4cut(p4s_data,  p4s_addr ) ),
    .wide       ( wide      ),
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
assign p4t0_addr = gfx0_addr;       assign p4t0_cs = bpp5;
assign p4t1_addr = gfx1_addr;       assign p4t1_cs = bpp5;
assign p4s_addr  = gfxs_addr;       assign p4s_cs  = bpp5;

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
integer nmw=0, nmr=0, nv=0, np=0, nf=0, nfe=0, cyc=0, pfirst=-1, plast=-1, pn=0; reg lvbl_l=0, mok_l=0, pw_l=0;
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
    if( mcu_sw ) nmw <= nmw+1;
    u_mcu.log_en <= nf>=1596 && nf<=1625;
    if( pal_cs  & cpu_we ) np <= np+1;
    if( lvbl_l & ~LVBL ) begin
        nf <= nf+1;
        if( nf<40 || nf%50==0 || (nf>=1100 && nf%20==0) ) $display("G2 frame %0d pc~%h vram_wr=%0d pal_wr=%0d vregs=%h %h %h mcu_shwr=%0d", nf,
            {main_addr,1'b0}, nv, np, vreg0, vreg1, vreg2, nmw);
    end
end
`endif
endmodule
