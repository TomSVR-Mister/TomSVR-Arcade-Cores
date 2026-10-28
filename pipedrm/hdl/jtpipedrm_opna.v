/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * YM2608 (OPNA) for Hatris, built on jotego's jt12 YM2610B (jt10b: 6 FM channels, SSG, ADPCM-A, ADPCM-B).
 * Register map differences are translated on the bus (MAME ymfm ym2608, Yamaha YM2608 manual):
 *   port 0 10-1d rhythm  -> YM2610 port 1 00-0d (ADPCM-A: key on/dump, total level, channel level/pan)
 *   port 1 00-0b ADPCM-B -> YM2610 port 0 10-1b (control, L/R, start, stop, delta-N, level)
 *   port 1 0c-1f (limit, DAC, PCM data, flag control) and 29 (IRQ enable) are not modelled: written to an unused
 *   register. Port 1 20-2f go nowhere on the YM2608, so they are dropped too (on jt12 they are ADPCM-A addresses).
 * Rhythm: the six drums live in the YM2608's internal ROM (ym2608_adpcm_rom.bin). The MRA stores them with each
 * drum starting on a 256-byte block (the ADPCM-A address unit), padded with 0x80 (ADPCM nibbles 8, 0: the output
 * holds), and after reset this module writes the start/end blocks to the six ADPCM-A channels, as the YM2608 does
 * with its fixed addresses (ymfm: 0000-01bf, 01c0-043f, 0440-1b7f, 1b80-1cff, 1d00-1f7f, 1f80-1fff).
 * ADPCM-B counts in 32-byte steps (jtpipedrm_adpcmb_cnt), as the YM2608 does with ROM or 8-bit RAM.
 * ready stays low until the drum addresses are in; hold the sound CPU in reset until then. */
module jtpipedrm_opna(
    input                rst,
    input                clk,
    input                cen,        // 8 MHz
    input        [ 7:0]  din,
    input        [ 1:0]  addr,
    input                cs_n,
    input                wr_n,
    output reg   [ 7:0]  dout,
    output               irq_n,
    output reg           ready,

    output       [19:0]  adpcma_addr,
    output       [ 4:0]  adpcma_bank,
    output               adpcma_roe_n,
    input        [ 7:0]  adpcma_data,
    output       [23:0]  adpcmb_addr,
    output               adpcmb_roe_n,
    input        [ 7:0]  adpcmb_data,

    output signed [15:0] fm_left,
    output signed [15:0] fm_right,
    output       [ 9:0]  psg_snd
);

// drum blocks (256 bytes) in the relocated rhythm ROM: bass drum 2, snare 3, top cymbal 24, hi-hat 2, tom 3, rim 1
function [7:0] drum_start( input [2:0] ch );
    case( ch )
        0: drum_start = 8'd0;   1: drum_start = 8'd2;  2: drum_start = 8'd5;
        3: drum_start = 8'd29;  4: drum_start = 8'd31; default: drum_start = 8'd34;
    endcase
endfunction

function [7:0] drum_end( input [2:0] ch );
    case( ch )
        0: drum_end = 8'd1;   1: drum_end = 8'd4;  2: drum_end = 8'd28;
        3: drum_end = 8'd30;  4: drum_end = 8'd33; default: drum_end = 8'd34;
    endcase
endfunction

// bus translation
reg  [ 1:0] tport;              // translated port of the last address write, per CPU port
reg  [ 7:0] taddr;
reg         tp0, tp1;
wire        cpu_addr_wr = !cs_n && !wr_n && !addr[0];

always @* begin
    tport = { addr[1], 1'b0 };
    taddr = din;
    if( !addr[1] ) begin
        if( din[7:4]==4'h1 && din[3:0]<=4'hd ) begin tport = 2'b10; taddr = { 4'h0, din[3:0] }; end
        else if( din[7:4]==4'h1 || din==8'h29 ) taddr = 8'hff;
    end else begin
        if( din<=8'h0b )      begin tport = 2'b00; taddr = { 4'h1, din[3:0] }; end
        else if( din<8'h30 ) begin tport = 2'b00; taddr = 8'hff; end
    end
end

always @(posedge clk) begin
    if( rst ) begin
        tp0 <= 0; tp1 <= 1;
    end else if( cpu_addr_wr ) begin
        if( addr[1] ) tp1 <= tport[1]; else tp0 <= tport[1];
    end
end

// drum address writes after reset: 6 channels x (start lo, start hi, end lo, end hi), port 1 regs 10/18/20/28 + ch
reg  [ 4:0] istep;      // channel * 4 + register
reg  [ 1:0] iphase;
reg  [10:0] icnt;
reg  [ 7:0] i_din;
reg  [ 1:0] i_addr;
reg         i_cs;
wire [ 2:0] ich  = istep[4:2];
wire [ 7:0] ireg = { 2'b00, istep[1:0]==0 ? 3'd2 : istep[1:0]==1 ? 3'd3 : istep[1:0]==2 ? 3'd4 : 3'd5, ich };
wire [ 7:0] ival = istep[1:0]==0 ? drum_start(ich) : istep[1:0]==2 ? drum_end(ich) : 8'd0;

always @(posedge clk) begin
    if( rst ) begin
        ready <= 0; istep <= 0; iphase <= 0; icnt <= 0; i_cs <= 0; i_addr <= 0; i_din <= 0;
    end else if( !ready ) begin
        icnt <= icnt + 11'd1;
        // one bus access per 1024 clocks (21 us at 48 MHz): ADPCM-A takes start/end when the channel slot passes.
        // iphase 1: address prepared, written in this period; 2: data; 0: idle period, next register
        i_cs <= icnt[10:3]==0 && iphase!=0;
        if( icnt==11'h7ff ) begin
            case( iphase )
                0: begin i_addr <= 2'b10; i_din <= ireg; iphase <= 1; end
                1: begin i_addr <= 2'b11; i_din <= ival; iphase <= 2; end
                default: begin
                    if( istep==5'd23 ) ready <= 1;
                    istep  <= istep + 5'd1;
                    iphase <= 0;
                end
            endcase
        end
    end
end

wire [ 7:0] j_din  = !ready ? i_din  : !addr[0] ? taddr : din;
// reads: 0 and 2 status (busy, timer flags), 1 SSG data
wire [ 1:0] j_addr = !ready ? i_addr : wr_n ? { 1'b0, addr[0] & ~addr[1] } :
                    !addr[0] ? { tport[1], 1'b0 } : { addr[1] ? tp1 : tp0, 1'b1 };
wire        j_cs_n = !ready ? ~i_cs  : cs_n;
wire        j_wr_n = !ready ? ~i_cs  : wr_n;
wire [ 7:0] j_dout;

// port 3 reads ADPCM-B data on the YM2608 (not modelled)
always @* begin
    dout = addr==2'd3 ? 8'd0 : j_dout;
end

wire signed [15:0] fm_only_l, fm_only_r, adpcma_l, adpcma_r, adpcmb_l, adpcmb_r;

jt10b_mixer u_left(
    .clk       ( clk          ),
    .cen       ( cen          ),
    .fm_in     ( fm_only_l    ),
    .adpcma_in ( adpcma_l     ),
    .adpcmb_in ( adpcmb_l     ),
    .psg_in    ( psg_snd      ),
    .fm_out    ( fm_left      ),
    .snd_out   (              )
);

jt10b_mixer u_right(
    .clk       ( clk          ),
    .cen       ( cen          ),
    .fm_in     ( fm_only_r    ),
    .adpcma_in ( adpcma_r     ),
    .adpcmb_in ( adpcmb_r     ),
    .psg_in    ( psg_snd      ),
    .fm_out    ( fm_right     ),
    .snd_out   (              )
);

jtpipedrm_opn_top #(
    .use_lfo(1), .use_ssg(1), .num_ch(6), .use_pcm(0), .use_adpcm(1),
    .FULLFM(1), .JT49_DIV(3)
) u_jt12(
    .rst            ( rst          ),
    .clk            ( clk          ),
    .cen            ( cen          ),
    .din            ( j_din        ),
    .addr           ( j_addr       ),
    .cs_n           ( j_cs_n       ),
    .wr_n           ( j_wr_n       ),

    .dout           ( j_dout       ),
    .irq_n          ( irq_n        ),
    .adpcma_addr    ( adpcma_addr  ),
    .adpcma_bank    ( adpcma_bank  ),
    .adpcma_roe_n   ( adpcma_roe_n ),
    .adpcma_data    ( adpcma_data  ),
    .adpcmb_addr    ( adpcmb_addr  ),
    .adpcmb_roe_n   ( adpcmb_roe_n ),
    .adpcmb_data    ( adpcmb_data  ),
    .psg_A          (              ),
    .psg_B          (              ),
    .psg_C          (              ),
    .psg_snd        ( psg_snd      ),
    .fm_snd_left    ( fm_only_l    ),
    .fm_snd_right   ( fm_only_r    ),
    .adpcmA_l       ( adpcma_l     ),
    .adpcmA_r       ( adpcma_r     ),
    .adpcmB_l       ( adpcmb_l     ),
    .adpcmB_r       ( adpcmb_r     ),
    .IOA_in         ( 8'b0         ),
    .IOB_in         ( 8'b0         ),
    .IOA_out        (              ),
    .IOB_out        (              ),
    .IOA_oe         (              ),
    .IOB_oe         (              ),
    .debug_bus      ( 8'd0         ),
    .snd_right      (              ),
    .snd_left       (              ),
    .snd_sample     (              ),
    .ch_enable      ( 6'h3f        ),
    .en_hifi_pcm    ( 1'b0         ),
    .debug_view     (              )
);

endmodule
