/* SPDX-License-Identifier: GPL-3.0-or-later
   Operation Thunderbolt main board: 68000 at 12 MHz, TC0220IOC inputs, 93C46 EEPROM, ADC0808 gun pots.
   Memory map from MAME othunder.cpp; CPU glue after jotego's jttaitox_main */

module jtothunder_main(
    input                rst,
    input                clk,
    input                LVBL,

    output               cpu_cen,
    output        [23:1] cpu_addr,
    output        [15:0] cpu_dout,
    output               cpu_rnw,
    output        [ 1:0] cpu_dsn,

    output reg           rom_cs,
    output        [18:1] rom_addr,
    input         [15:0] rom_data,
    input                rom_ok,

    output        [ 1:0] ram_we,
    input         [15:0] ram_dout,

    // video chips
    output reg           scn_cs,     // 200000-20ffff RAM
    output reg           ctl_cs,     // 220000-22000f control
    output reg           pcr_cs,     // 100000-100007 palette
    output reg           obj_cs,     // 400000-4005ff sprite RAM
    input         [15:0] vid_dout,

    // TC0140SYT
    output reg           syt_cs,
    input         [ 3:0] syt_dout,

    // cabinet
    input         [ 5:0] joystick1,
    input         [ 5:0] joystick2,
    input         [ 1:0] cab_1p,
    input         [ 1:0] coin,
    input                service,
    input                dip_pause,
    input         [15:0] dipsw,
    input         [ 7:0] adc0, adc1, adc2, adc3,   // P1X P1Y P2X P2Y

    // EEPROM default contents and NVRAM
    input         [ 6:0] prog_addr,
    input         [ 7:0] prog_data,
    input                prog_we,
    output        [ 7:0] prog_din,

    output        [ 7:0] st_dout
);
`ifndef NOMAIN
wire [23:1] A;
wire        UDSn, LDSn, RnW, ASn, VPAn, DTACKn, cpu_cenb, bus_busy, LWRn, sdo;
wire [ 2:0] FC;
reg  [ 2:0] IPLn;
reg  [15:0] cpu_din;
reg  [ 7:0] ioc_dout, adc_dout, ioc4, eep;
reg  [ 1:0] adc_ch;
reg  [12:0] adc_cnt;
reg         ram_cs, ioc_cs, adc_cs, ack_cs, irq5, irq6, adc_busy, lvbl_l, LWRn_l;

assign cpu_addr = A;
assign rom_addr = A[18:1];
assign cpu_dsn  = { UDSn, LDSn };
assign cpu_rnw  = RnW;
assign LWRn     = RnW | LDSn;
assign ram_we   = {2{ram_cs & ~RnW}} & ~{UDSn,LDSn};
assign VPAn     = !(!ASn && FC==7);
assign bus_busy = rom_cs & ~rom_ok;
assign st_dout  = eep;

always @* begin
    rom_cs = 0; ram_cs = 0; ioc_cs = 0; pcr_cs = 0; scn_cs = 0; ctl_cs = 0;
    syt_cs = 0; obj_cs = 0; adc_cs = 0; ack_cs = 0;
    if( !ASn && {UDSn,LDSn}!=2'b11 && ~&FC ) case( A[23:16] )
        8'h00,8'h01,8'h02,8'h03,
        8'h04,8'h05,8'h06,8'h07: rom_cs = 1;
        8'h08: ram_cs = 1;
        8'h09: ioc_cs = 1;
        8'h10: pcr_cs = 1;
        8'h20: scn_cs = 1;
        8'h22: ctl_cs = 1;
        8'h30: syt_cs = 1;
        8'h40: obj_cs = 1;
        8'h50: adc_cs = 1;
        8'h60: ack_cs = 1;
        default:;
    endcase
end

// TC0220IOC, byte wide at odd addresses
always @(posedge clk) begin
    case( A[3:1] )
        0: ioc_dout <= dipsw[7:0];
        1: ioc_dout <= dipsw[15:8];
        2: ioc_dout <= { cab_1p[1], cab_1p[0], 1'b1, service, coin[0], coin[1], 2'b11 };
        3: ioc_dout <= { sdo, 7'd0 };
        4: ioc_dout <= ioc4;
        7: ioc_dout <= { 4'hf, joystick2[5], joystick1[5], joystick2[4], joystick1[4] };
        default: ioc_dout <= 8'hff;
    endcase
end

always @(posedge clk) begin
    cpu_din <= rom_cs ? rom_data :
               ram_cs ? ram_dout :
               (scn_cs | ctl_cs | pcr_cs | obj_cs) ? vid_dout :
               ioc_cs ? { 8'hff, ioc_dout } :
               adc_cs ? { 8'hff, adc_dout } :
               syt_cs ? { 12'hfff, syt_dout } : 16'hffff;
end

// interrupts: vertical blank on level 5, ADC end of conversion on level 6
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        irq5 <= 0; irq6 <= 0; ioc4 <= 0; eep <= 0; adc_busy <= 0; adc_ch <= 0; adc_cnt <= 0;
        adc_dout <= 0; lvbl_l <= 0; LWRn_l <= 1;
    end else begin
        lvbl_l <= LVBL;
        LWRn_l <= LWRn;
        if( !LVBL && lvbl_l && dip_pause ) irq5 <= 1;
        if( !LWRn && LWRn_l ) begin
            if( ack_cs ) begin
                if( A[1] ) irq6 <= 0; else irq5 <= 0;
            end
            if( ioc_cs && A[3:1]==3 ) eep  <= cpu_dout[7:0];
            if( ioc_cs && A[3:1]==4 ) ioc4 <= cpu_dout[7:0];
            if( adc_cs ) begin   // any write selects the channel by its offset and starts a conversion
                adc_ch   <= A[2:1];
                adc_busy <= 1;
                adc_cnt  <= 0;
            end
        end
        if( adc_busy ) begin
            adc_cnt <= adc_cnt + 1'd1;
            if( &adc_cnt ) begin   // about 150 us, the ADC0808 takes 64 clocks at 500 kHz
                adc_busy <= 0;
                irq6     <= 1;
                case( adc_ch )
                    0: adc_dout <= adc0;
                    1: adc_dout <= adc1;
                    2: adc_dout <= adc2;
                    3: adc_dout <= adc3;
                endcase
            end
        end
    end
end

always @(posedge clk) IPLn <= irq6 ? 3'b001 : irq5 ? 3'b010 : 3'b111;

jt9346_16b8b #(.DW(16),.AW(6)) u_eeprom(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .sclk       ( eep[5]    ),
    .sdi        ( eep[6]    ),
    .sdo        ( sdo       ),
    .scs        ( eep[4]    ),
    .dump_clk   ( clk       ),
    .dump_addr  ({1'b0,prog_addr}),
    .dump_we    ( prog_we   ),
    .dump_din   ( prog_data ),
    .dump_dout  ( prog_din  ),
    .dump_flag  (           ),
    .dump_clr   ( 1'b0      )
);

jtframe_68kdtack_cen #(.W(6)) u_dtack(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( rom_cs    ),
    .bus_busy   ( bus_busy  ),
    .bus_legit  ( 1'b0      ),
    .bus_ack    ( 1'b0      ),
    .ASn        ( ASn       ),
    .DSn        ({UDSn,LDSn}),
    .num        ( 5'd9      ), // 12 MHz from 53.37 MHz
    .den        ( 6'd40     ),
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
    .HALTn      ( 1'b1        ),
    .BRn        ( 1'b1        ),
    .BGACKn     ( 1'b1        ),
    .BGn        (             ),

    .DTACKn     ( DTACKn      ),
    .IPLn       ( IPLn        )
);
`else
assign cpu_addr=0, cpu_dout=0, cpu_rnw=1, cpu_dsn=3, cpu_cen=0, rom_addr=0, ram_we=0, prog_din=0, st_dout=0;
initial begin rom_cs=0; scn_cs=0; ctl_cs=0; pcr_cs=0; obj_cs=0; syt_cs=0; end
`endif
endmodule
