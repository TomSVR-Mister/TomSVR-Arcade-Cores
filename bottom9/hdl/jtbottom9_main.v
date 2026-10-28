/* SPDX-License-Identifier: GPL-3.0-or-later
   Bottom of the Ninth main board: HD63C09E at 3 MHz (run as a 6809 with mc6809i), memory map from MAME bottom9.cpp
   0000-3fff  K052109 tile chip, with K051937/K051960 at 3800-3807/3c00-3fff and these overlays:
              0000-07ff  K051316 RAM (or its ROM when 1f90 bit 4 is set) unless 1f90 bit 5 is set
              2000-27ff  palette RAM unless 1f90 bit 5 is set
              1f80 bank, 1f90 control, 1fa0 watchdog, 1fb0 sound latch, 1fc0 sound IRQ,
              1fd0-1fd3 SYSTEM/P1/P2/DSW1, 1fe0 DSW2, 1ff0-1fff K051316 control
   4000-5fff  RAM, 6000-7fff banked ROM (12 x 8 kB), 8000-ffff ROM (region 18000-1ffff)
   With 1f90 bit 2 set, reads from 0000-3fff (but the overlays) return the K052109 tile ROM. */

module jtbottom9_main(
    input               rst,
    input               clk,
    input               cen12,

    output      [15:0]  cpu_addr,
    output      [ 7:0]  cpu_dout,
    output              cpu_we,

    output reg  [16:0]  rom_addr,
    input       [ 7:0]  rom_data,
    output reg          rom_cs,
    input               rom_ok,
    // cabinet I/O
    input       [ 1:0]  cab_1p,
    input       [ 1:0]  coin,
    input       [ 6:0]  joystick1,
    input       [ 6:0]  joystick2,
    input               service,
    input               dip_test,
    input               dip_pause,
    input       [19:0]  dipsw,

    // video
    input               rst8,
    input               irq_n,
    output reg          tilesys_cs,
    output reg          objsys_cs,
    output reg          pal_cs,
    output reg          roz_vr, roz_io,
    output reg          rmrd,
    output reg          video_en,
    output reg          roz_romrd,
    input       [ 7:0]  tilesys_dout, objsys_dout, pal_dout, roz_dout,
    input               tile_dtack,
    input               roz_ok,
    // sound
    output reg  [ 7:0]  snd_latch,
    output reg          snd_irq,
    // Debug
    input       [ 7:0]  debug_bus,
    output reg  [ 7:0]  st_dout
);
`ifndef NOMAIN
wire [15:0] A;
wire [ 7:0] ram_dout;
wire        RnW;
reg  [ 7:0] cpu_din, cab_dout;
reg  [ 3:0] bank;
reg         ram_cs, bank_cs, ctrl_cs, latch_cs, sirq_cs, in_cs, pal_bank,
            banked, fixed, sirq_l, rst_cmb;
wire        dtack, low;

assign cpu_addr = A;
assign cpu_we   = ~RnW;
assign low      = A[15:14]==0;
assign dtack    = tile_dtack & (~(roz_vr & roz_romrd & RnW) | roz_ok);

always @* begin
    st_dout = debug_bus[0] ? { 2'd0, roz_romrd, pal_bank, bank } : snd_latch;
end

always @(*) begin
    ram_cs = 0; pal_cs = 0; roz_vr = 0; roz_io = 0; tilesys_cs = 0; objsys_cs = 0;
    bank_cs = 0; ctrl_cs = 0; latch_cs = 0; sirq_cs = 0; in_cs = 0; banked = 0; fixed = 0;
    if( low ) begin
        if( A[13:11]==0 && !pal_bank ) roz_vr = 1;
        else if( A[13:11]==3'b100 && !pal_bank ) pal_cs = 1;
        else if( A[13:7]==7'b01_1111_1 && A[3:0]==0 && A[6:4]!=3'b111 ) case( A[6:4] )
            0: bank_cs  = 1;
            1: ctrl_cs  = 1;
            2: ;                // watchdog
            3: latch_cs = 1;
            4: sirq_cs  = 1;
            5,6: in_cs  = 1;
            default:;
        endcase
        else if( A[13:7]==7'b01_1111_1 && A[6:4]==3'b101 && A[3:2]==0 ) in_cs = 1;   // 1fd1-1fd3
        else if( A[13:7]==7'b01_1111_1 && A[6:4]==3'b111 ) roz_io = 1;
        else if( A[13:11]==3'b111 && (A[10] || A[9:3]==0) && (!rmrd || cpu_we) ) objsys_cs = 1;
        else tilesys_cs = 1;
    end else if( A[15:13]==3'b010 ) ram_cs = 1;
    else if( A[15:13]==3'b011 ) banked = 1;
    else fixed = 1;
    rom_cs   = banked | fixed;
    rom_addr = fixed ? { 2'b11, A[14:0] } : { bank, A[12:0] };
end

// input ports (active low)
always @(posedge clk) begin
    case( { A[5], A[1:0] } )
        3'b0_00: cab_dout <= { dipsw[19], dipsw[18] & dip_test, dipsw[17:16], 1'b1, service, coin };  // 1fd0 SYSTEM
        3'b0_01: cab_dout <= { joystick1[6:4], joystick1[0], joystick1[1], joystick1[2], joystick1[3], cab_1p[0] };
        3'b0_10: cab_dout <= { joystick2[6:4], joystick2[0], joystick2[1], joystick2[2], joystick2[3], cab_1p[1] };
        3'b0_11: cab_dout <= dipsw[7:0];       // 1fd3 DSW1
        default: cab_dout <= dipsw[15:8];      // 1fe0 DSW2
    endcase
end

always @* begin
    cpu_din = rom_cs     ? rom_data     :
              ram_cs     ? ram_dout     :
              pal_cs     ? pal_dout     :
              roz_vr     ? roz_dout     :
              in_cs      ? cab_dout     :
              objsys_cs  ? objsys_dout  :
              tilesys_cs ? tilesys_dout : 8'hff;
end

always @(posedge clk) begin
    if( rst ) begin
        bank      <= 0;
        rmrd      <= 0;
        video_en  <= 0;
        roz_romrd <= 0;
        pal_bank  <= 0;
        snd_latch <= 0;
        snd_irq   <= 0;
        sirq_l    <= 0;
    end else begin
        sirq_l  <= sirq_cs & cpu_we;
        snd_irq <= sirq_cs & cpu_we & ~sirq_l;
        if( cpu_we ) begin
            if( bank_cs  ) bank <= cpu_dout[4] ? { 2'b10, cpu_dout[2:1] } : { 1'b0, cpu_dout[3:1] };
            if( ctrl_cs  ) begin
                rmrd     <= cpu_dout[2];
                video_en <= ~cpu_dout[3];
                roz_romrd <= cpu_dout[4];
                pal_bank <= cpu_dout[5];
            end
            if( latch_cs ) snd_latch <= cpu_dout;
        end
    end
end

always @(posedge clk) rst_cmb <= rst | rst8;

`ifdef SIMULATION
// trace: register/IO writes and the PC every 2^20 clocks
reg        we_l;
reg [19:0] tcnt;
always @(posedge clk) begin
    we_l <= cpu_we;
    tcnt <= tcnt + 1'd1;
    if( cpu_we && !we_l && low && A[13:10]==4'b0111 )
        $display("W %04X=%02X pc=%04X", A, cpu_dout, u_cpu.u_sys6809.reg_pc);
    if( &tcnt ) $display("PC %04X irq_n=%b", u_cpu.u_sys6809.reg_pc, irq_n);
end
`endif

// HD6309E on the board, but the game never enables native mode (no LDMD)
// and a MAME trace of attract+play shows only 6809 opcodes, so the
// plain 6809 model from JTFRAME is used.
jtframe_sys6809 #(.RAM_AW(13)) u_cpu(
    .rstn       ( ~rst_cmb  ),
    .clk        ( clk       ),
    .cen        ( cen12     ),   // E and Q at 3 MHz
    .cpu_cen    (           ),
    .VMA        (           ),
    .nIRQ       ( irq_n | ~dip_pause ),
    .nFIRQ      ( 1'b1      ),
    .nNMI       ( 1'b1      ),
    .irq_ack    (           ),
    .bus_busy   ( ~dtack    ),
    .A          ( A         ),
    .RnW        ( RnW       ),
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    ),
    .ram_dout   ( ram_dout  ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_din    ( cpu_din   )
);
`else
    assign cpu_addr=0, cpu_dout=0, cpu_we=0;
    initial begin rom_addr=0; rom_cs=0; tilesys_cs=0; objsys_cs=0; pal_cs=0; roz_vr=0; roz_io=0;
        rmrd=0; video_en=0; roz_romrd=0; snd_latch=0; snd_irq=0; st_dout=0; end
`endif
endmodule
