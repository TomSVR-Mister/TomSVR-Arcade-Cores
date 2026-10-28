/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Pipe Dream / Hatris main CPU (MAME vsystem/pipedrm.cpp hatris_state::main_map / main_portmap): Z80 at 6 MHz,
 * INT at the start of vertical blanking, held until acknowledged (irq0_line_hold).
 *   0000-7fff ROM   8000-9fff RAM   a000-bfff ROM bank (8 kB pages from maincpu 10000)   c000-cfff palette RAM
 *   (pipedrm: cc00-cfff is sprite RAM and never reaches the palette)   d000-ffff tile map RAM of the selected layer
 *   I/O 10/11 GGA data/address   20 P1 / sound latch   21 P2 / bank + video control   22-25 scroll registers
 *   22 DSW1   23 DSW2   24 SYSTEM   25 sound latch pending */
module jtpipedrm_main(
    input              rst,
    input              clk,
    input              cen,
    input              lvbl,
    input              dip_pause,
    input              hatris,
    input       [ 7:0] sys, p1, p2, dsw1, dsw2,
    output      [ 7:0] cpu_dout,
    output      [15:0] cpu_addr,
    output      [16:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    // video memories
    output             vram0_we, vram1_we, pall_we, palh_we, objl_we, objh_we,
    input       [ 7:0] vram0_dout, vram1_dout, pall_dout, palh_dout,
    // GGA
    output             gga_we,
    // video control
    output reg         flip,
    output reg  [ 8:0] scrx0, scry0, scrx1, scry1,
    // sound
    output reg  [ 7:0] snd_latch,
    output reg         snd_wr,
    input              snd_pending
);

`ifndef NOMAIN
wire [15:0] A;
wire [ 7:0] ram_dout;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n;
reg  [ 7:0] din, gfxreg;
reg  [ 2:0] bank;
reg         ram_cs, pal_cs, vid_cs, irq, lvbl_l, rstn, iow_l;
wire        mem   = !mreq_n && rfsh_n;
wire        io    = !iorq_n && m1_n;
wire        iow   = io && !wr_n;
wire        iowr  = iow && !iow_l;
wire        vsel  = ~gfxreg[1];          // fromance_gfxreg_w: selected videoram = (~data >> 1) & 1
wire        spr_a = !hatris && A[11:10]==2'b11;   // cc00-cfff on pipedrm

assign cpu_addr = A;
assign rom_addr = A[15] ? { 1'b1, bank, A[12:0] } : { 2'd0, A[14:0] };
assign vram0_we = vid_cs && !vsel && !wr_n;
assign vram1_we = vid_cs &&  vsel && !wr_n;
// pipedrm's sprite RAM sits on top of palette entries 600-7ff; init_pipedrm installs plain RAM there, so those
// entries keep their power-on (black) colour. Writing the copy keeps the CPU read-back simple.
assign pall_we  = pal_cs && !A[0] && !wr_n;
assign palh_we  = pal_cs &&  A[0] && !wr_n;
assign objl_we  = pal_cs && spr_a && !A[0] && !wr_n;
assign objh_we  = pal_cs && spr_a &&  A[0] && !wr_n;
assign gga_we   = iowr && A[7:1]==7'h08;   // 10 data, 11 address latch

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && (!A[15] || A[15:13]==3'b101);
    ram_cs = mem && A[15:13]==3'b100;
    pal_cs = mem && A[15:12]==4'hc;
    vid_cs = mem && A[15:12]>=4'hd;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout :
           pal_cs ? (A[0] ? palh_dout : pall_dout) :
           vid_cs ? (vsel ? vram1_dout : vram0_dout) :
           io ? ( A[7:0]==8'h20 ? p1  : A[7:0]==8'h21 ? p2   :
                  A[7:0]==8'h22 ? dsw1: A[7:0]==8'h23 ? dsw2 :
                  A[7:0]==8'h24 ? sys : A[7:0]==8'h25 ? { 7'd0, snd_pending } : 8'hff ) : 8'hff;
end

// fromance_scroll_w: the result is computed at write time from the current flip and gfxreg bits.
// Not flipped: x - 0x1f7, y - 0xf9. Flipped: x - scrollx_ofs, y - scrolly_ofs. video_start sets per-game values,
// but machine_reset runs after it and leaves 0x159 / 0x10 for both games, so those are what MAME uses.
wire [8:0] sx_ofs = flip ? 9'h159 : 9'h1f7;
wire [8:0] sy_ofs = flip ? 9'h010 : 9'h0f9;
wire [8:0] wr_x1  = { gfxreg[3], cpu_dout } - sx_ofs;
wire [8:0] wr_y1  = { gfxreg[2], cpu_dout } - sy_ofs;
wire [8:0] wr_x0  = { gfxreg[5], cpu_dout } - sx_ofs;
wire [8:0] wr_y0  = { gfxreg[4], cpu_dout } - sy_ofs;

always @(posedge clk) begin
    snd_wr <= 0;
    iow_l  <= iow;
    lvbl_l <= lvbl;
    if( rst ) begin
        bank <= 0; gfxreg <= 0; flip <= 0; snd_latch <= 0; irq <= 0;
        scrx0 <= 0; scry0 <= 0; scrx1 <= 0; scry1 <= 0;
    end else begin
        if( iowr ) case( A[7:0] )
            8'h20: begin snd_latch <= cpu_dout; snd_wr <= 1; end
            8'h21: if( hatris ) begin   // init_hatris: port 21 goes straight to fromance_gfxreg_w
                gfxreg <= cpu_dout;
                flip   <= cpu_dout[0];
            end else begin              // pipedrm bankswitch_w: D6 flip, D3 videoram select, D2-D0 ROM bank
                bank   <= cpu_dout[2:0];
                gfxreg <= { 6'd0, ~cpu_dout[3], cpu_dout[6] };
                flip   <= cpu_dout[6];
            end
            8'h22: scrx1 <= wr_x1;
            8'h23: scry1 <= wr_y1;
            8'h24: scrx0 <= wr_x0;
            8'h25: scry0 <= wr_y0;
            default:;
        endcase
        if( !lvbl && lvbl_l && dip_pause ) irq <= 1;
        if( !m1_n && !iorq_n ) irq <= 0;
    end
end

jtframe_sysz80 #(.RAM_AW(13)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen         ),
    .cpu_cen    (             ),
    .int_n      ( ~irq        ),
    .nmi_n      ( 1'b1        ),
    .busrq_n    ( 1'b1        ),
    .m1_n       ( m1_n        ),
    .mreq_n     ( mreq_n      ),
    .iorq_n     ( iorq_n      ),
    .rd_n       ( rd_n        ),
    .wr_n       ( wr_n        ),
    .rfsh_n     ( rfsh_n      ),
    .halt_n     (             ),
    .busak_n    (             ),
    .A          ( A           ),
    .cpu_din    ( din         ),
    .cpu_dout   ( cpu_dout    ),
    .ram_dout   ( ram_dout    ),
    .ram_cs     ( ram_cs      ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( rom_ok      )
);
`else
initial begin rom_cs=0; snd_latch=0; snd_wr=0; flip=0; scrx0=0; scry0=0; scrx1=0; scry1=0; end
assign cpu_dout=0, cpu_addr=0, rom_addr=0, vram0_we=0, vram1_we=0, pall_we=0, palh_we=0, objl_we=0, objh_we=0,
       gga_we=0;
`endif
endmodule
