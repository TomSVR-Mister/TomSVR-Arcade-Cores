/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * ESD 16-bit main board (MAME esd16.cpp): 68000 at 16 MHz, IRQ 6 at vblank (hold).
 * Address pages (bits 23-16) per memory map:
 *              RAM     palette sprites tilemaps attr   I/O    platform
 *   hedpanic   10      80      90      a0/a2    b0     c0     d00008
 *   mchampdx   20      40      60      30/32    70     50     d00008
 *   tangtang   70      10      20      30/32    40     50     600008
 *   multchmp   10      20      30      40/42    50     60     -
 *   jumppop    12+1a   14      16      30/32    38     18     -
 * I/O: 2 P1/P2, 4 SYSTEM, 6 DSW (multchmp, jumppop) or EEPROM data out in bit 15, 8 tilemap 0 colour,
 *   d sound latch (low byte), e EEPROM (bit 0 CS, bit 1 CLK, bit 2 DI).
 * Attr: 0/2 tilemap 0 scroll x/y, 4/6 tilemap 1 scroll x/y, 8/a platform x/y, e layer size (bit 0/1: 16x16 tiles).
 * The platform port writes a tilemap 1 word at platform_x + 64 * platform_y (Head Panic protection). */

module jtesd_main(
    input              rst,
    input              clk,
    input              lvbl,
    input              dip_pause,
    input       [ 2:0] gmap,

    input       [15:0] inputs, system, dipsw,

    output      [15:0] cpu_dout,
    output      [18:1] rom_addr,
    output reg         rom_cs,
    input       [15:0] rom_data,
    input              rom_ok,
    output      [15:1] wram_addr,
    output      [ 1:0] wram_we,
    input       [15:0] wram_dout,
    output      [11:1] pal_addr,
    output      [ 1:0] pal_we,
    input       [15:0] pal_dout,
    output      [10:1] objram_addr,
    output      [ 1:0] objram_we,
    input       [15:0] objram_dout,
    output      [13:1] vram0_addr,
    output      [ 1:0] vram0_we,
    input       [15:0] vram0_dout,
    output      [13:1] vram1_addr,
    output      [ 1:0] vram1_we,
    output      [15:0] vram1_din,
    input       [15:0] vram1_dout,

    output reg  [ 9:0] scr0x, scr0y, scr1x, scr1y,
    output reg  [ 1:0] lsize,
    output reg  [ 1:0] col0,
    output reg  [ 7:0] snd_latch,
    output reg         snd_wr,

    input              nvbe,
    input       [ 7:0] prog_addr,
    input       [ 7:0] prog_data,
    input              prog_we,
    output      [ 7:0] prog_din
);

`ifndef NOMAIN
wire [23:1] A;
wire [ 2:0] fc;
wire        as_n, lds_n, uds_n, wr_n, dtack_n, vpa_n, bus_n;
wire        cpu_cen, cpu_cenb, int_ack, bus_busy;
wire [ 1:0] dsn, wen;
wire [ 2:0] ipl_n;
wire [ 7:0] pg = A[23:16];
reg  [15:0] cpu_din;
reg  [ 7:0] p_ram, p_pal, p_spr, p_vram, p_attr, p_io;
reg  [23:0] a_plat;
reg         irq_n;
reg         wram_cs, pal_cs, objram_cs, io_cs, attr_cs, vram0_cs, vram1_cs, plat_cs;
reg  [12:0] plat_x, plat_y;
reg         ee_cs, ee_clk, ee_di;
wire        ee_do;
wire        eeprom = gmap < 3;

assign dsn        = { uds_n, lds_n };
assign bus_n      = as_n | (lds_n & uds_n);
assign wen        = {2{~wr_n}} & ~dsn;
assign rom_addr   = A[18:1];
assign wram_addr  = gmap==4 ? { A[19], A[19] ? A[14:1] : { 1'b0, A[13:1] } } : A[15:1];
assign pal_addr   = A[11:1];
assign objram_addr= A[10:1];
assign vram0_addr = A[13:1];
assign vram1_addr = plat_cs ? plat_x + { plat_y[6:0], 6'd0 } : A[13:1];
assign vram1_din  = cpu_dout;
assign wram_we    = wram_cs   ? wen : 2'b00;
assign pal_we     = pal_cs    ? wen : 2'b00;
assign objram_we  = objram_cs ? wen : 2'b00;
assign vram0_we   = vram0_cs  ? wen : 2'b00;
assign vram1_we   = vram1_cs || plat_cs ? wen : 2'b00;
assign int_ack    = fc == 3'b111 && !as_n;
assign vpa_n      = !int_ack;
assign ipl_n      = irq_n ? 3'b111 : 3'b001;     // level 6
assign bus_busy   = rom_cs && !rom_ok;

always @* begin
    case( gmap )
        0: begin p_ram=8'h10; p_pal=8'h80; p_spr=8'h90; p_vram=8'ha0; p_attr=8'hb0; p_io=8'hc0; a_plat=24'hd00008; end
        1: begin p_ram=8'h20; p_pal=8'h40; p_spr=8'h60; p_vram=8'h30; p_attr=8'h70; p_io=8'h50; a_plat=24'hd00008; end
        2: begin p_ram=8'h70; p_pal=8'h10; p_spr=8'h20; p_vram=8'h30; p_attr=8'h40; p_io=8'h50; a_plat=24'h600008; end
        3: begin p_ram=8'h10; p_pal=8'h20; p_spr=8'h30; p_vram=8'h40; p_attr=8'h50; p_io=8'h60; a_plat=24'hffffff; end
        default: begin p_ram=8'h12; p_pal=8'h14; p_spr=8'h16; p_vram=8'h30; p_attr=8'h38; p_io=8'h18; a_plat=24'hffffff; end
    endcase
end

always @* begin
    rom_cs = 0; wram_cs = 0; pal_cs = 0; objram_cs = 0; io_cs = 0; attr_cs = 0; vram0_cs = 0; vram1_cs = 0; plat_cs = 0;
    if( !bus_n ) begin
        rom_cs    = A[23:19] == 0;
        wram_cs   = gmap==4 ? (pg==8'h12 && A[15:14]==0) || (pg==8'h1a && !A[15]) : pg==p_ram;
        pal_cs    = pg==p_pal  && A[15:12]==0;
        objram_cs = pg==p_spr  && A[15:12]==0;
        vram0_cs  = pg==p_vram && !A[15];
        vram1_cs  = pg==(p_vram+8'd2) && !A[15];
        attr_cs   = pg==p_attr && A[15:4]==0;
        io_cs     = pg==p_io   && A[15:4]==0;
        plat_cs   = { A, 1'b0 }==a_plat;
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs    ? rom_data    :
               wram_cs   ? wram_dout   :
               pal_cs    ? pal_dout    :
               objram_cs ? objram_dout :
               vram0_cs  ? vram0_dout  :
               vram1_cs  ? vram1_dout  :
               io_cs     ? ( A[3:1]==1 ? inputs :
                             A[3:1]==2 ? system :
                             A[3:1]==3 ? (eeprom ? { ee_do, 15'd0 } : dipsw) : 16'hffff ) :
               16'hffff;
end

reg wr_l;
always @(posedge clk) begin
    snd_wr <= 0;
    wr_l   <= io_cs && !wr_n;
    if( rst ) begin
        scr0x <= 0; scr0y <= 0; scr1x <= 0; scr1y <= 0; lsize <= 0; col0 <= 0;
        plat_x <= 0; plat_y <= 0; snd_latch <= 0;
        ee_cs <= 0; ee_clk <= 0; ee_di <= 0;
    end else begin
        if( attr_cs && !wr_n ) case( A[3:1] )
            0: scr0x  <= cpu_dout[9:0];
            1: scr0y  <= cpu_dout[9:0];
            2: scr1x  <= cpu_dout[9:0];
            3: scr1y  <= cpu_dout[9:0];
            4: plat_x <= cpu_dout[12:0];
            5: plat_y <= cpu_dout[12:0];
            7: lsize  <= cpu_dout[1:0];
            default:;
        endcase
        if( io_cs && !wr_n && !wr_l ) case( A[3:1] )
            4: col0 <= cpu_dout[1:0];
            6: if( !lds_n ) begin snd_latch <= cpu_dout[7:0]; snd_wr <= 1; end
            7: if( eeprom ) begin
                if( !lds_n ) { ee_di, ee_clk, ee_cs } <= cpu_dout[2:0];
                else         { ee_di, ee_clk, ee_cs } <= cpu_dout[10:8];
            end
            default:;
        endcase
    end
end

`ifdef SIMULATION
reg as_l=1;
always @(posedge clk) begin
    as_l <= as_n;
    if( !as_n && as_l ) begin
        if( (io_cs || plat_cs) && !wr_n && A[3:1]!=6 )
            $display("68k %06X W dout=%04X", {A,1'b0}, cpu_dout);
    end
end
`endif

// IRQ 6 asserted at the start of vblank, cleared on acknowledge
reg lvbl_l;
always @(posedge clk) begin
    lvbl_l <= lvbl;
    if( rst ) irq_n <= 1;
    else begin
        if( !lvbl && lvbl_l ) irq_n <= 0;
        if( int_ack ) irq_n <= 1;
    end
end

// EEPROM default / save (MiSTer NVRAM, index 2). jt9346_16b8b takes the low byte at the even address.
// nvbe: the file holds big-endian words, so the pair is written swapped once the odd byte arrives.
wire [7:0] src_addr, src_din;
wire       src_we;
reg  [7:0] nv_addr, nv_din, nv_even;
reg        nv_we;
reg  [1:0] nv_seq;
`ifdef SIMULATION
// the simulator skips the NVRAM download: nvram.hex (128 bytes, file order) is written during reset
reg [7:0] nvsim[0:127]; reg [9:0] nvcnt=0;
initial begin : nvinit integer k; for(k=0;k<128;k=k+1) nvsim[k]=8'hff; $readmemh("nvram.hex", nvsim); end
always @(posedge clk) if( rst && !nvcnt[9] ) nvcnt <= nvcnt + 1'd1;
assign src_we   = (rst && !nvcnt[9] && nvcnt[1:0]==3) | prog_we;
assign src_addr = rst ? { 1'b0, nvcnt[8:2] } : prog_addr;
assign src_din  = rst ? nvsim[nvcnt[8:2]] : prog_data;
`else
assign src_we   = prog_we;
assign src_addr = prog_addr;
assign src_din  = prog_data;
`endif

always @(posedge clk) begin
    nv_we <= 0;
    if( nv_seq==0 ) begin
        nv_addr <= prog_addr ^ { 7'd0, nvbe };      // read back
        if( src_we ) begin
            if( !nvbe ) begin
                nv_addr <= src_addr; nv_din <= src_din; nv_we <= 1;
            end else if( !src_addr[0] ) nv_even <= src_din;
            else begin
                nv_addr <= { src_addr[7:1], 1'b0 }; nv_din <= src_din; nv_we <= 1; nv_seq <= 1;
            end
        end
    end else begin
        nv_seq  <= 0;
        nv_addr <= nv_addr | 8'd1; nv_din <= nv_even; nv_we <= 1;
    end
end

// 93C46 in 16-bit mode, 128 bytes
jt9346_16b8b #(.DW(16),.AW(6)) u_eeprom(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .sclk       ( ee_clk    ),
    .sdi        ( ee_di     ),
    .sdo        ( ee_do     ),
    .scs        ( ee_cs     ),
    .dump_clk   ( clk       ),
    .dump_addr  ( nv_addr   ),
    .dump_we    ( nv_we     ),
    .dump_din   ( nv_din    ),
    .dump_dout  ( prog_din  ),
    .dump_flag  (           ),
    .dump_clr   ( 1'b0      )
);

jtframe_m68k u_cpu(
    .clk     ( clk       ),
    .rst     ( rst       ),
    .cpu_cen ( cpu_cen   ),
    .cpu_cenb( cpu_cenb  ),
    .BERRn   ( 1'b1      ),
    .VPAn    ( vpa_n     ),
    .BGACKn  ( 1'b1      ),
    .HALTn   ( dip_pause ),
    .RESETn  (           ),
    .eab     ( A         ),
    .ASn     ( as_n      ),
    .LDSn    ( lds_n     ),
    .UDSn    ( uds_n     ),
    .eRWn    ( wr_n      ),
    .DTACKn  ( dtack_n   ),
    .iEdb    ( cpu_din   ),
    .oEdb    ( cpu_dout  ),
    .BRn     ( 1'b1      ),
    .BGn     (           ),
    .IPLn    ( ipl_n     ),
    .FC      ( fc        )
);

// 16 MHz from 48 MHz
jtframe_68kdtack_cen u_dtack(
    .rst       ( rst      ),
    .clk       ( clk      ),
    .cpu_cen   ( cpu_cen  ),
    .cpu_cenb  ( cpu_cenb ),
    .bus_cs    ( rom_cs   ),
    .bus_busy  ( bus_busy ),
    .bus_legit ( 1'b0     ),
    .bus_ack   ( 1'b0     ),
    .ASn       ( as_n     ),
    .DSn       ( dsn      ),
    .num       ( 4'd1     ),
    .den       ( 5'd3     ),
    .DTACKn    ( dtack_n  ),
    .wait2     ( 1'b0     ),
    .wait3     ( 1'b0     ),
    .fave      (          ),
    .fworst    (          )
);
`else
initial begin rom_cs=0; scr0x=0; scr0y=0; scr1x=0; scr1y=0; lsize=0; col0=0; snd_latch=0; snd_wr=0; end
assign cpu_dout=0, rom_addr=0, wram_addr=0, wram_we=0, pal_addr=0, pal_we=0, objram_addr=0, objram_we=0,
       vram0_addr=0, vram0_we=0, vram1_addr=0, vram1_we=0, vram1_din=0, prog_din=0;
`endif

endmodule
