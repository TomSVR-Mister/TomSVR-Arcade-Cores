/* SPDX-License-Identifier: GPL-3.0-or-later
   K051316 zoom/rotate layer for Chequered Flag. Copy of jotego's jt051316 (jtcores/cores/ajax) with the
   pixel formats Chequered Flag uses:
   BPP=4: code = {color[1:0], code}, pixel = {color[5:2], pen[3:0]}
   BPP=8: code = {color[3:0], code}, pixel = {color[4], pen[7:0]}
   The line is fetched through a pipeline: counter -> tile RAM -> FIFO -> ROM slot, so a new ROM
   address is presented the clock after the previous one is served. With DUAL=1 even and odd
   pixels go to two ROM slots in different SDRAM banks, which fetch at the same time. */

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
    // second copy of the ROM in another SDRAM bank, used when DUAL=1 (odd pixels)
    output  [23:0] rom2_addr,
    output         rom2_cs,
    input          rom2_ok,
    input   [ 7:0] rom2_data,

    input   [10:0] ioctl_addr,
    input          ioctl_ram,
    output  [ 7:0] ioctl_din, mmr_dump
);
parameter [8:0] WR_STRT=9'h060, // Positions in wr_addr skipped during blanking
                VB_END =9'h10F, // Must be same as in vtimer
                RST_CT =9'h058, // starting value for wr_addr
                RD_DLY =9'h00B, // number of times to delay hdump
                RD_END =9'h19F; // Value of rd_addr when LHBL goes low
parameter BPP=4, DUAL=0;
parameter MMRFILE="", RAM0FILE="", RAM1FILE="";

localparam EW=24+4+1; // FIFO entry: gfx address, colour bits, duplicate (blank) flag

wire [23:0] xcnt, ycnt;
wire [15:0] scan_dout;
wire [ 9:0] vaddr;
wire [ 8:0] rd_addr;
reg  [ 8:0] wr_addr, nissued;
wire [ 7:0] cpu_ram1, cpu_ram2;
reg  [ 8:0] buf_din;
wire [ 2:1] we;
wire [15:0] xcnt0, xhstep, xvstep, ycnt0, yhstep, yvstep;
wire [12:0] ckbank;
wire        rmrd_n, hflip_en, vflip_en;
wire        rst_cnt, pre_lvbl;
reg         hs_l, hs_cen;
// pipeline
reg         issue, s1v, s1dup, pushsel, turn;
reg  [ 3:0] s1vf, s1hf;
reg  [ 3:0] occ;
reg  [EW-1:0] f0[0:3], f1[0:3];  // two FIFOs: even pixels to ROM slot 1, odd pixels to slot 2
reg  [ 2:0] n0, n1;
wire [EW-1:0] h0 = f0[0], h1 = f1[0];
wire [EW-1:0] hd = turn ? h1 : h0;
wire        vflip = vflip_en & scan_dout[15],
            hflip = hflip_en & scan_dout[14];
wire [EW-1:0] s1e = { scan_dout, s1vf^{4{vflip}}, s1hf^{4{hflip}}, scan_dout[13:10], s1dup };
wire        pop0  = !turn && n0!=0 && rom_ok,
            pop1  =  turn && n1!=0 && rom2_ok,
            pop   = pop0 | pop1,
            push0 = s1v & ~pushsel,
            push1 = s1v &  pushsel;
wire [ 7:0] pdata = turn ? rom2_data : rom_data;
wire [23:0] ga0 = h0[EW-1-:24], ga1 = h1[EW-1-:24], gad = hd[EW-1-:24];
wire [23:0] vid0 = BPP==4 ? {1'b0,ga0[23:1]} : ga0,
            vid1 = BPP==4 ? {1'b0,ga1[23:1]} : ga1;

assign we        ={cpu_addr[10],~cpu_addr[10]} & {2{cpu_we & vr_cs}};
assign cpu_din   = cpu_addr[10] ? cpu_ram2 : cpu_ram1;
assign ioctl_din = ioctl_addr[10] ? scan_dout[15:8] : scan_dout[7:0];
assign rom_addr  = rmrd_n ? vid0 : { ckbank, cpu_addr };
assign rom_cs    = rmrd_n ? n0!=0 : vr_cs;
assign rom2_addr = vid1;
assign rom2_cs   = DUAL && n1!=0;
assign cpu_ok    = rmrd_n | ~vr_cs | rom_ok;
assign vaddr     = {ycnt[19:15],xcnt[19:15]};
assign blnk_n    = BPP==4 ? pxl[3:0]!=0 : 1'b1;   // the 8 bpp layer has no transparent pen
assign rst_cnt   = vs & hs;
assign pre_lvbl  = vdump==VB_END;

// packed 4 bpp pixels use the high nibble at even addresses
always @(*) begin
    buf_din = hd[0] ? 9'h0 :
              BPP==4 ? { 1'b0, hd[4:1], gad[0] ? pdata[3:0] : pdata[7:4] } :
                       { hd[3], pdata };    // hd[4:1] holds code bits 13:10
end

always @(*) begin
    hs_cen = 0;
    if(cen24 && (lvbl | pre_lvbl)) hs_cen = hs & ~hs_l;  // starts drawing in buffer one line before lvbl is high
    issue  = !hs_cen && occ < (DUAL ? 4'd8 : 4'd4) && nissued < (RD_END-RST_CT+9'd1);
end

integer i;
always @(posedge clk) begin
    if(cen24) hs_l <= hs;
    s1v   <= issue;
    s1vf  <= ycnt[14:11];
    s1hf  <= xcnt[14:11];
    s1dup <= (~(~|{ycnt[23:20],xcnt[23:20]}) & ~wrap) | rvo;
    if( hs_cen ) begin
        occ     <= 0;
        n0      <= 0;
        n1      <= 0;
        s1v     <= 0;
        nissued <= 0;
        pushsel <= 0;
        turn    <= 0;
        wr_addr <= RST_CT;
    end else begin
        occ     <= occ + {3'd0,issue} - {3'd0,pop};
        nissued <= nissued + {8'd0,issue};
        if( pop ) begin
            wr_addr <= wr_addr + 9'd1;
            if( DUAL ) turn <= ~turn;
        end
        if( pop0 ) for( i=0; i<3; i=i+1 ) f0[i] <= f0[i+1];
        if( push0 ) f0[n0-{2'd0,pop0}] <= s1e;
        n0 <= n0 + {2'd0,push0} - {2'd0,pop0};
        if( pop1 ) for( i=0; i<3; i=i+1 ) f1[i] <= f1[i+1];
        if( push1 ) f1[n1-{2'd0,pop1}] <= s1e;
        n1 <= n1 + {2'd0,push1} - {2'd0,pop1};
        if( s1v && DUAL ) pushsel <= ~pushsel;
    end
end

jtframe_sh #(.W(9),.L(RD_DLY)) u_hb_dly(
    .clk        ( clk       ),
    .clk_en     ( pxl_cen   ),
    .din        ( hdump     ),
    .drop       ( rd_addr   )
);

jtchqflag_roz_cnt u_xcnt(
    .rst        ( rst_cnt   ),
    .clk        ( clk       ),
    .pxl_cen    ( issue     ),
    .cnt0       ( xcnt0     ),
    .hs_cen     ( hs_cen    ),
    .hstep      ( xhstep    ),
    .vstep      ( xvstep    ),
    .cnt        ( xcnt      )
);

jtchqflag_roz_cnt u_ycnt(
    .rst        ( rst_cnt   ),
    .clk        ( clk       ),
    .pxl_cen    ( issue     ),
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
    .we         ( pop       ),
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
