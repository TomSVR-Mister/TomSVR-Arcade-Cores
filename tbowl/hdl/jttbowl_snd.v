/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Board 6206A sound (MAME tecmo/tbowl.cpp _6206A_map): Z80 at 4 MHz, NMI while the sound latch is pending (cleared by
 * the e006 acknowledge write, not by reading), INT from the first YM3812. Two YM3812 at 4 MHz, two MSM5205 at
 * 384 kHz / 48 (8 kHz) fed nibble by nibble (high first) from 256-byte aligned blocks of their own 64 kB ROM.
 *   0000-7fff ROM   c000-c7ff RAM   d000-d001 YM 1   d800-d801 YM 2
 *   e000/e001 ADPCM 1/2 end block   e002/e003 start block (starts playing)   e004/e005 volume (bits 6-0)
 *   e006 latch acknowledge   e010 latch read */
module jttbowl_snd(
    input              rst,
    input              clk,
    input              cen,         // 4 MHz
    input              cen_fm,      // 4 MHz
    input              cen_pcm,     // 384 kHz
    input       [ 7:0] latch,
    input              pending,
    output reg         ack,
    // ROM
    output      [14:0] rom_addr,
    output reg         rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output      [16:0] pcm0_addr,
    output             pcm0_cs,
    input       [ 7:0] pcm0_data,
    input              pcm0_ok,
    output      [16:0] pcm1_addr,
    output             pcm1_cs,
    input       [ 7:0] pcm1_data,
    input              pcm1_ok,
    // sound
    output signed [15:0] fm0,
    output signed [15:0] fm1,
    output signed [11:0] pcm0,
    output signed [11:0] pcm1
);

wire [15:0] A;
wire [ 7:0] dout, ram_dout, fm0_dout;
wire        rd_n, wr_n, mreq_n, iorq_n, rfsh_n, m1_n, fm_irqn;
reg  [ 7:0] din;
reg         ram_cs, rstn, wr_l;
wire        mem    = !mreq_n && rfsh_n;
wire        fm0_cs = mem && A[15:11]==5'b11010;
wire        fm1_cs = mem && A[15:11]==5'b11011;
wire        ctl_cs = mem && A[15:12]==4'he;
wire        wr     = ctl_cs && !wr_n && !wr_l;

assign rom_addr = A[14:0];

always @(posedge clk) rstn <= ~rst;

always @* begin
    rom_cs = mem && !A[15];
    ram_cs = mem && A[15:11]==5'b11000;
end

always @(posedge clk) begin
    din <= rom_cs ? rom_data : ram_cs ? ram_dout :
           fm0_cs ? fm0_dout :
           (ctl_cs && A[4]) ? latch : 8'h00;
end

// ---------------- ADPCM control ----------------
reg  [ 7:0] start0, start1, end0, end1;
reg  [ 6:0] vol0, vol1;
reg         go0, go1;

always @(posedge clk) begin
    wr_l <= ctl_cs && !wr_n;
    ack  <= 0;
    go0  <= 0;
    go1  <= 0;
    if( rst ) begin
        start0 <= 0; start1 <= 0; end0 <= 0; end1 <= 0; vol0 <= 7'h7f; vol1 <= 7'h7f;
    end else if( wr && !A[4] ) case( A[2:0] )
        3'd0: end0   <= dout;
        3'd1: end1   <= dout;
        3'd2: begin start0 <= dout; go0 <= 1; end
        3'd3: begin start1 <= dout; go1 <= 1; end
        3'd4: vol0   <= dout[6:0];
        3'd5: vol1   <= dout[6:0];
        3'd6: ack    <= 1;
        default:;
    endcase
end

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( rstn        ),
    .clk        ( clk         ),
    .cen        ( cen         ),
    .cpu_cen    (             ),
    .int_n      ( fm_irqn     ),
    .nmi_n      ( ~pending    ),
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
    .cpu_dout   ( dout        ),
    .ram_dout   ( ram_dout    ),
    .ram_cs     ( ram_cs      ),
    .rom_cs     ( rom_cs      ),
    .rom_ok     ( rom_ok      )
);

jtopl2 u_fm0(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen        ( cen_fm      ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm0_cs     ),
    .wr_n       ( wr_n        ),
    .dout       ( fm0_dout    ),
    .irq_n      ( fm_irqn     ),
    .snd        ( fm0         ),
    .sample     (             )
);

jtopl2 u_fm1(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen        ( cen_fm      ),
    .din        ( dout        ),
    .addr       ( A[0]        ),
    .cs_n       ( ~fm1_cs     ),
    .wr_n       ( wr_n        ),
    .dout       (             ),
    .irq_n      (             ),
    .snd        ( fm1         ),
    .sample     (             )
);

jttbowl_adpcm u_pcm0(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen        ( cen_pcm     ),
    .go         ( go0         ),
    .start      ( start0      ),
    .stop       ( end0        ),
    .vol        ( vol0        ),
    .rom_addr   ( pcm0_addr   ),
    .rom_cs     ( pcm0_cs     ),
    .rom_data   ( pcm0_data   ),
    .rom_ok     ( pcm0_ok     ),
    .bank       ( 1'b0        ),
    .snd        ( pcm0        )
);

jttbowl_adpcm u_pcm1(
    .rst        ( rst         ),
    .clk        ( clk         ),
    .cen        ( cen_pcm     ),
    .go         ( go1         ),
    .start      ( start1      ),
    .stop       ( end1        ),
    .vol        ( vol1        ),
    .rom_addr   ( pcm1_addr   ),
    .rom_cs     ( pcm1_cs     ),
    .rom_data   ( pcm1_data   ),
    .rom_ok     ( pcm1_ok     ),
    .bank       ( 1'b1        ),
    .snd        ( pcm1        )
);

endmodule

// One MSM5205 with its address counter (MAME tbowl_state::adpcm_int): at every VCK the next nibble is sent, high
// nibble first; the chip is held in reset once the address reaches the end block.
module jttbowl_adpcm(
    input              rst,
    input              clk,
    input              cen,
    input              go,
    input       [ 7:0] start,
    input       [ 7:0] stop,
    input       [ 6:0] vol,
    input              bank,
    output      [16:0] rom_addr,
    output             rom_cs,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output reg signed [11:0] snd
);

reg  [15:0] pos;
reg         msm_rst, low, run;
reg  [ 3:0] nib;
reg  [ 7:0] byte_l;
wire        vck;
wire signed [11:0] raw;
wire signed [19:0] scaled = raw * $signed({1'b0, vol});

assign rom_addr = { bank, pos };
assign rom_cs   = run;

always @(posedge clk) begin
    if( rst ) begin
        pos <= 0; msm_rst <= 1; low <= 0; run <= 0; nib <= 0;
    end else begin
        if( go ) begin
            pos <= { start, 8'd0 }; msm_rst <= 0; run <= 1;     // MAME keeps a pending low nibble
        end else if( vck ) begin
            if( !run || pos[15:8] > stop ) begin
                msm_rst <= 1; run <= 0;
            end else if( low ) begin
                nib <= byte_l[3:0]; low <= 0;
            end else begin
                nib    <= rom_data[7:4];
                byte_l <= rom_data;
                pos    <= pos + 1'd1;
                low    <= 1;
            end
        end
    end
end

always @(posedge clk) snd <= msm_rst ? 12'd0 : scaled[18:7];

jt5205 u_msm(
    .rst        ( rst | msm_rst ),
    .clk        ( clk         ),
    .cen        ( cen         ),
    .sel        ( 2'b10       ),    // S48: 384 kHz / 48 = 8 kHz
    .din        ( nib         ),
    .sound      ( raw         ),
    .sample     (             ),
    .irq        ( vck         ),     // VCK strobe, also while in reset (MAME vck_legacy_callback)
    .vclk_o     (             )
);

endmodule
