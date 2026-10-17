/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 1-06-2020
 * Miss Bubble II changes (2026, Tom Sveen), MAME missb2.cpp: no MCU. Main CPU IRQ held at vblank,
 * fc00-feff RAM, ff00-ff03 DSW1/DSW2/P1/P2. Sub CPU: 0000-7fff ROM, 9000-9fff / a000-afff banked ROM
 * (sub ROM 8000 / 9000 + bank * 1000), b000-b1ff ROM, c000-c1ff background palette, c800-cfff RAM,
 * d000 bank (bit 1 -> 1, bit 0 -> 4), d003 background picture register, e000-f7ff shared RAM, IRQ held at vblank. */

module jtmissb_main(
    input               rst,
    input               clk,
    input               cen6,
    // Cabinet inputs
    input      [ 1:0]   cab_1p,
    input      [ 1:0]   coin,
    input      [ 5:0]   joystick1,
    input      [ 5:0]   joystick2,
    // Video interface
    output reg          vram_cs,
    output reg          pal_cs,
    output reg          black_n,
    output reg          flip,
    output     [12:0]   cpu_addr,
    output     [ 7:0]   cpu_dout,
    output              cpu_rnw,
    input      [ 7:0]   vram_dout,
    input      [ 7:0]   pal_dout,
    input               LVBL,
    // background (sub CPU)
    output reg [ 7:0]   bgvram,
    output              bgpal_we,
    output     [ 8:0]   sub_pal_addr,
    output     [ 7:0]   sub_cpu_dout,
    input      [ 7:0]   bgpal_dout,
    // Sound interface
    input      [ 7:0]   main_latch,
    output reg [ 7:0]   snd_latch,
    output reg          snd_stb,
    input               snd_flag,
    input               main_stb,
    output              main_flag,
    output reg          snd_rst,
    // Main CPU ROM interface
    output     [17:0]   main_rom_addr,
    output reg          main_rom_cs,
    input               main_rom_ok,
    input      [ 7:0]   main_rom_data,
    // Sub CPU ROM interface
    output     [15:0]   sub_rom_addr,
    output reg          sub_rom_cs,
    input               sub_rom_ok,
    input      [ 7:0]   sub_rom_data,
    // DIP switches
    input               dip_pause,
    input               service,
    input               tilt,
    input      [ 7:0]   dipsw_a,
    input      [ 7:0]   dipsw_b
);

`ifndef NOMAIN
wire        cen_main, cen_sub;
reg  [ 7:0] main_din, sub_din;
wire [ 7:0] main_dout, sub_dout, ram_dout, sram_dout;
wire [15:0] main_addr, sub_addr;
wire        main_mreq_n, main_iorq_n, main_rdn, main_wrn, main_rfsh_n;
wire        sub_mreq_n,  sub_iorq_n,  sub_rd_n,  sub_wrn, sub_rfsh_n;
reg         main_macc_n, sub_macc_n;
reg         main_work_cs, ram_cs, in_cs, tres_cs, misc_cs, sound_cs;
reg         sub_work_cs, sub_bank_cs, sub_pal_cs, sub_ram_cs, sub_bg_cs, sub_bgv_cs;
wire        sub_int_n, main_int_n;
reg  [ 2:0] bank, sbank;
reg         main_rst_n, sub_rst_n;
reg  [ 7:0] wdog_cnt;
reg         last_VBL;
wire [ 7:0] work2main_dout, work2sub_dout;
wire        sub_m1_n, main_m1_n;
reg         lde, sde;
wire        VBL_gated    = ~LVBL & dip_pause;
wire        sub_int_ack  = ~sub_iorq_n & ~sub_m1_n;
wire        main_int_ack = ~main_iorq_n & ~main_m1_n;
reg  [ 7:0] in_dout;

assign main_rom_addr = main_addr[15] ?
                        { { {1'b0, bank}+4'b10 } , main_addr[13:0] } : // banked
                        { 3'd0, main_addr[14:0] }; // not banked
// sub ROM: 9000-9fff -> 8000 + bank * 1000, a000-afff -> 9000 + bank * 1000
wire [3:0] sub_page  = { 1'b0, sbank } + { 3'd0, sub_addr[13] } + 4'h8;
assign sub_rom_addr  = sub_bg_cs ? { sub_page, sub_addr[11:0] } :
                       sub_addr;
assign cpu_addr      = main_addr[12:0];
assign cpu_dout      = main_dout;
assign cpu_rnw       = main_wrn;
assign bgpal_we      = sub_pal_cs && !sub_wrn;
assign sub_pal_addr  = sub_addr[8:0];
assign sub_cpu_dout  = sub_dout;

// Watchdog and main CPU reset
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        main_rst_n <= 0;
        wdog_cnt   <= 8'd0;
    end else begin
        last_VBL  <= VBL_gated;
        if( tres_cs )
            wdog_cnt <= 8'd0;
        else if( !VBL_gated && last_VBL ) wdog_cnt <= wdog_cnt + 8'd1;
        main_rst_n <= ~wdog_cnt[7];
    end
end

// Main CPU address decoder
always @(*) begin
    main_macc_n  =  main_mreq_n | ~main_rfsh_n;
    main_rom_cs  = !main_macc_n && (!main_addr[15] || main_addr[15:14]==2'b10); // 0000-7FFF and 8000-BFFF
    vram_cs      = !main_macc_n && main_addr[15:13]==3'b110; // C000-DFFF
    main_work_cs = !main_macc_n && main_addr[15:13]==3'b111 && main_addr[12:11]!=2'b11; //E000-F7FF
    pal_cs       = !main_macc_n && main_addr[15: 9]==7'b1111_100; // F800-F9FF
    sound_cs     = !main_macc_n && main_addr[15: 8]==8'hFA && !main_addr[7];
    tres_cs      = !main_macc_n && main_addr[15: 8]==8'hFA &&  main_addr[7];
    misc_cs      = !main_macc_n && main_addr[15: 0]==16'hFB40 && !main_wrn;
    ram_cs       = !main_macc_n && main_addr[15:10]==6'b1111_11 && main_addr[9:8]!=2'b11; // FC00-FEFF
    in_cs        = !main_macc_n && main_addr[15: 8]==8'hFF;
end

always @(posedge clk) begin
    case( main_addr[1:0] )
        0: in_dout <= dipsw_a;
        1: in_dout <= dipsw_b;
        2: in_dout <= { 1'b1, cab_1p[0], joystick1[4], joystick1[5], coin[0], coin[1], joystick1[1], joystick1[0] };
        3: in_dout <= { 1'b1, cab_1p[1], joystick2[4], joystick2[5], service, tilt, joystick2[1], joystick2[0] };
    endcase
end

// Main CPU input mux
always @(posedge clk) begin
    main_din <=
        main_rom_cs ? main_rom_data :
        vram_cs     ? vram_dout     :
        pal_cs      ? pal_dout      :
        main_work_cs? work2main_dout:
        ram_cs      ? ram_dout      :
        !main_iorq_n? 8'hff         :
        sound_cs    ? (main_addr[0] ? { 6'h3f, main_flag, snd_flag } : main_latch) :
        in_cs       ? (main_addr[7:2]==0 ? in_dout : 8'hff) :
        8'hff;
end

// Main CPU control bits: 0-2 ROM bank (xor 4), 4 sub CPU reset, 6 video enable, 7 flip
always @(posedge clk ) begin
    if( !main_rst_n ) begin
        bank      <= 3'd4;  // reset clears the latch
        sub_rst_n <= 0;
        black_n   <= 0;
        flip      <= 0;
    end else if(misc_cs) begin
        bank      <= cpu_dout[2:0]^3'b100;
        sub_rst_n <= cpu_dout[4];
        black_n   <= cpu_dout[6];
        flip      <= cpu_dout[7];
    end
end

// Communication with sound CPU
always @(posedge clk ) begin
    if( !main_rst_n ) begin
        snd_latch <= 8'd0;
        snd_rst   <= 0;
        snd_stb   <= 0;
    end else if(sound_cs) begin
        snd_stb <= !main_wrn && cpu_addr[1:0]==2'b00;
        if( !main_wrn )
            case( cpu_addr[1:0] )
                2'b00: snd_latch <= main_dout;
                2'b11: snd_rst   <= main_dout[0];
                default:;
            endcase
    end else snd_stb <= 0;
end

jtframe_ff u_flag(
    .clk    ( clk                    ),
    .rst    ( main_rst_n             ),
    .cen    ( 1'b1                   ),
    .din    ( 1'b0                   ),
    .q      (                        ),
    .qn     ( main_flag              ),
    .set    ( sound_cs && !main_rdn  ),
    .clr    ( 1'b0                   ),
    .sigedge( main_stb               )
);

jtframe_ram #(.AW(10)) u_ram(
    .clk    ( clk              ),
    .cen    ( 1'b1             ),
    .data   ( main_dout        ),
    .addr   ( main_addr[9:0]   ),
    .we     ( ram_cs & ~main_wrn ),
    .q      ( ram_dout         )
);

// Sub CPU address decoder
always @(*) begin
    sub_macc_n  =  sub_mreq_n || !sub_rfsh_n;
    sub_bg_cs   = !sub_macc_n && (sub_addr[15:12]==4'h9 || sub_addr[15:12]==4'ha);
    sub_rom_cs  = !sub_macc_n && (!sub_addr[15] || sub_bg_cs || sub_addr[15:9]==7'b1011_000);
    sub_pal_cs  = !sub_macc_n && sub_addr[15:9]==7'b1100_000;
    sub_ram_cs  = !sub_macc_n && sub_addr[15:11]==5'b1100_1;
    sub_bank_cs = !sub_macc_n && sub_addr==16'hd000 && !sub_wrn;
    sub_bgv_cs  = !sub_macc_n && sub_addr==16'hd003;
    sub_work_cs = !sub_macc_n && sub_addr[15:13]==3'b111 && sub_addr[12:11]!=2'b11;
end

always @(posedge clk) begin
    if( !sub_rst_n ) begin
        sbank <= 0;
    end else begin
        if( sub_bank_cs ) sbank <= { sub_dout[0], 1'b0, sub_dout[1] };
    end
    if( rst ) bgvram <= 0;
    else if( sub_bgv_cs && !sub_wrn ) bgvram <= sub_dout;
end

// Sub CPU input mux
always @(posedge clk) begin
    sub_din <= sub_rom_cs  ? sub_rom_data :
               sub_work_cs ? work2sub_dout :
               sub_pal_cs  ? bgpal_dout :
               sub_ram_cs  ? sram_dout :
               sub_bgv_cs  ? bgvram : 8'hff;
end

jtframe_ram #(.AW(11)) u_subram(
    .clk    ( clk              ),
    .cen    ( 1'b1             ),
    .data   ( sub_dout         ),
    .addr   ( sub_addr[10:0]   ),
    .we     ( sub_ram_cs & ~sub_wrn ),
    .q      ( sram_dout        )
);

// Time shared
jtframe_dual_ram #(.AW(13)) u_work(
    .clk0   ( clk             ),
    .data0  ( main_dout       ),
    .addr0  ( main_addr[12:0] ),
    .we0    ( ~main_wrn & lde ),
    .q0     ( work2main_dout  ),
    // Sub CPU
    .clk1   ( clk             ),
    .data1  ( sub_dout        ),
    .addr1  ( sub_addr[12:0]  ),
    .we1    ( ~sub_wrn & sub_work_cs       ),
    .q1     ( work2sub_dout   )
);

always @(posedge clk, negedge main_rst_n) begin
    if( !main_rst_n )
        lde <= 0;
    else begin
        lde <= main_work_cs;
    end
end

always @(posedge clk, negedge sub_rst_n) begin
    if( !sub_rst_n )
        sde <= 0;
    else begin
        if( !sub_work_cs )
            sde <= 0;
        else if( !main_work_cs ) sde <= 1;
    end
end

jtframe_z80 u_maincpu(
    .rst_n    ( main_rst_n     ),
    .clk      ( clk            ),
    .cen      ( cen_main       ),
    .wait_n   ( 1'b1           ),
    .int_n    ( main_int_n     ),
    .nmi_n    ( 1'b1           ),
    .busrq_n  ( 1'b1           ),
    .m1_n     ( main_m1_n      ),
    .mreq_n   ( main_mreq_n    ),
    .iorq_n   ( main_iorq_n    ),
    .rd_n     ( main_rdn       ),
    .wr_n     ( main_wrn       ),
    .rfsh_n   ( main_rfsh_n    ),
    .halt_n   (                ),
    .busak_n  (                ),
    .A        ( main_addr      ),
    .din      ( main_din       ),
    .dout     ( main_dout      )
);

wire main_wait = sde & main_work_cs;

jtframe_z80wait #(.DEVCNT(1),.RECOVERY(0)) u_mainwait(
    .rst_n    ( main_rst_n      ),
    .clk      ( clk             ),
    .cen_in   ( cen6            ),
    .cen_out  ( cen_main        ),
    .gate     (                 ),
    .mreq_n   ( main_mreq_n     ),
    .iorq_n   ( main_iorq_n     ),
    .busak_n  ( 1'b1            ),
    .dev_busy ( main_wait       ),
    .rom_cs   ( 1'b0            ),
    .rom_ok   ( 1'b1            )
);

jtframe_z80 u_subcpu(
    .rst_n    ( sub_rst_n      ),
    .clk      ( clk            ),
    .cen      ( cen_sub        ),
    .wait_n   ( 1'b1           ),
    .int_n    ( sub_int_n      ),
    .nmi_n    ( 1'b1           ),
    .busrq_n  ( 1'b1           ),
    .m1_n     ( sub_m1_n       ),
    .mreq_n   ( sub_mreq_n     ),
    .iorq_n   ( sub_iorq_n     ),
    .rd_n     ( sub_rd_n       ),
    .wr_n     ( sub_wrn        ),
    .rfsh_n   ( sub_rfsh_n     ),
    .halt_n   (                ),
    .busak_n  (                ),
    .A        ( sub_addr       ),
    .din      ( sub_din        ),
    .dout     ( sub_dout       )
);

wire sub_wait = (main_work_cs & ~sde) & sub_work_cs;

jtframe_z80wait #(.DEVCNT(1),.RECOVERY(0)) u_subwait(
    .rst_n    ( sub_rst_n       ),
    .clk      ( clk             ),
    .cen_in   ( cen6            ),
    .cen_out  ( cen_sub         ),
    .gate     (                 ),
    .mreq_n   ( sub_mreq_n      ),
    .iorq_n   ( sub_iorq_n      ),
    .busak_n  ( 1'b1            ),
    .dev_busy ( sub_wait        ),
    .rom_cs   ( 1'b0            ),
    .rom_ok   ( 1'b1            )
);

jtframe_ff u_subint(
    .rst    ( ~sub_rst_n    ),
    .clk    ( clk           ),
    .cen    ( 1'b1          ),
    .din    ( 1'b1          ),
    .q      (               ),
    .qn     ( sub_int_n     ),
    .set    ( 1'b0          ),
    .clr    ( sub_int_ack   ),
    .sigedge( VBL_gated     )
);

jtframe_ff u_mainint(
    .rst    ( ~main_rst_n   ),
    .clk    ( clk           ),
    .cen    ( 1'b1          ),
    .din    ( 1'b1          ),
    .q      (               ),
    .qn     ( main_int_n    ),
    .set    ( 1'b0          ),
    .clr    ( main_int_ack  ),
    .sigedge( VBL_gated     )
);
`else
assign cpu_addr      = 13'd0;
assign cpu_dout      = 8'd0;
assign cpu_rnw       = 1'b1;
assign main_flag     = 1'b0;
assign main_rom_addr = 18'd0;
assign sub_rom_addr  = 16'd0;
assign bgpal_we = 0, sub_pal_addr = 0, sub_cpu_dout = 0;
initial begin
    vram_cs=0; pal_cs=0; black_n=1; flip=0; snd_latch=0; snd_stb=0; snd_rst=0;
    main_rom_cs=0; sub_rom_cs=0; bgvram=0;
end
`endif
endmodule
