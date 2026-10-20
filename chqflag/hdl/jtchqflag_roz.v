/* SPDX-License-Identifier: GPL-3.0-or-later
   K051316 zoom/rotate layer for Chequered Flag. Copy of jotego's jt051316 (jtcores/cores/ajax) with the
   pixel formats Chequered Flag uses:
   BPP=4: code = {color[1:0], code}, pixel = {color[5:2], pen[3:0]}
   BPP=8: code = {color[3:0], code}, pixel = {color[4], pen[7:0]} */

module jtchqflag_roz(
    input          rst, clk, pxl_cen, cen24,
                   hs, vs, lhbl, lvbl,
    input   [10:0] cpu_addr,
    input   [ 7:0] cpu_dout,
    output  [ 7:0] cpu_din,
    output         cpu_ok,
    input          cpu_we,
    input          io_cs, vr_cs,
    output  [ 8:0] pxl,
    output         blnk_n,
    input          rvo, // enables blanking
    input          wrap, // repeats the tilemap outside its nominal bounds
    input   [ 8:0] hdump, vdump,

    output  [23:0] rom_addr,
    output         rom_cs,
    input          rom_ok,
    input   [ 7:0] rom_data,

    input   [10:0] ioctl_addr,
    input          ioctl_ram,
    output  [ 7:0] ioctl_din, mmr_dump
);
parameter [8:0] WR_STRT=9'h060, // Positions in wr_addr skipped during blanking
                VB_END =9'h10F, // Must be same as in vtimer
                RST_CT =9'h058, // starting value for wr_addr
                RD_DLY =9'h00B, // number of times to delay hdump
                RD_END =9'h19F; // Value of rd_addr when LHBL goes low
parameter BPP=4;
parameter MMRFILE="", RAM0FILE="", RAM1FILE="";

wire [23:0] xcnt, ycnt, gfx_addr;
wire [23:0] rom_source;
wire [15:0] scan_dout;
wire [ 9:0] vaddr;
wire [ 8:0] wr_addr, rd_addr;
wire [ 7:0] cpu_ram1, cpu_ram2;
wire [ 8:0] buf_din;
wire [ 2:1] we;
wire [15:0] xcnt0, xhstep, xvstep, ycnt0, yhstep, yvstep;
wire [12:0] ckbank;
wire [ 3:0] vf, hf;
reg  [ 2:0] oblk;
wire        rmrd_n, hflip_en, vflip_en;
wire        vflip, hflip, rst_cnt, pre_lvbl, duplicate;
reg         hs_l, hs_cen, cnt_cen, done;

assign we        ={cpu_addr[10],~cpu_addr[10]} & {2{cpu_we & vr_cs}};
assign cpu_din   = cpu_addr[10] ? cpu_ram2 : cpu_ram1;
assign ioctl_din = ioctl_addr[10] ? scan_dout[15:8] : scan_dout[7:0];
assign rom_source=  rmrd_n ? gfx_addr : { ckbank, cpu_addr };
assign rom_addr  =  BPP==4 ? {1'b0,rom_source[23:1]} : rom_source;
assign rom_cs    =  rmrd_n |  vr_cs;
assign cpu_ok    =  rmrd_n | ~vr_cs | rom_ok;
assign vflip     = vflip_en & scan_dout[15];
assign hflip     = hflip_en & scan_dout[14];
assign vf        = {4{vflip}} ^ ycnt[14:11];
assign hf        = {4{hflip}} ^ xcnt[14:11];
assign gfx_addr  = {scan_dout,vf,hf};
assign vaddr     = {ycnt[19:15],xcnt[19:15]};
// packed 4 bpp pixels use the high nibble at even addresses
assign buf_din   = duplicate ? 9'h0 :
                   BPP==4 ? { 1'b0, scan_dout[13:10], gfx_addr[0] ? rom_data[3:0] : rom_data[7:4] } :
                            { scan_dout[12], rom_data };
assign blnk_n    = BPP==4 ? pxl[3:0]!=0 : 1'b1;   // the 8 bpp layer has no transparent pen
assign rst_cnt   = vs & hs;
assign pre_lvbl  = vdump==VB_END;
assign duplicate = (~oblk[2] & ~wrap) | rvo;

always @(*) begin
    done    = wr_addr>=RD_END;
    cnt_cen = 0;
    hs_cen  = 0;
    if(cen24) begin
        cnt_cen = rom_cs & rom_ok & !done;
        if( lvbl | pre_lvbl ) hs_cen  = hs & ~hs_l;  // starts drawing in buffer one line before lvbl is high
    end
    if( wr_addr<WR_STRT ) cnt_cen = 1;
end

always @(posedge clk) begin
    if(cen24) begin
        hs_l     <= hs;
        oblk <= {oblk[1:0], ~|{ycnt[23:20],xcnt[23:20]}};
    end
end

jtframe_counter #(.W(9),.RST_VAL(RST_CT)) u_counter(
    .rst        ( hs_cen    ),
    .clk        ( clk       ),
    .cen        ( cnt_cen   ),
    .cnt        ( wr_addr   )
);

jtframe_sh #(.W(9),.L(RD_DLY)) u_hb_dly(
    .clk        ( clk       ),
    .clk_en     ( pxl_cen   ),
    .din        ( hdump     ),
    .drop       ( rd_addr   )
);

jtchqflag_roz_cnt u_xcnt(
    .rst        ( rst_cnt   ),
    .clk        ( clk       ),
    .pxl_cen    ( cnt_cen   ),
    .cnt0       ( xcnt0     ),
    .hs_cen     ( hs_cen    ),
    .hstep      ( xhstep    ),
    .vstep      ( xvstep    ),
    .cnt        ( xcnt      )
);

jtchqflag_roz_cnt u_ycnt(
    .rst        ( rst_cnt   ),
    .clk        ( clk       ),
    .pxl_cen    ( cnt_cen   ),
    .hs_cen     ( hs_cen    ),
    .cnt0       ( ycnt0     ),
    .hstep      ( yhstep    ),
    .vstep      ( yvstep    ),
    .cnt        ( ycnt      )
);

jtk051316_mmr #(.SIMFILE(MMRFILE)) u_mmr(
    .rst        ( rst       ),
    .clk        ( clk       ),

    .cs         ( io_cs     ),
    .addr       ( cpu_addr[3:0] ),
    .rnw        ( ~cpu_we   ),
    .din        ( cpu_dout  ),
    .dout       (           ),

    .xcnt0      ( xcnt0     ),
    .xhstep     ( xhstep    ),
    .xvstep     ( xvstep    ),
    .ycnt0      ( ycnt0     ),
    .yhstep     ( yhstep    ),
    .yvstep     ( yvstep    ),
    .ckbank     ( ckbank    ),
    .rmrd_n     ( rmrd_n    ),
    .hflip_en   ( hflip_en  ),
    .vflip_en   ( vflip_en  ),

    // IOCTL dump
    .ioctl_addr ( ioctl_addr[3:0] ),
    .ioctl_din  ( mmr_dump  ),
    // Debug
    .debug_bus  ( 8'd0      ),
    .st_dout    (           )
);

jtframe_dual_nvram #(.AW(10),.SIMFILE(RAM0FILE)) u_attr(
    // Port 0: CPU
    .clk0   ( clk            ),
    .data0  ( cpu_dout       ),
    .addr0  ( cpu_addr[9:0]  ),
    .we0    ( we[1]          ),
    .q0     ( cpu_ram1       ),
    // Port 1
    .clk1   ( clk            ),
    .addr1a ( vaddr          ),
    .addr1b ( ioctl_addr[9:0]),
    .sel_b  ( ioctl_ram      ),
    .data1  ( 8'd0           ),
    .we_b   ( 1'b0           ),
    .q1     ( scan_dout[ 7:0])  // code
);

jtframe_dual_nvram #(.AW(10),.SIMFILE(RAM1FILE)) u_code(
    // Port 0: CPU
    .clk0   ( clk            ),
    .data0  ( cpu_dout       ),
    .addr0  ( cpu_addr[9:0]  ),
    .we0    ( we[2]          ),
    .q0     ( cpu_ram2       ),
    // Port 1
    .clk1   ( clk            ),
    .addr1a ( vaddr          ),
    .addr1b ( ioctl_addr[9:0]),
    .sel_b  ( ioctl_ram      ),
    .data1  ( 8'd0           ),
    .we_b   ( 1'b0           ),
    .q1     ( scan_dout[15:8])  // color
);

jtframe_linebuf #(.DW(9)) u_linebuf(
    .clk        ( clk       ),
    .LHBL       ( ~hs       ),
    // New line writting
    .we         ( rom_ok    ),
    .wr_data    ( buf_din   ),
    .wr_addr    ( wr_addr   ),
    // Previous line reading
    .rd_gated   (           ),
    .rd_addr    ( rd_addr   ),
    .rd_data    ( pxl       )
);

endmodule

module jtchqflag_roz_cnt(
    input             clk, rst,
    input             hs_cen, pxl_cen,
    input      [15:0] hstep, vstep, cnt0,
    output reg [23:0] cnt
);

reg [23:0] vcnt;
wire [23:0] cnt_init = {cnt0,8'd0};

always @(posedge clk) begin
    if( rst ) begin
        cnt  <= cnt_init;
        vcnt <= cnt_init;
    end else begin
        if(pxl_cen)
            cnt  <= cnt  + {{8{hstep[15]}},hstep};
        if( hs_cen) begin
            vcnt <= vcnt + {{8{vstep[15]}},vstep};
            cnt  <= vcnt;
        end
    end
end

endmodule
