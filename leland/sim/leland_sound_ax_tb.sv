// leland_sound_tb -- standalone integration test for rtl/audio/leland_sound.sv
// (MiSTer-integration wrapper: real Core + first-level instr/
// data arbiter + i186_periph (incl. DMA) + leland_sound_board +
// leland_dac_mixer + on-chip RAM + a byte-wide SDRAM-style ROM
// adapter). This is the first bench to exercise the parts the earlier
// unit benches never needed: the instr/data arbiter (every prior bench
// fed instr_m straight to a flat memory model) and the RAM/ROM address
// decode + multi-cycle byte-wide ROM read FSM (every prior bench used
// a flat, single-cycle-ack memory model for everything downstream of
// leland_sound_board's mem_* port).
//
// Loads the real SOR sound ROM (6 files already in sim/, no scratchpad
// image needed) into a flat 1MB array matching the 80186's own address
// space (leland_a.cpp leland_80186_map_program: ROM identity-mapped
// from 0x20000), and a small multi-cycle (3-wait-state) memory model
// behind rom_req/rom_addr/rom_data/rom_stall -- deliberately NOT
// single-cycle, to actually exercise the ROM FSM's req-gap/multi-cycle
// timing instead of only ever seeing the fastest possible case.
//
// Also drives sound_ctrl_data/sound_ctrl_wr once, after reset, with
// /RESET deasserted (bit7=1) -- unlike leland_sound_smoketest_tb.sv
// (which drove Core.reset directly, bypassing the control-latch reset
// chain entirely), this bench exercises the REAL reset path now that
// it's actually wired through (leland_sound.sv's own core_reset = reset |
// ~audiocpu_reset_n), so something has to play the master Z80's role
// of releasing it, exactly once, matching the real protocol's own
// "write once at boot" shape.

`timescale 1ns / 1ps

module leland_sound_ax_tb;

// 48MHz -- the REAL clk_sys rate this design is built around (matches
// leland_board_tb.sv's own convention), unlike every earlier unit bench's
// deliberately uncalibrated "functional only" sim clock: this bench's
// whole point is a real-time-accurate audio capture, so cycle counts
// here really do mean real seconds (240,000,000 cycles = 5 real
// seconds), and the WAV decimation below is calibrated against this
// exact frequency, not copied from the smoke test's own (uncalibrated,
// by its own admission) 250kHz-into-an-8kHz-labeled-file mismatch.
localparam real CLK_PERIOD = 20.833; // 1000/48

reg clk_sys = 0;
reg reset = 1;
always #(CLK_PERIOD/2) clk_sys = ~clk_sys;

reg  [7:0] sound_ctrl_data = 8'h00;
reg        sound_ctrl_wr   = 1'b0;
reg [15:0] cmd_wr_data     = 16'h0;
reg        cmd_wr_lo = 1'b0, cmd_wr_hi = 1'b0;
wire [7:0] response_data;

wire        rom_req;
wire [19:0] rom_addr;
wire  [7:0] rom_data;
wire        rom_stall;

wire signed [15:0] audio_out;

reg ce_8m;

leland_sound dut(
    .clk_sys(clk_sys), .reset(reset), .ce_8m(ce_8m), .ataxx_mode(1'b1), .wsf_mode(1'b0), .ext_data(8'h00), .ext_stall(1'b0),
    .sound_ctrl_data(sound_ctrl_data), .sound_ctrl_wr(sound_ctrl_wr),
    .cmd_wr_data(cmd_wr_data), .cmd_wr_lo(cmd_wr_lo), .cmd_wr_hi(cmd_wr_hi),
    .response_data(response_data),
    .rom_req(rom_req), .rom_addr(rom_addr), .rom_data(rom_data), .rom_stall(rom_stall),
    .audio_out(audio_out));

// ce_8m: 8MHz-equivalent from this 50MHz functional clock -- not a real
// Hz calibration (same "functional only" caveat every prior sim clock
// in this repo carries), just a plausible non-1:1 divide so the
// internal-timer-tick-vs-bus-rate distinction this session's clocking
// decision hinges on is genuinely exercised (ce_8m ticking slower than
// clk_sys), not accidentally tied high (which would silently revert to
// every prior bench's "every clk" behavior and prove nothing new).
reg [2:0] ce_8m_div;
always @(posedge clk_sys or posedge reset) begin
    if (reset) begin ce_8m_div <= 3'd0; ce_8m <= 1'b0; end
    else begin
        ce_8m_div <= (ce_8m_div == 3'd5) ? 3'd0 : ce_8m_div + 3'd1;
        ce_8m <= (ce_8m_div == 3'd5);
    end
end

reg [7:0] rom_img [0:1048575];
integer rfd, rcount;
initial begin
    rfd = $fopen("ataxx_snd.bin", "rb");
    if (!rfd) begin $display("ERROR: could not open ataxx_snd.bin"); $finish; end
    rcount = $fread(rom_img, rfd);
    $fclose(rfd);
    $display("Loaded ataxx_snd.bin (%0d bytes)", rcount);
end

// --- Multi-cycle (3-wait-state) byte-wide memory model behind
// rom_req/rom_addr/rom_data/rom_stall -- deliberately not single-cycle,
// see file header. ---
reg [1:0] rom_wait_ctr;
reg       rom_req_d;
always @(posedge clk_sys or posedge reset) begin
    if (reset) begin
        rom_wait_ctr <= 2'd0;
        rom_req_d    <= 1'b0;
    end else begin
        rom_req_d <= rom_req;
        if (rom_req && !rom_req_d) rom_wait_ctr <= 2'd3;
        else if (rom_wait_ctr != 2'd0) rom_wait_ctr <= rom_wait_ctr - 2'd1;
    end
end
assign rom_stall = rom_req && (rom_wait_ctr != 2'd0);
assign rom_data  = rom_img[rom_addr];

// Microcode ROM load workaround -- same ModelSim quirk documented in
// s80x86_stage_a_tb.sv (Microcode.sv's own $readmemb unreliable under
// this tool); re-load directly via hierarchical reference.
initial $readmemb("../rtl/s80x86/microcode/microcode.bin", dut.cpu.Microcode.mem);

localparam integer FRAME_CLKS = 800000;
integer evfd, ef, ecount;
reg [8*4-1:0] eport;
integer edata;
longint unsigned t_next;
longint unsigned MAX_FRAME;
longint unsigned cyc_count = 0;
initial begin
    if (!$value$plusargs("MAX_FRAME=%d", MAX_FRAME)) MAX_FRAME = 330;
    reset = 1'b1;
    repeat (10) @(posedge clk_sys);
    reset = 1'b0;
    evfd = $fopen("ax_events.txt", "r");
    t_next = 0;
    while (!$feof(evfd)) begin
        ecount = $fscanf(evfd, "%d %s %h\n", ef, eport, edata);
        if (ecount == 3 && ef <= MAX_FRAME) begin
            while (cyc_count < ef * FRAME_CLKS || cyc_count < t_next) @(posedge clk_sys);
            t_next = cyc_count + 3000;
            if (eport == "05") begin cmd_wr_data = {edata[7:0], edata[7:0]}; cmd_wr_hi = 1'b1; @(posedge clk_sys); cmd_wr_hi = 1'b0; end
            else if (eport == "06") begin cmd_wr_data = {edata[7:0], edata[7:0]}; cmd_wr_lo = 1'b1; @(posedge clk_sys); cmd_wr_lo = 1'b0; end
            else begin
                sound_ctrl_data = {edata[0], edata[1], edata[2], edata[3], 4'h0};
                sound_ctrl_wr = 1'b1; @(posedge clk_sys); sound_ctrl_wr = 1'b0;
            end
        end
    end
end

// --- Instrumentation + WAV capture (same convention as
// leland_sound_smoketest_tb.sv) ---
longint unsigned MAX_CYCLES;
reg [15:0] ctl0_d = 0, ctl1_d = 0;
longint unsigned dac_write_count = 0, dac9_write_count = 0, c0 = 0, c1 = 0, c2 = 0, resp_count = 0;

always @(posedge clk_sys) begin
    if (!reset) cyc_count <= cyc_count + 1;
    if (!reset && (cyc_count == 190*FRAME_CLKS || cyc_count == 250*FRAME_CLKS || cyc_count == 330*FRAME_CLKS || cyc_count == 520*FRAME_CLKS))
        $display("CKPT frame=%0d d0=%0d d1=%0d d2=%0d d9=%0d resp=%0d", cyc_count/FRAME_CLKS, c0, c1, c2, dac9_write_count, resp_count);
    if (!reset && (cyc_count % (10*FRAME_CLKS)) == 0)
        $display("DMA f=%0d ctl0=%h dst0=%h cnt0=%h src0=%h ctl1=%h dst1=%h cnt1=%h src1=%h act=%b drq0l=%b drq1l=%b", cyc_count/FRAME_CLKS, dut.dma_control[0], dut.dma_dst[0], dut.dma_count[0], dut.dma_src[0], dut.dma_control[1], dut.dma_dst[1], dut.dma_count[1], dut.dma_src[1], dut.dma_active, dut.periph.drq0_latch, dut.periph.drq1_latch);
    if (dut.dma_control[0] !== ctl0_d || dut.dma_control[1] !== ctl1_d)
        $display("DMACTL f=%0d.%0d ctl0=%h ctl1=%h cnt0=%h cnt1=%h src0=%h src1=%h dst0=%h dst1=%h", cyc_count/FRAME_CLKS, (cyc_count%FRAME_CLKS)/1000, dut.dma_control[0], dut.dma_control[1], dut.dma_count[0], dut.dma_count[1], dut.dma_src[0], dut.dma_src[1], dut.dma_dst[0], dut.dma_dst[1]);
    ctl0_d <= dut.dma_control[0]; ctl1_d <= dut.dma_control[1];
    if (cyc_count >= 91*FRAME_CLKS && cyc_count < 91*FRAME_CLKS+80000 && (cyc_count % 1000) == 0)
        $display("DBG st=%0d cnt0=%h src0=%h drq0l=%b pit0c0=%b ack=%b acc=%b wr=%b addr=%h d_io=%b winhit=%b", dut.periph.dma_state, dut.dma_count[0], dut.dma_src[0], dut.periph.drq0_latch, dut.drq0_pit_level, dut.periph.dma_m_ack, dut.periph.dma_m_access, dut.periph.dma_m_wr_en, dut.periph.dma_m_addr, dut.periph.dma_m_d_io, dut.board.win_hit);
    if (dut.board.u_pit0.state == 3'd1 && dut.board.u_pit0.cs_n == 1'b0 && dut.board.u_pit0.we_n == 1'b0)
        $display("PIT0W f=%0d addr=%0d data=%h", cyc_count/FRAME_CLKS, dut.board.u_pit0.kf_addr, dut.board.u_pit0.kf_data_in);
    if (dut.dac_wr[0]) c0 <= c0 + 1;
    if (dut.dac_wr[1]) c1 <= c1 + 1;
    if (dut.dac_wr[2]) c2 <= c2 + 1;
    if (dut.response_wr) resp_count <= resp_count + 1;
    if (dut.dac9_wr) dac9_write_count <= dac9_write_count + 1;
    if (dut.dac_wr[0] || dut.dac_wr[1] || dut.dac_wr[2] || dut.dac_wr[3] || dut.dac_wr[4] || dut.dac_wr[5])
        dac_write_count <= dac_write_count + 1;
end

// Calibrated against the real 48MHz clk_sys above: 48,000,000/44,100 ~=
// 1088 clk_sys cycles per WAV sample -- unlike the smoke test's own
// 200-cycles-into-an-8kHz-label mismatch (a ~250kHz decimation rate
// declared as 8kHz, which would play back roughly 31x too slow), this
// makes the WAV's declared sample rate genuinely match the rate samples
// are actually taken at, so real-time pitch comes out correct.
localparam integer SAMPLE_PERIOD_CLKS = 1088;
localparam integer WAV_SAMPLE_RATE_HZ = 44100;

integer pcm_fd;
integer sample_div;
longint unsigned wav_sample_count = 0;

task automatic wav_u16(input integer fd_, input integer v);
    begin $fwrite(fd_, "%c%c", v[7:0], v[15:8]); end
endtask
task automatic wav_u32(input integer fd_, input integer v);
    begin $fwrite(fd_, "%c%c%c%c", v[7:0], v[15:8], v[23:16], v[31:24]); end
endtask

initial begin
    if (!$value$plusargs("MAX_CYCLES=%d", MAX_CYCLES))
        MAX_CYCLES = 330*800000;
    pcm_fd = $fopen("leland_sound_ax_tb.pcm", "wb");
    sample_div = 0;
end

always @(posedge clk_sys) begin
    if (!reset) begin
        sample_div <= sample_div + 1;
        if (sample_div >= SAMPLE_PERIOD_CLKS) begin
            sample_div <= 0;
            wav_u16(pcm_fd, {16'h0, audio_out} & 32'h0000ffff);
            wav_sample_count <= wav_sample_count + 1;
        end
        if (cyc_count >= MAX_CYCLES) begin
            $display("LELAND_SOUND_TB DONE: cyc_count=%0d dac_write_count=%0d dac9_write_count=%0d wav_samples=%0d",
                       cyc_count, dac_write_count, dac9_write_count, wav_sample_count);
            $display("LELAND_SOUND_TB reloc=%h pacs=%h mpcs=%h t_control0=%h ext_window_valid=%b ext_window_base=%h",
                       dut.reloc_reg, dut.pacs_reg, dut.mpcs_reg, dut.t_control[0],
                       dut.ext_window_valid, dut.ext_window_base);
            $fclose(pcm_fd);
            stitch_wav();
            $finish;
        end
    end
end

task automatic stitch_wav;
    integer wav_fd, rd_fd;
    integer data_bytes, byte_rate, riff_bytes;
    integer c;
    begin
        data_bytes = wav_sample_count * 2;
        byte_rate  = WAV_SAMPLE_RATE_HZ * 2;
        riff_bytes = 36 + data_bytes;
        wav_fd = $fopen("leland_sound_ax_tb.wav", "wb");
        $fwrite(wav_fd, "RIFF");
        wav_u32(wav_fd, riff_bytes);
        $fwrite(wav_fd, "WAVE");
        $fwrite(wav_fd, "fmt ");
        wav_u32(wav_fd, 16);
        wav_u16(wav_fd, 1);
        wav_u16(wav_fd, 1);
        wav_u32(wav_fd, WAV_SAMPLE_RATE_HZ);
        wav_u32(wav_fd, byte_rate);
        wav_u16(wav_fd, 2);
        wav_u16(wav_fd, 16);
        $fwrite(wav_fd, "data");
        wav_u32(wav_fd, data_bytes);

        rd_fd = $fopen("leland_sound_ax_tb.pcm", "rb");
        c = $fgetc(rd_fd);
        while (c != -1) begin
            $fwrite(wav_fd, "%c", c[7:0]);
            c = $fgetc(rd_fd);
        end
        $fclose(rd_fd);
        $fclose(wav_fd);
        $display("WAV written: leland_sound_ax_tb.wav (%0d samples @ %0d Hz nominal)",
                   wav_sample_count, WAV_SAMPLE_RATE_HZ);
    end
endtask

// Safety timeout -- generous margin (MAX_CYCLES + 20% + a fixed 100k
// cycle floor) above the requested run length, not a fixed literal:
// this session's first 5M-cycle run hit a hardcoded 5M-cycle timeout
// almost exactly at the same instant as its own MAX_CYCLES target
// (cyc_count=4999990 of 5000000), a tuning near-miss, not a hang --
// fixed here so a future larger MAX_CYCLES doesn't repeat it.
initial begin
    #(CLK_PERIOD * (MAX_CYCLES + MAX_CYCLES/5 + 100_000));
    $display("LELAND_SOUND_TB TIMEOUT: only cyc_count=%0d retired", cyc_count);
    $fclose(pcm_fd);
    stitch_wav();
    $finish;
end

// WAIT backstop, same as prior benches -- since this is the first bench
// exercising the REAL reset/control-latch path (not a directly-forced
// Core.reset), worth re-checking here too.
longint unsigned wait_dispatch_count = 0;
always @(posedge clk_sys) begin
    if (dut.cpu.instruction_fifo_rd_en && dut.cpu.next_instruction_value.opcode == 8'h9b) begin
        wait_dispatch_count <= wait_dispatch_count + 1;
        $display("WP9 WARNING: WAIT (0x9B) dispatched at cyc %0d", cyc_count);
    end
end

endmodule
