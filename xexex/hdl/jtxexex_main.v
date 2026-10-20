/*  This file is part of JTXEXEX.
    SPDX-License-Identifier: GPL-3.0-or-later
    Xexex main board: 68000 at 16 MHz, memory map and interrupts from MAME's xexex.cpp.
    The bus timing follows jotego's JTMOO (jtmoo_main.v, Rafael Eduardo Paiva Feener / Jose Tejada).

    Interrupts (held until acknowledged, as MAME's HOLD_LINE):
      IRQ 4  start of vertical blank (line 256), enabled by control bit 11
      IRQ 5  end of the object DMA, enabled by control bit 6
      IRQ 6  line 0, test mode only, enabled by control bit 5
    Control register (0DE000): bits 0-2 EEPROM data, chip select, clock; bit 8 sprite ROM readout;
    bit 9 disables the layer B alpha blending. */

module jtxexex_main(
    input                rst,
    input                clk,        // 48 MHz
    input                LVBL,
    input                vb_start,   // line 256
    input                line0,      // start of line 0
    input                dma_bsy,
    input         [ 8:0] vdump,

    output        [23:1] cpu_addr,
    output        [15:0] cpu_dout,
    output        [ 1:0] cpu_dsn,
    output               cpu_we,

    // ROM, 1 MB: 000000-07FFFF and 100000-17FFFF
    output        [19:1] rom_addr,
    output reg           rom_cs,
    input         [15:0] rom_data,
    input                rom_ok,
    // work RAM (BRAM)
    output reg           ram_cs,
    input         [15:0] ram_dout,

    // video chips
    output reg           tmap_reg_cs,
    output reg           tmap_ram_cs,
    output reg           lvc_ram_cs,
    output reg           lvc_reg_cs,
    output reg           obj_ram_cs,
    output reg           obj_reg_cs,
    output reg           pal_cs,
    output reg           k251_cs,
    output reg           k338_cs,
    input         [15:0] tmap_dout,
    input         [15:0] lvc_dout,
    input         [ 7:0] lvc_reg_dout,
    input         [15:0] obj_dout,
    input         [15:0] pal_dout,
    output               objcha_n,
    output               alpha_off,

    // sound
    output reg           snd_irq,    // one clock
    output               pair_we,
    input         [ 7:0] pair_dout,

    // EEPROM contents (128 x 8)
    output        [ 6:0] nv_addr,
    input         [ 7:0] nv_dout,
    output        [ 7:0] nv_din,
    output               nv_we,

    // cabinet
    input         [ 6:0] joystick1,
    input         [ 6:0] joystick2,
    input         [ 1:0] cab_1p,
    input         [ 1:0] coin,
    input                service,
    input                dip_test,
    input                dip_pause,
    output        [ 7:0] st_dout
);

wire [23:1] A;
wire        cpu_cen, cpu_cenb, UDSn, LDSn, RnW, ASn, BUSn, DTACKn;
wire [ 2:0] FC;
wire        bus_cs, bus_busy, eep_do, eep_rdy, iack;
reg  [ 2:0] IPLn;
reg  [15:0] cpu_din, ctrl;
reg         io_cs, ctrl_cs, ccu_cs, pair_cs, sirq_cs, rd_cs,
            irq4, irq5, irq6, dma_l, HALTn;

assign cpu_addr = A;
assign cpu_dsn  = { UDSn, LDSn };
assign cpu_we   = ~RnW;
assign rom_addr = { A[20], A[18:1] };
assign BUSn     = ASn | (LDSn & UDSn);
assign bus_cs   = rom_cs;
assign bus_busy = rom_cs & ~rom_ok;
assign iack     = &FC & ~ASn;
assign pair_we  = pair_cs && !RnW && !LDSn;
assign objcha_n = ~ctrl[8];
assign alpha_off=  ctrl[9];
assign st_dout  = ctrl[7:0];

always @* begin
    rom_cs      = 0;
    ram_cs      = 0;
    obj_ram_cs  = 0;
    tmap_reg_cs = 0;
    obj_reg_cs  = 0;
    rd_cs       = 0;
    lvc_ram_cs  = 0;
    lvc_reg_cs  = 0;
    k338_cs     = 0;
    k251_cs     = 0;
    ccu_cs      = 0;
    sirq_cs     = 0;
    pair_cs     = 0;
    io_cs       = 0;
    ctrl_cs     = 0;
    tmap_ram_cs = 0;
    pal_cs      = 0;
    if( !ASn && !iack ) begin
        case( A[23:16] )
            8'h00,8'h01,8'h02,8'h03,8'h04,8'h05,8'h06,8'h07,
            8'h10,8'h11,8'h12,8'h13,8'h14,8'h15,8'h16,8'h17: rom_cs = 1;
            8'h08: ram_cs     = ~BUSn;
            8'h09: obj_ram_cs = ~BUSn;      // with the mirror at 098000
            8'h0C: case( A[15:13] )
                3'd0: tmap_reg_cs = ~BUSn;  // 0C0000 K054157
                3'd1: obj_reg_cs  = ~BUSn;  // 0C2000 K053246
                3'd2: rd_cs       = ~BUSn;  // 0C4000 sprite ROM readout (not modelled)
                3'd3: lvc_ram_cs  = ~BUSn;  // 0C6000 K053250 RAM
                3'd4: lvc_reg_cs  = ~BUSn;  // 0C8000 K053250 registers
                3'd5: k338_cs     = ~BUSn;  // 0CA000 K054338
                3'd6: k251_cs     = ~BUSn;  // 0CC000 K053251
                default:;
            endcase
            8'h0D: case( A[15:13] )
                3'd0: ccu_cs  = ~BUSn;      // 0D0000 K053252
                3'd2: sirq_cs = ~BUSn;      // 0D4000 sound IRQ
                3'd3: pair_cs = ~BUSn;      // 0D6000 K054321
                // 0D8000 K054156 "b" registers: tile ROM readout banks, not modelled
                3'd5: io_cs   = ~BUSn;      // 0DA000 players
                3'd6: io_cs   = ~BUSn;      // 0DC000 system, EEPROM
                3'd7: ctrl_cs = ~BUSn;      // 0DE000 control
                default:;
            endcase
            8'h18: tmap_ram_cs = ~BUSn & ~A[15] & ~A[14];   // 180000-183FFF, two mirrors
            8'h1B: pal_cs      = ~BUSn & ~A[15] & ~A[14] & ~A[13];
            default:;
        endcase
    end
end

// KONAMI16_LSB: left, right, up, down, buttons 1-3, start; active low
function [7:0] player( input [6:0] joy, input start );
    player = { start, joy[6:4], joy[2], joy[3], joy[0], joy[1] };
endfunction

always @(posedge clk) begin
    cpu_din <= rom_cs      ? rom_data :
               ram_cs      ? ram_dout :
               obj_ram_cs  ? obj_dout :
               lvc_ram_cs  ? lvc_dout :
               lvc_reg_cs  ? { 8'd0, lvc_reg_dout } :
               tmap_ram_cs ? tmap_dout :
               pal_cs      ? pal_dout :
               pair_cs     ? { 8'd0, pair_dout } :
               ctrl_cs     ? ctrl :
               ccu_cs      ? { 8'd0, A[4:1]==4'he ? { 7'd0, vdump[8] } : A[4:1]==4'hf ? vdump[7:0] : 8'd0 } :
               io_cs       ? ( A[14:13]==2'b01 ? // 0DA000
                                { 8'hff, A[1] ? player(joystick2, cab_1p[1]) : player(joystick1, cab_1p[0]) } :
                               A[1] ? { 8'h00, 4'h0, dip_test, 1'b0, eep_rdy, eep_do } :
                                      { 8'hff, 2'b11, service, service, 2'b11, coin } ) :
               16'hffff;
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        ctrl    <= 0;
        snd_irq <= 0;
        irq4    <= 0;
        irq5    <= 0;
        irq6    <= 0;
        dma_l   <= 0;
    end else begin
        snd_irq <= 0;
        dma_l   <= dma_bsy;
        if( ctrl_cs && !RnW ) begin
            if( !UDSn ) ctrl[15:8] <= cpu_dout[15:8];
            if( !LDSn ) ctrl[ 7:0] <= cpu_dout[ 7:0];
        end
        if( sirq_cs && !RnW ) snd_irq <= 1;
        if( vb_start && ctrl[11] ) irq4 <= 1;
        if( !dma_bsy && dma_l && ctrl[6] ) irq5 <= 1;
        if( line0 && ctrl[5] ) irq6 <= 1;
        if( iack ) case( A[3:1] )
            4: irq4 <= 0;
            5: irq5 <= 0;
            6: irq6 <= 0;
            default:;
        endcase
    end
end

always @(posedge clk) begin
    IPLn  <= irq6 ? 3'b001 : irq5 ? 3'b010 : irq4 ? 3'b011 : 3'b111;
    HALTn <= dip_pause & ~rst;
end

jt5911 u_eeprom(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .sclk       ( ctrl[2]   ),
    .sdi        ( ctrl[0]   ),
    .sdo        ( eep_do    ),
    .rdy        ( eep_rdy   ),
    .scs        ( ctrl[1]   ),
    .mem_addr   ( nv_addr   ),
    .mem_din    ( nv_din    ),
    .mem_we     ( nv_we     ),
    .mem_dout   ( nv_dout   ),
    .dump_clr   ( 1'b0      ),
    .dump_flag  (           )
);

jtframe_68kdtack_cen #(.W(6),.RECOVERY(1)) u_dtack(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( bus_cs    ),
    .bus_busy   ( bus_busy  ),
    .bus_legit  ( 1'b0      ),
    .bus_ack    ( 1'b0      ),
    .ASn        ( ASn       ),
    .DSn        ({UDSn,LDSn}),
    .num        ( 5'd1      ),
    .den        ( 6'd3      ),  // 16 MHz
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
    .VPAn       ( ~iack       ),
    .FC         ( FC          ),
    .BERRn      ( 1'b1        ),
    .HALTn      ( HALTn       ),
    .BRn        ( 1'b1        ),
    .BGACKn     ( 1'b1        ),
    .BGn        (             ),
    .DTACKn     ( DTACKn      ),
    .IPLn       ( IPLn        )
);

endmodule
