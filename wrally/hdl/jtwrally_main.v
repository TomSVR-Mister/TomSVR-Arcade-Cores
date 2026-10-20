/*  This file is part of JTWRALLY.
    SPDX-License-Identifier: GPL-3.0-or-later
    World Rally 68000 (MAME wrally.cpp). The bus logic follows jotego's JTGAE1
    (jtgae1_main.v), adapted to the World Rally memory map. */

module jtwrally_main(
    input              clk,
    input              rst,
    input              lvbl,

    output     [19:1]  main_addr,
    output reg         main_cs,
    input      [15:0]  main_data,
    input              main_ok,

    output     [15:0]  cpu_dout,
    // video memories (CPU ports)
    output     [13:1]  vaddr,
    output     [ 1:0]  vdsn_we,     // byte enables for writes
    output             vram_we,     // decrypted data on vram_din
    output     [15:0]  vram_din,
    output reg         pal_cs, spr_cs, sha_cs,
    output             mem_we,
    input      [15:0]  vram_dout, pal_dout, spr_dout, sha_dout,
    output     [15:0]  scr0_y, scr0_x, scr1_y, scr1_x,

    input      [15:0]  dipsw,
    input      [ 5:0]  joystick1,
    input      [ 5:0]  joystick2,
    input      [ 1:0]  coin,
    input      [ 1:0]  start,
    input              service,
    input              dip_test,
    input              dip_pause,
    output             flip,

    output     [ 7:0]  oki_din,
    input      [ 7:0]  oki_dout,
    output             oki_wrn,
    output reg [ 3:0]  oki_bank
);

wire [23:1] A;
wire [23:0] addr = { A, 1'b0 };
wire [ 2:0] FC;
wire        RnW, UDSn, LDSn, ASn, DTACKn, cpu_cen, cpu_cenb, BUSn, VPAn, LDSWn;
wire        IPL6n, ok_dly, int_clr;
wire [15:0] dec_word, vmem_wdata;
reg  [15:0] cpu_din, scr[0:3];
reg  [ 7:0] outlatch;
reg         vram_cs, vregs_cs, io_cs, outl_cs, okib_cs, oki_cs;
reg         gear, b2_l;
// VRAM write decryption: second word of a 32-bit write (see jtgae1_main.v)
reg  [15:0] vdec_last_enc, vdec_last_dec, pend_enc, pend_dec;
reg  [12:0] vdec_prev_woff, pend_woff;
reg         vdec_prev_wr, pend_vramwr, pend_is2nd;
wire        vdec_is2nd = vdec_prev_wr & (vdec_prev_woff == (addr[13:1] - 13'd1));

assign main_addr = A[19:1];
assign BUSn      = ASn | (UDSn & LDSn);
assign VPAn      = ~(~ASn && FC == 3'd7);   // autovector
assign int_clr   = ~ASn && FC == 3'd7;
assign LDSWn     = RnW | LDSn;
assign vaddr     = A[13:1];
assign vdsn_we   = {~UDSn, ~LDSn};
assign mem_we    = ~RnW;
assign vram_we   = vram_cs & ~RnW;
assign vram_din  = dec_word;
assign oki_din   = cpu_dout[7:0];
assign oki_wrn   = LDSWn | ~oki_cs;
assign flip      = outlatch[5];
assign scr0_y = scr[0], scr0_x = scr[1], scr1_y = scr[2], scr1_x = scr[3];

always @* begin
    main_cs  = !BUSn && addr[23:20] == 4'h0 && RnW;
    vram_cs  = !BUSn && addr[23:14] == 10'h040;                 // 100000-103FFF
    vregs_cs = !BUSn && addr[23:12] == 12'h108 && addr[11:3]==0;// 108000-108007
    pal_cs   = !BUSn && addr[23:14] == 10'h080;                 // 200000-203FFF
    spr_cs   = !BUSn && addr[23:12] == 12'h440;                 // 440000-440FFF
    sha_cs   = !BUSn && addr[23:14] == 10'h3fb;                 // FEC000-FEFFFF
    io_cs    = !BUSn && addr[23:8]  == 16'h7000;
    outl_cs  = io_cs && addr[3:1] == 3'd5;                      // 70000B (A6:4 = bit)
    okib_cs  = io_cs && addr[7:1] == 7'h06;                     // 70000D
    oki_cs   = io_cs && addr[7:1] == 7'h07;                     // 70000F
end

// P1_P2: gear shift is a toggle (MAME PORT_TOGGLE PORT_REVERSE, reads 1 at start)
always @(posedge clk) begin
    if( rst ) begin
        gear <= 1;
        b2_l <= 1;
    end else begin
        b2_l <= joystick1[5];
        if( b2_l && !joystick1[5] ) gear <= ~gear;
    end
end

wire [15:0] p1p2 = { start[1], start[0], joystick2[4], joystick2[5],
                     joystick2[1], joystick2[0], joystick2[2], joystick2[3],
                     coin[1], coin[0], joystick1[4], gear,
                     joystick1[1], joystick1[0], joystick1[2], joystick1[3] };
wire [15:0] dsw  = { dipsw[15:8], dipsw[7] & dip_test, dipsw[6:0] };

always @(posedge clk) begin
    cpu_din <= main_cs  ? main_data :
               vram_cs  ? vram_dout :
               pal_cs   ? pal_dout  :
               spr_cs   ? spr_dout  :
               sha_cs   ? sha_dout  :
               vregs_cs ? scr[addr[2:1]] :
               io_cs && addr[7:1]==7'h00 ? dsw  :
               io_cs && addr[7:1]==7'h01 ? p1p2 :
               io_cs && addr[7:1]==7'h02 ? 16'h00ff :        // optical wheel
               io_cs && addr[7:1]==7'h04 ? { 12'hfff, 2'b00, dip_test, service } :
               oki_cs ? { 8'hff, oki_dout } : 16'hffff;
end

always @(posedge clk) begin
    if( rst ) begin
        outlatch <= 0;
        oki_bank <= 0;
        scr[0] <= 0; scr[1] <= 0; scr[2] <= 0; scr[3] <= 0;
    end else begin
        if( outl_cs && !LDSWn ) outlatch[addr[6:4]] <= cpu_dout[0];
        if( okib_cs && !LDSWn ) oki_bank <= cpu_dout[3:0];
        if( vregs_cs && !RnW ) begin
            if( !UDSn ) scr[addr[2:1]][15:8] <= cpu_dout[15:8];
            if( !LDSn ) scr[addr[2:1]][ 7:0] <= cpu_dout[ 7:0];
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        vdec_prev_wr   <= 0;
        vdec_prev_woff <= 0;
        vdec_last_enc  <= 0;
        vdec_last_dec  <= 0;
        pend_woff      <= 0;
        pend_enc       <= 0;
        pend_dec       <= 0;
        pend_vramwr    <= 0;
        pend_is2nd     <= 0;
    end else begin
        if (!BUSn) begin
            pend_woff   <= addr[13:1];
            pend_enc    <= cpu_dout;
            pend_dec    <= dec_word;
            pend_vramwr <= ~RnW & vram_cs;
            pend_is2nd  <= vdec_is2nd;
        end else begin
            if (pend_vramwr) begin
                vdec_prev_wr <= ~pend_is2nd;
                if (!pend_is2nd) begin
                    vdec_prev_woff <= pend_woff;
                    vdec_last_enc  <= pend_enc;
                    vdec_last_dec  <= pend_dec;
                end
            end
            pend_vramwr <= 0;
            pend_is2nd  <= 0;
        end
    end
end

jtwrally_vram_decrypt u_decrypt(
    .key        ( 6'h1f     ),
    .prev_ciph  ( vdec_is2nd ? vdec_last_enc : 16'd0 ),
    .prev_plain ( vdec_is2nd ? vdec_last_dec : 16'd0 ),
    .din        ( cpu_dout  ),
    .dout       ( dec_word  )
);

// IRQ 6 on vblank, held until acknowledged (MAME irq6_line_hold)
jtframe_edge #(.QSET(0)) u_irq(
    .rst    ( rst      ),
    .clk    ( clk      ),
    .edgeof ( ~lvbl    ),
    .clr    ( int_clr  ),
    .q      ( IPL6n    )
);

jtframe_okdly #(.W(1)) u_okdly(
    .rst    ( rst      ),
    .clk    ( clk      ),
    .cs     ( main_cs  ),
    .ok     ( main_ok  ),
    .ok_dly ( ok_dly   )
);

jtframe_68kdtack_cen #(.W(6),.RECOVERY(1)) u_dtack(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( main_cs   ),
    .bus_busy   ( main_cs & ~ok_dly ),
    .bus_legit  ( 1'b0      ),
    .bus_ack    ( 1'b0      ),
    .ASn        ( ASn       ),
    .DSn        ( {UDSn,LDSn} ),
    .num        ( 5'd1      ),
    .den        ( 6'd4      ),   // 12 MHz
    .DTACKn     ( DTACKn    ),
    .wait2      ( 1'b0      ),
    .wait3      ( 1'b0      ),
    .fave       (           ),
    .fworst     (           )
);

jtframe_m68k u_cpu(
    .clk        ( clk         ),
    .rst        ( rst         ),
    .RESETn     (             ),
    .cpu_cen    ( cpu_cen     ),
    .cpu_cenb   ( cpu_cenb    ),
    .eab        ( A           ),
    .iEdb       ( cpu_din     ),
    .oEdb       ( cpu_dout    ),
    .eRWn       ( RnW         ),
    .LDSn       ( LDSn        ),
    .UDSn       ( UDSn        ),
    .ASn        ( ASn         ),
    .VPAn       ( VPAn        ),
    .FC         ( FC          ),
    .BERRn      ( 1'b1        ),
    .HALTn      ( dip_pause   ),
    .BRn        ( 1'b1        ),
    .BGACKn     ( 1'b1        ),
    .BGn        (             ),
    .DTACKn     ( DTACKn      ),
    .IPLn       ( { IPL6n, IPL6n, 1'b1 } )   // level 6 = 001
);

endmodule
