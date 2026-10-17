/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hot Blocks - Tetrix II (MAME hotblock.cpp) on JTFRAME (Jose Tejada, jotego). Personal build.
 * CPU: 8088-compatible MCL86 core (Ted Fried, MIT licence) in maximum mode with the KF8288 bus controller (kitune-san, MIT),
 *   8 MHz pin clock, core logic on the 96 MHz clock (the board has a NEC V20; the code uses 8088 opcodes only).
 *   00000-0ffff RAM   10000-1ffff video window (port 0 bit 5 = palette 0x200 bytes, else 64 kB frame buffer RAM)
 *   20000-fffff ROM   NMI at vblank.
 *   I/O: 0000 port 0 (bit 6 video on, bit 5 window select), 0004 24C02 (write bit 1 SCL, bit 0 SDA; read SDA),
 *        8000 AY-3-8910 address, 8001 AY data (port A = P1, port B = P2). */

module jthotblk_game(
    `include "jtframe_game_ports.inc"
);

wire [19:0] A = A_l;
wire [ 7:0] cpu_dout8;
reg  [ 7:0] din, port0;
wire [19:0] ad;
wire [ 2:0] cpu_st;
wire        ale, mrd_n, mwr_n, iord_n, iowr_n, inta_n;
wire        rd_n = mrd_n & iord_n, wr_n = mwr_n & iowr_n;
wire        iom  = !(iord_n & iowr_n);
reg  [19:0] A_l;
reg         ce_pos, ce_neg;
reg  [ 3:0] ccnt;
reg         cpu_clk;
wire        vbl_irq;
wire        mem_cs  = !iom && (!rd_n || !wr_n);
wire        io_cs   = iom && (!rd_n || !wr_n) && inta_n;
wire        wram_cs = mem_cs && A[19:16]==4'h0;
wire        vid_cs  = mem_cs && A[19:16]==4'h1;
wire        rom_cs  = mem_cs && A[19:17]!=0 && !rd_n;
wire        ay_cs   = io_cs && A[15:1]==15'h4000;
reg         scl, sdaw;
wire        sda;
wire [ 7:0] ay_dout;
wire [ 7:0] p1, p2;
wire        ready;
reg  [ 2:0] wr_sh;
wire        wr     = !wr_n && wr_sh==0;     // the data bus carries the address for the first clocks of WR_n: wait until it settles

assign dip_flip   = 1'b0;
assign debug_view = 8'd0;
assign cpu_dout   = cpu_dout8;
`ifdef JTFRAME_IOCTL_RD
assign ioctl_din  = 8'd0;
`endif

// inputs, active low: coin, start, up, down, left, right, button 1, button 2
assign p1 = { joystick1[5], joystick1[4], joystick1[0], joystick1[1], joystick1[2], joystick1[3], cab_1p[0], coin[0] };
assign p2 = { joystick2[5], joystick2[4], joystick2[0], joystick2[1], joystick2[2], joystick2[3], cab_1p[1], coin[1] };

assign main_addr  = A;
assign main_cs    = rom_cs;
assign ready      = !(rom_cs && !main_ok);
assign wram_addr  = A[15:0];
assign wram_we    = wram_cs && wr;
assign vram_addr  = A[15:0];
assign vram_we    = vid_cs && !port0[5] && wr;
assign pallo_addr = A[8:1];
assign pallo_we   = vid_cs && port0[5] && !A[0] && wr;
assign palhi_addr = A[8:1];
assign palhi_we   = vid_cs && port0[5] &&  A[0] && wr;

// 8 MHz CPU pin clock from 96 MHz (the CPU core runs on clk)
always @(posedge clk) begin
    ccnt    <= ccnt==11 ? 4'd0 : ccnt + 1'd1;
    cpu_clk <= ccnt < 6;
    ce_pos  <= ccnt==0;     // same edge as cpu_clk rising
    ce_neg  <= ccnt==6;
end

always @(posedge clk) if( ale ) A_l <= ad;

always @(posedge clk) begin
    din <= rom_cs  ? main_data :
           wram_cs ? wram_dout :
           vid_cs  ? (port0[5] ? (A[0] ? palhi_dout : pallo_dout) : vram_dout) :
           io_cs   ? ( A[15:0]==16'h0004 ? { 7'd0, sda } : ay_cs ? ay_dout : 8'hff ) :
           8'hff;
end

always @(posedge clk) wr_sh <= { wr_sh[1:0], wr_n };

always @(posedge clk) begin
    if( rst ) begin
        port0 <= 0; scl <= 1; sdaw <= 1;
    end else if( io_cs && wr ) begin
        if( A[15:0]==16'h0000 ) port0 <= cpu_dout8;
        if( A[15:0]==16'h0004 ) begin scl <= cpu_dout8[1]; sdaw <= cpu_dout8[0]; end
    end
end

`ifdef SIMULATION
reg [19:0] dbg_n=0; reg [9:0] dbg_e=0; reg rd_l=1, wr_l2=1; reg [31:0] dbg_t=0;
always @(posedge clk) dbg_t <= dbg_t + 1;
reg [5:0] dbg_s, dbg_sl;
always @(posedge clk) begin
    dbg_s  <= { ale, rd_n, wr_n, ready, main_ok, main_cs };
    dbg_sl <= dbg_s;
    if( dbg_n>=1 && dbg_n<=4 && dbg_s!=dbg_sl ) $display("t=%0d ale=%b rd=%b wr=%b rdy=%b ok=%b cs=%b A=%05X clk=%b", dbg_t, dbg_s[5], dbg_s[4], dbg_s[3], dbg_s[2], dbg_s[1], dbg_s[0], A, cpu_clk);
end
always @(posedge clk) begin
    rd_l <= rd_n; wr_l2 <= wr_n;
    if( !rd_n && rd_l ) begin
        dbg_n <= dbg_n + 1'd1;
        if( dbg_n[15:0]==0 ) $display("RD %s %05X n=%0d t=%0t rdy=%b", iom ? "IO " : "MEM", A, dbg_n, dbg_t, ready);
    end
    if( !wr_n && wr_l2 && iom && dbg_e < 600 ) begin $display("E W %04X %02X", A[15:0], cpu_dout8); dbg_e <= dbg_e + 1'd1; end
    if( !rd_n && rd_l && iom && A[15:0]==4 && dbg_e < 600 ) begin $display("E R sda=%b", sda); dbg_e <= dbg_e + 1'd1; end
end
`endif

// the microcode counts 8088 cycles in units of a 100 MHz core at 4.77 MHz: 4 core clocks per tick, 7 per tick -> 8 MHz at 96 MHz
i8088 u_cpu(
    .CORE_CLK   ( clk       ),
    .CLK        ( cpu_clk   ),
    .RESET      ( rst       ),
    .READY      ( ready     ),
    .INTR       ( 1'b0      ),
    .NMI        ( ~vbl_irq  ),
    .ad_out     ( ad        ),
    .dout       ( cpu_dout8 ),
    .din        ( din       ),
    .lock_n     (           ),
    .s6_3_mux   (           ),
    .s2_s0_out  ( cpu_st    ),
    .SEGMENT    (           ),
    .biu_done   (           ),
    .cycle_accrate                      ( 1'b1  ),
    .clock_cycle_counter_division_ratio ( 8'd3  ),
    .clock_cycle_counter_decrement_value( 8'd7  ),
    .shift_read_timing                  ( 1'b0  ),
    .is8086                             ( 1'b0  ),
    .fake286_flags                      ( 1'b0  ),
    .word_read_request                  (       ),
    .word_write_request                 (       ),
    .data_bus_word_out                  (       ),
    .data_bus_word                      ( 16'd0 ),
    .word_access_possible               ( 1'b0  )
);

KF8288 u_busctl(
    .clock                          ( clk     ),
    .cpu_ce_posedge                 ( ce_pos  ),
    .cpu_ce_negedge                 ( ce_neg  ),
    .reset                          ( rst     ),
    .address_enable_n               ( 1'b0    ),
    .command_enable                 ( 1'b1    ),
    .io_bus_mode                    ( 1'b0    ),
    .processor_status               ( cpu_st  ),
    .enable_io_command              (         ),
    .advanced_io_write_command_n    (         ),
    .io_write_command_n             ( iowr_n  ),
    .io_read_command_n              ( iord_n  ),
    .interrupt_acknowledge_n        ( inta_n  ),
    .enable_memory_command          (         ),
    .advanced_memory_write_command_n(         ),
    .memory_write_command_n         ( mwr_n   ),
    .memory_read_command_n          ( mrd_n   ),
    .direction_transmit_or_receive_n(         ),
    .data_enable                    (         ),
    .master_cascade_enable          (         ),
    .peripheral_data_enable_n       (         ),
    .address_latch_enable           ( ale     )
);

jthotblk_i2c u_eeprom(
    .rst        ( rst            ),
    .clk        ( clk            ),
    .scl        ( scl            ),
    .sdaw       ( sdaw           ),
    .sda        ( sda            ),
    .prog_addr  ( prog_addr[7:0] ),
    .prog_data  ( prog_data      ),
    .prog_we    ( prom_we        )
);

jt49_bus u_ay(
    .rst_n      ( ~rst           ),
    .clk        ( clk            ),
    .clk_en     ( cen_ay         ),
    .bdir       ( ay_cs && wr ),
    .bc1        ( ay_cs && (wr ? !A[0] : !rd_n) ),
    .din        ( cpu_dout8      ),
    .sel        ( 1'b1           ),
    .dout       ( ay_dout        ),
    .sound      ( psg            ),
    .A          (                ),
    .B          (                ),
    .C          (                ),
    .sample     (                ),
    .IOA_in     ( p1             ),
    .IOA_out    (                ),
    .IOA_oe     (                ),
    .IOB_in     ( p2             ),
    .IOB_out    (                ),
    .IOB_oe     (                )
);

jthotblk_video u_video(
    .rst              ( rst              ),
    .clk              ( clk              ),
    .pxl_cen          ( pxl_cen          ),
    .enable           ( port0[6]         ),
    .vram_video_addr  ( vram_video_addr  ),
    .vram_video_dout  ( vram_video_dout  ),
    .pallo_video_addr ( pallo_video_addr ),
    .pallo_video_dout ( pallo_video_dout ),
    .palhi_video_addr ( palhi_video_addr ),
    .palhi_video_dout ( palhi_video_dout ),
    .vbl_irq          ( vbl_irq          ),
    .LHBL             ( LHBL             ),
    .LVBL             ( LVBL             ),
    .HS               ( HS               ),
    .VS               ( VS               ),
    .red              ( red              ),
    .green            ( green            ),
    .blue             ( blue             )
);

endmodule
