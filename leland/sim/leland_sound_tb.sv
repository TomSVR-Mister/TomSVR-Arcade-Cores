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

module leland_sound_tb;

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
    .clk_sys(clk_sys), .reset(reset), .ce_8m(ce_8m), .ataxx_mode(1'b0), .wsf_mode(1'b0), .ext_data(8'h00), .ext_stall(1'b0),
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

// --- Flat 1MB ROM image (80186's own address space, 0x00000-0xFFFFF).
// RAM window (0-0x1FFFF) and unpopulated ROM gaps are irrelevant here
// (rom_req is only ever asserted for addr>=0x20000 by leland_sound.sv's
// own mem_is_ram decode) -- zero-initialized, real content loaded only
// into the three populated 128KB windows, matching the MRA fix's own
// derivation from leland.cpp's ROM_START(offroad). ---
reg [7:0] rom_img [0:1048575];

integer rfd, rcount, i;
initial begin
    for (i = 0; i < 1048576; i = i + 1) rom_img[i] = 8'h00;

    load_pair("03-22113-03.u13t", "03-22116-03.u25t", 20'h040000);
    load_pair("03-22114-03.u14t", "03-22117-03.u26t", 20'h060000);
    load_pair("03-22115-03.u15t", "03-22118-03.u27t", 20'h0E0000);
end

task automatic load_pair(input string lo_name, input string hi_name, input [19:0] base);
    integer fd_lo, fd_hi, k;
    reg [7:0] lo_buf[0:65535];
    reg [7:0] hi_buf[0:65535];
    integer n_lo, n_hi;
    begin
        fd_lo = $fopen(lo_name, "rb");
        if (!fd_lo) begin $display("ERROR: could not open %s", lo_name); $finish; end
        n_lo = $fread(lo_buf, fd_lo);
        $fclose(fd_lo);
        fd_hi = $fopen(hi_name, "rb");
        if (!fd_hi) begin $display("ERROR: could not open %s", hi_name); $finish; end
        n_hi = $fread(hi_buf, fd_hi);
        $fclose(fd_hi);
        if (n_lo != 65536 || n_hi != 65536) begin
            $display("ERROR: %s/%s read %0d/%0d bytes, expected 65536/65536", lo_name, hi_name, n_lo, n_hi);
            $finish;
        end
        for (k = 0; k < 65536; k = k + 1) begin
            rom_img[base + {k[15:0], 1'b0}] = lo_buf[k];
            rom_img[base + {k[15:0], 1'b0} + 1] = hi_buf[k];
        end
        $display("Loaded %s (low) / %s (high) at base 0x%05h", lo_name, hi_name, base);
    end
endtask

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

// --- Boot sequencing: release the 80186 from /RESET once, matching
// the real master Z80's own single boot-time write (leland_a.cpp:
// leland_80186_control_w only cares about bits [7:3]; INT0/INT1/TEST
// all deasserted, /RESET deasserted -- 0x80). ---
initial begin
    reset = 1'b1;
    repeat (10) @(posedge clk_sys);
    reset = 1'b0;
    repeat (10) @(posedge clk_sys);
    sound_ctrl_data = 8'h80; // /RESET deasserted (bit7=1), INT0/INT1/TEST=0
    sound_ctrl_wr   = 1'b1;
    @(posedge clk_sys);
    sound_ctrl_wr = 1'b0;
end

// --- Synthetic command-injection sequence (without driving
// cmd_wr_lo/cmd_wr_hi after boot, the 80186 has nothing to do once its
// own boot self-test finishes).
// Real hardware's master Z80 continuously writes music/SFX command
// bytes to ports 0xF2 (command_lo_w)/0xF4 (command_hi_w) throughout
// gameplay/attract mode -- this bench can't replicate the REAL Leland
// command table (that needs the 80186 ROM's own command-dispatch logic
// disassembled, out of scope here), so it drives a
// synthetic-but-plausible sequence instead: the one real byte value
// actually observed in
// a MAME master-CPU trace (0xFF/0xFF, the very
// first command the real master Z80 sends, at PC $1246/$1248) as the
// first command, then a swept sequence of synthetic command bytes to
// exercise whatever command-dispatch code path this reaches, so the
// capture reflects "the pipeline responds to commands" rather than
// silence -- explicitly not a claim of matching real game audio
// content. `send_command` mirrors the real protocol's own
// two-separate-OUT shape (command_lo and command_hi as two distinct
// 1-cycle strobes with a real gap between them, not simultaneous --
// see leland_master.sv's own io_cmd/io_snd_hi decode for the hardware
// timing this copies).
task automatic send_command(input [7:0] lo, input [7:0] hi);
    begin
        @(posedge clk_sys);
        cmd_wr_data = {lo, lo};
        cmd_wr_lo   = 1'b1;
        @(posedge clk_sys);
        cmd_wr_lo   = 1'b0;
        repeat (4) @(posedge clk_sys);
        cmd_wr_data = {hi, hi};
        cmd_wr_hi   = 1'b1;
        @(posedge clk_sys);
        cmd_wr_hi   = 1'b0;
        repeat (4) @(posedge clk_sys);
        // Pulse INT0 (control_data bit5, leland_80186_control_w) to
        // notify the 80186 a new command is ready -- writing
        // cmd_wr_lo/hi alone does NOT do this (confirmed: an earlier
        // version of this sequence with no INT0 pulse produced zero
        // change in dac_write_count vs. the no-commands-at-all
        // baseline). i186_periph's own interrupt controller defaults
        // to edge-triggered (LTM=0 reset default, see
        // intc_ext0_ctrl<=7'hf in i186_periph.sv), so this needs a real
        // 0->1 transition on int0_pin, not just holding it high --
        // matches a captured real REQST 0x0000->0x0020
        // transition, not a held level. Reuses the same
        // sound_ctrl_data/sound_ctrl_wr port this bench's boot sequence
        // already drives for /RESET (bit7 stays 1 = deasserted in both
        // writes below -- never re-asserting reset here).
        sound_ctrl_data = 8'h80; // INT0 low (bit5=0), /RESET still deasserted
        sound_ctrl_wr   = 1'b1;
        @(posedge clk_sys);
        sound_ctrl_wr   = 1'b0;
        repeat (4) @(posedge clk_sys);
        sound_ctrl_data = 8'hA0; // INT0 high (bit5=1) -- the rising edge
        sound_ctrl_wr   = 1'b1;
        @(posedge clk_sys);
        sound_ctrl_wr   = 1'b0;
    end
endtask

// COMMAND_PERIOD_CLKS: cadence between synthetic commands. Real
// hardware's own observed command traffic is sparse (only 6 total
// command-port writes across mastertrace.log's whole captured window),
// but this bench's goal is exercising the pipeline, not reproducing
// real traffic density -- a much tighter cadence than real hardware
// gives more command diversity per simulated second, at the cost of
// not being period-accurate to any real attract-mode timing.
localparam integer COMMAND_PERIOD_CLKS = 50_000; // ~1.04ms @ 48MHz
localparam integer NUM_SYNTHETIC_COMMANDS = 200;

task automatic send_command_sequence;
    integer cmd_idx;
    begin
        // Let the 80186 finish its own boot self-test (the boot
        // signature settles well within 300k cycles) before the first command arrives --
        // matches real hardware, where the master Z80 never sends a
        // command before the sound CPU has come out of its own boot.
        repeat (COMMAND_PERIOD_CLKS) @(posedge clk_sys);
        send_command(8'hFF, 8'hFF); // real: mastertrace.log PC $1246/$1248
        for (cmd_idx = 0; cmd_idx < NUM_SYNTHETIC_COMMANDS; cmd_idx = cmd_idx + 1) begin
            repeat (COMMAND_PERIOD_CLKS) @(posedge clk_sys);
            send_command(cmd_idx[7:0], 8'h00);
        end
    end
endtask

initial send_command_sequence();

// --- Instrumentation + WAV capture (same convention as
// leland_sound_smoketest_tb.sv) ---
longint unsigned cyc_count = 0;
longint unsigned MAX_CYCLES;
longint unsigned dac_write_count = 0, dac9_write_count = 0;

always @(posedge clk_sys) begin
    if (!reset) cyc_count <= cyc_count + 1;
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
        MAX_CYCLES = 2_000_000;
    pcm_fd = $fopen("leland_sound_tb.pcm", "wb");
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
        wav_fd = $fopen("leland_sound_tb.wav", "wb");
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

        rd_fd = $fopen("leland_sound_tb.pcm", "rb");
        c = $fgetc(rd_fd);
        while (c != -1) begin
            $fwrite(wav_fd, "%c", c[7:0]);
            c = $fgetc(rd_fd);
        end
        $fclose(rd_fd);
        $fclose(wav_fd);
        $display("WAV written: leland_sound_tb.wav (%0d samples @ %0d Hz nominal)",
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
