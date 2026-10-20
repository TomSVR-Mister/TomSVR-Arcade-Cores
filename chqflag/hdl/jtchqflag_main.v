/* SPDX-License-Identifier: GPL-3.0-or-later
   Chequered Flag main board: Konami 052001 CPU (jtkcpu) at 12 MHz, memory map from MAME chqflag.cpp */

module jtchqflag_main(
    input               rst,
    input               clk,
    input               cen_ref,
    output              cpu_cen,

    output      [15:0]  cpu_addr,
    output      [ 7:0]  cpu_dout,
    output              cpu_we,

    output reg  [18:0]  rom_addr,
    input       [ 7:0]  rom_data,
    output reg          rom_cs,
    input               rom_ok,
    // work RAM (BRAM)
    output              ram_we,
    input       [ 7:0]  ram_dout,
    // cabinet I/O
    input       [ 1:0]  cab_1p,
    input       [ 1:0]  coin,
    input       [ 6:0]  joystick1,
    input       [15:0]  joyana,
    input               service,
    input               lvbl,
    input               dip_test,
    input               dip_pause,
    input       [23:0]  dipsw,

    // video
    input               irq_n,
    input               nmi_n,
    output reg          objsys_cs,
    output reg          pal_cs,
    output reg          roza_vr, roza_io,
    output reg          rozb_vr, rozb_io,
    output reg  [ 7:0]  vreg,
    input       [ 7:0]  objsys_dout, pal_dout, roza_dout, rozb_dout, roz_rom,
    input               roza_ok, rozb_ok,
    // sound
    output reg  [ 7:0]  snd_latch, snd_latch2,
    output reg          snd_irq,     // pulse on writes to 3001
    // Debug
    input       [ 7:0]  debug_bus,
    output reg  [ 7:0]  st_dout
);
`ifndef NOMAIN
wire [ 7:0] Aupper, prot_dout;
wire [15:0] A, pcbad;
wire        buserror;
reg  [ 7:0] cpu_din, cab_dout, adc_res, wheel;
reg  [ 5:0] bank;
reg  [12:0] adc_cnt;
reg         ram_cs, bank_cs, vreg_cs, latch_cs, latch2_cs, prot_cs, asel_cs, adc_cs,
            in_cs, banked, fixed, berr_l, rst_cmb, asel, adc_busy, adc_intr,
            shift, b3_l, lvbl_l, roz_rd, l2_l, adw_l, adr_l;
wire        dtack, cpu_rd;

assign cpu_rd = ~cpu_we;
assign cpu_addr = A;
assign ram_we = ram_cs & cpu_we;
assign dtack  = (~rom_cs | rom_ok) & (~roz_rd | (roza_vr ? roza_ok : rozb_ok));

always @* begin
    roz_rd = (roza_vr | rozb_vr) & vreg[4] & cpu_rd;
    st_dout = debug_bus[0] ? pcbad[7:0] : { 2'd0, bank };
end

always @(*) begin
    ram_cs = 0; pal_cs = 0; roza_vr = 0; roza_io = 0; rozb_vr = 0; rozb_io = 0;
    objsys_cs = 0; latch_cs = 0; latch2_cs = 0; bank_cs = 0; vreg_cs = 0;
    in_cs = 0; prot_cs = 0; asel_cs = 0; adc_cs = 0; banked = 0; fixed = 0;
    case( A[15:12] )
        4'h0: ram_cs = 1;
        4'h1: if( !bank[5] ) ram_cs = 1; else if( !A[11] ) roza_vr = 1; else pal_cs = 1;
        4'h2: if( !A[11] ) objsys_cs = 1; else rozb_vr = 1;
        4'h3: case( A[11:8] )
            4'h0: case( A[1:0] )
                0: latch_cs  = 1;
                1: latch2_cs = 1;
                2: bank_cs   = 1;
                3: vreg_cs   = 1;
            endcase
            4'h1, 4'h2: in_cs = 1;
            4'h4: prot_cs = 1;
            4'h5: roza_io = 1;
            4'h6: rozb_io = 1;
            4'h7: case( A[1:0] )
                0: asel_cs = 1;
                1: in_cs   = 1;
                2: adc_cs  = 1;
                default:;
            endcase
            default:;
        endcase
        4'h4,4'h5,4'h6,4'h7: banked = 1;
        default: fixed = 1;
    endcase
    rom_cs   = banked | fixed;
    rom_addr = fixed ? { 4'd9, A[14:0] } : { bank[4:0], A[13:0] };
end

// input ports (all active low except where noted)
always @(posedge clk) begin
    case( {A[9:8],A[1:0]} )
        4'b01_00: cab_dout <= dipsw[7:0];                                            // 3100 DSW1
        4'b10_00: cab_dout <= { dipsw[18] & dip_test, dipsw[17:16], 1'b1,
                                cab_1p[0], service, coin[1], coin[0] };              // 3200 IN1
        4'b10_01: cab_dout <= { dipsw[19], 7'h7f };                                  // 3201 IN0
        4'b10_11: cab_dout <= dipsw[15:8];                                           // 3203 DSW2
        default:  cab_dout <= { adc_intr, 3'd0, 2'b11, joystick1[5], shift };        // 3701 IN2
    endcase
end

always @* begin
    cpu_din = rom_cs    ? rom_data    :
              ram_cs    ? ram_dout    :
              pal_cs    ? pal_dout    :
              objsys_cs ? objsys_dout :
              roza_vr   ? (vreg[4] ? roz_rom : roza_dout) :
              rozb_vr   ? (vreg[4] ? roz_rom : rozb_dout) :
              prot_cs   ? prot_dout   :
              adc_cs    ? adc_res     :
              in_cs     ? cab_dout    : 8'hff;
end

// Accelerator (button 1 or analog stick up) and steering wheel (joystick or analog stick).
// MAME ranges: pedal 38-A0, wheel 60-A0 centred at 80
wire [7:0] pedal = !joystick1[4] ? 8'ha0 : 8'h38;
wire signed [7:0] anax = joyana[7:0];
wire [7:0] wheel_tgt = (anax > 8'sd8 || anax < -8'sd8) ? 8'h80 + {{2{anax[7]}}, anax[7:2]} :
                       !joystick1[1] ? 8'h60 : !joystick1[0] ? 8'ha0 : 8'h80;

always @(posedge clk) begin
    if( rst ) begin
        bank     <= 0;
        vreg     <= 0;
        asel     <= 0;
        adc_busy <= 0;
        adc_intr <= 1;
        adc_cnt  <= 0;
        berr_l   <= 0;
        shift    <= 1;
        wheel    <= 8'h80;
        snd_irq  <= 0;
    end else begin
        snd_irq <= 0;
        lvbl_l  <= lvbl;
        b3_l    <= joystick1[6];
        if( buserror ) berr_l <= 1;
        if( b3_l && !joystick1[6] ) shift <= ~shift;   // gear shift toggles, like MAME's PORT_TOGGLE
        if( !lvbl && lvbl_l ) begin                     // move the wheel by 3 units per frame
            if( wheel < wheel_tgt ) wheel <= wheel_tgt-wheel < 3 ? wheel_tgt : wheel + 8'd3;
            if( wheel > wheel_tgt ) wheel <= wheel-wheel_tgt < 3 ? wheel_tgt : wheel - 8'd3;
        end
        l2_l  <= latch2_cs & cpu_we;
        adw_l <= adc_cs & cpu_we;
        adr_l <= adc_cs & ~cpu_we;
        if( latch2_cs & cpu_we & ~l2_l ) snd_irq <= 1;
        if( cpu_we ) begin
            if( latch_cs  ) snd_latch  <= cpu_dout;
            if( latch2_cs ) snd_latch2 <= cpu_dout;
            if( bank_cs && cpu_dout[4:0]<5'd20 ) bank[4:0] <= cpu_dout[4:0];
            if( bank_cs ) bank[5] <= cpu_dout[5];
            if( vreg_cs ) vreg <= cpu_dout;
            if( asel_cs ) asel <= cpu_dout[0];
        end
        // ADC0804: a write starts a conversion (~100 us), a read clears INTR (bit 7 of IN2, low = ready)
        if( adc_busy ) begin
            adc_cnt <= adc_cnt + 1'd1;
            if( &adc_cnt ) begin
                adc_busy <= 0;
                adc_intr <= 0;
                adc_res  <= asel ? wheel : pedal;
            end
        end
        if( adc_cs &  cpu_we & ~adw_l ) begin adc_busy <= 1; adc_cnt <= 0; end
        if( adc_cs & ~cpu_we & ~adr_l ) adc_intr <= 1;
    end
end

jt051733 u_prot(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .cen    ( cpu_cen   ),
    .addr   ( A[4:0]    ),
    .wr_n   ( ~cpu_we   ),
    .cs     ( prot_cs   ),
    .din    ( cpu_dout  ),
    .dout   ( prot_dout )
);

always @(posedge clk) rst_cmb <= rst;

jtkcpu u_cpu(
    .rst    ( rst_cmb   ),
    .clk    ( clk       ),
    .cen2   ( cen_ref   ),
    .cen_out( cpu_cen   ),

    .halt   ( berr_l    ),
    .dtack  ( dtack     ),
    .nmi_n  ( nmi_n     ),
    .irq_n  ( irq_n | ~dip_pause ),
    .firq_n ( 1'b1      ),
    .pcbad  ( pcbad     ),
    .buserror( buserror ),

    // memory bus
    .din    ( cpu_din   ),
    .dout   ( cpu_dout  ),
    .addr   ({Aupper, A}),
    .we     ( cpu_we    )
);
`else
    assign cpu_cen=0, cpu_addr=0, cpu_dout=0, cpu_we=0, ram_we=0;
    initial begin rom_addr=0; rom_cs=0; objsys_cs=0; pal_cs=0; roza_vr=0; roza_io=0; rozb_vr=0; rozb_io=0;
        vreg=0; snd_latch=0; snd_latch2=0; snd_irq=0; st_dout=0; end
`endif
endmodule
