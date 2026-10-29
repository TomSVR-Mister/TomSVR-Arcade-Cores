// leland_sound_smoketest_tb -- real s80x86 Core + real ROM,
// wired through the real i186_periph -> leland_sound_board
// -> leland_dac_mixer chain, to answer a narrower question
// than full integration: "does actual SOR sound-ROM code, running
// on the real CPU core, reach the point of driving the polled/timer-
// paced DAC path and produce real audio samples" -- without waiting for
// internal DMA or board-level reset sequencing, master
// Z80 harness, Quartus integration.
//
// Explicitly NOT a claim of PC-trace-accurate MAME matching (that's
// s80x86_stage_a_tb.sv's job, already proven for the first 30
// instructions) and NOT a claim that DMA
// channels 0/1 produce audio (DMA is not serviced here -- their PIT
// DRQ0/DRQ1 pulses just go unserviced here, so those two channels stay
// silent by construction, not by bug). Channels 2-5 (polled) and dac9
// (timer-0-paced, direct CPU store) need no DMA at all and are exactly
// what a real MAME trace showed getting programmed within the
// first ~16 emulated video frames of boot -- i.e. very early, well
// within a bounded instruction-count run.
//
// Memory model, ROM/microcode loading, and the "run <N>ns not run <N>"
// / Microcode.sv readmemb workarounds are copied verbatim from
// s80x86_stage_a_tb.sv -- see that file's own header
// for why they're needed. This bench adds: the
// DATA port routes through i186_periph -> leland_sound_board instead
// of a flat memory model with dummy I/O reads; a real ROM/RAM array
// still backs leland_sound_board's `mem_*` passthrough port for
// everything neither module claims; leland_dac_mixer samples the
// resulting audio periodically into a real WAV file.
//
// Board-level control-latch /RESET sequencing (leland_sound_board's
// own `audiocpu_reset_n`) is intentionally NOT wired to the Core's
// `reset` input here -- there is no master-Z80 harness driving
// `control_wr` in this bench, so that output would just hold the
// module's own post-reset default forever. The Core's `reset` is
// pulsed directly by this testbench once at time 0, same as Stage A.

`timescale 1ns / 1ps

module leland_sound_smoketest_tb;

localparam CLK_PERIOD = 20; // 50MHz sim clock -- functional only, not calibrated to real MHz

reg clk = 0;
reg reset = 1;
always #(CLK_PERIOD/2) clk = ~clk;

// --- Core interrupt/debug ports ---
wire nmi = 1'b0;
wire intr, inta;
wire [7:0] irq;

wire debug_stopped;
wire debug_seize = 1'b0;
wire [7:0] debug_addr = 8'h0;
wire debug_run = 1'b0;
wire [15:0] debug_val;
wire [15:0] debug_wr_val = 16'h0;
wire debug_wr_en = 1'b0;

// --- Core instruction bus (straight to ROM/RAM, no peripheral involved) ---
wire [19:1] instr_m_addr;
reg  [15:0] instr_m_data_in;
wire        instr_m_access;
reg         instr_m_ack;

// --- Core data bus (routes through i186_periph) ---
wire [19:1] core_data_addr;
wire [15:0] core_data_in;
wire [15:0] core_data_out;
wire        core_data_access;
wire        core_data_ack;
wire        core_data_wr_en;
wire [1:0]  core_data_bytesel;
wire        core_d_io;
wire        lock;

Core dut(.clk(clk),
         .reset(reset),
         .nmi(nmi),
         .intr(intr),
         .irq(irq),
         .inta(inta),
         .instr_m_addr(instr_m_addr),
         .instr_m_data_in(instr_m_data_in),
         .instr_m_access(instr_m_access),
         .instr_m_ack(instr_m_ack),
         .data_m_addr(core_data_addr),
         .data_m_data_in(core_data_in),
         .data_m_data_out(core_data_out),
         .data_m_access(core_data_access),
         .data_m_ack(core_data_ack),
         .data_m_wr_en(core_data_wr_en),
         .data_m_bytesel(core_data_bytesel),
         .d_io(core_d_io),
         .lock(lock),
         .debug_stopped(debug_stopped),
         .debug_seize(debug_seize),
         .debug_addr(debug_addr),
         .debug_run(debug_run),
         .debug_val(debug_val),
         .debug_wr_val(debug_wr_val),
         .debug_wr_en(debug_wr_en));

// --- i186_periph ---
wire [19:1] sys_addr;
wire [15:0] sys_data_in;
wire [15:0] sys_data_out;
wire        sys_access;
wire        sys_ack;
wire        sys_wr_en;
wire [1:0]  sys_bytesel;
wire        sys_d_io;

wire [19:0] ext_window_base;
wire        ext_window_is_mem, ext_window_valid;
wire [15:0] reloc_reg, umcs_reg, lmcs_reg, pacs_reg, mmcs_reg, mpcs_reg;
wire        tmrout0, tmrout1;
wire [2:0]  timer_irq, timer_tc_pulse;
wire [15:0] t_count[0:2], t_maxA[0:2], t_maxB[0:2], t_control[0:2];
wire [7:0]  intc_request_reg, intc_in_service_reg;
wire [2:0]  intc_status_reg;
wire [3:0]  intc_timer0_ctrl_reg, intc_dma0_ctrl_reg, intc_dma1_ctrl_reg;
wire [6:0]  intc_ext0_ctrl_reg, intc_ext1_ctrl_reg;

// No master-Z80 harness -- INT0/INT1 and DMA-TC never assert. The ROM
// runs in poll mode for its own status checks so
// this doesn't block the polled/timer-paced DAC path from working.
wire int0_pin = 1'b0, int1_pin = 1'b0;
wire dma0_irq_req = 1'b0, dma1_irq_req = 1'b0;

// DMA readback (unused by this bench's own pass/fail criteria --
// this smoke test only checks "does it hang" / DAC-write snapshots, per
// its own header -- but wired up so the internal DMA engine is actually
// live and driving real channel-0/1 traffic if the real ROM programs it).
wire [19:0] dma_src[0:1], dma_dst[0:1];
wire [15:0] dma_count[0:1], dma_control[0:1];
wire [1:0]  dma_active;
wire        dma_byte_done, dma_byte_done_ch;
wire        drq0_pit_level, drq1_pit_level, drq0_clear, drq1_clear;

i186_periph periph(
    .clk(clk), .reset(reset), .ce_8m(1'b1),
    .cpu_data_m_addr(core_data_addr), .cpu_data_m_data_in(core_data_in),
    .cpu_data_m_data_out(core_data_out), .cpu_data_m_access(core_data_access),
    .cpu_data_m_ack(core_data_ack), .cpu_data_m_wr_en(core_data_wr_en),
    .cpu_data_m_bytesel(core_data_bytesel), .cpu_d_io(core_d_io),
    .sys_data_m_addr(sys_addr), .sys_data_m_data_in(sys_data_in),
    .sys_data_m_data_out(sys_data_out), .sys_data_m_access(sys_access),
    .sys_data_m_ack(sys_ack), .sys_data_m_wr_en(sys_wr_en),
    .sys_data_m_bytesel(sys_bytesel), .sys_d_io(sys_d_io),
    .ext_window_base(ext_window_base), .ext_window_is_mem(ext_window_is_mem),
    .ext_window_valid(ext_window_valid),
    .reloc_reg(reloc_reg), .umcs_reg(umcs_reg), .lmcs_reg(lmcs_reg),
    .pacs_reg(pacs_reg), .mmcs_reg(mmcs_reg), .mpcs_reg(mpcs_reg),
    .tmrout0(tmrout0), .tmrout1(tmrout1), .timer_irq(timer_irq),
    .timer_tc_pulse(timer_tc_pulse),
    .t_count(t_count), .t_maxA(t_maxA), .t_maxB(t_maxB), .t_control(t_control),
    .intr(intr), .irq_out(irq), .inta(inta),
    .int0_pin(int0_pin), .int1_pin(int1_pin),
    .dma0_irq_req(dma0_irq_req), .dma1_irq_req(dma1_irq_req),
    .intc_request_reg(intc_request_reg), .intc_in_service_reg(intc_in_service_reg),
    .intc_status_reg(intc_status_reg),
    .intc_timer0_ctrl_reg(intc_timer0_ctrl_reg), .intc_dma0_ctrl_reg(intc_dma0_ctrl_reg),
    .intc_dma1_ctrl_reg(intc_dma1_ctrl_reg),
    .intc_ext0_ctrl_reg(intc_ext0_ctrl_reg), .intc_ext1_ctrl_reg(intc_ext1_ctrl_reg),
    .drq0_pit_level(drq0_pit_level), .drq1_pit_level(drq1_pit_level),
    .drq0_clear(drq0_clear), .drq1_clear(drq1_clear),
    .dma_src(dma_src), .dma_dst(dma_dst), .dma_count(dma_count), .dma_control(dma_control),
    .dma_active(dma_active), .dma_byte_done(dma_byte_done), .dma_byte_done_ch(dma_byte_done_ch));

// --- leland_sound_board ---
wire [19:1] mem_addr;
reg  [15:0] mem_data_in;
wire [15:0] mem_data_out;
wire        mem_access;
reg         mem_ack;
wire        mem_wr_en;
wire [1:0]  mem_bytesel;
wire        mem_d_io;

reg  [15:0] cmd_wr_data = 16'h0;
wire        cmd_wr_lo = 1'b0, cmd_wr_hi = 1'b0; // no master Z80 harness
wire [7:0]  response_data;
wire        response_wr;
wire [7:0]  control_data = 8'h0;
wire        control_wr = 1'b0;
wire        audiocpu_reset_n, audiocpu_test_n, int0_out, int1_out;
wire [7:0]  dac_sample[0:5];
wire [7:0]  dac_vol[0:5];
wire        dac_wr[0:5];
wire [9:0]  dac9_sample;
wire        dac9_wr;
wire [6:0]  clock_active;

reg pit_ce;

leland_sound_board board(
    .clk(clk), .reset(reset),
    .cpu_addr(sys_addr), .cpu_data_in(sys_data_in), .cpu_data_out(sys_data_out),
    .cpu_access(sys_access), .cpu_ack(sys_ack), .cpu_wr_en(sys_wr_en),
    .cpu_bytesel(sys_bytesel), .cpu_d_io(sys_d_io),
    .ext_window_base(ext_window_base), .ext_window_is_mem(ext_window_is_mem),
    .ext_window_valid(ext_window_valid),
    .mem_addr(mem_addr), .mem_data_in(mem_data_in), .mem_data_out(mem_data_out),
    .mem_access(mem_access), .mem_ack(mem_ack), .mem_wr_en(mem_wr_en),
    .mem_bytesel(mem_bytesel), .mem_d_io(mem_d_io),
    .t0_tc_pulse(timer_tc_pulse[0]),
    .pit_ce(pit_ce), .ataxx_mode(1'b0), .wsf_mode(1'b0), .t1_tc_pulse(1'b0), .t1_state(1'b1), .ym_dout(8'h00), .ext_data(8'h00), .ext_stall(1'b0),
    .cmd_wr_data(cmd_wr_data), .cmd_wr_lo(cmd_wr_lo), .cmd_wr_hi(cmd_wr_hi),
    .response_data(response_data), .response_wr(response_wr),
    .control_data(control_data), .control_wr(control_wr),
    .audiocpu_reset_n(audiocpu_reset_n), .audiocpu_test_n(audiocpu_test_n),
    .int0_pin(int0_out), .int1_pin(int1_out),
    .dac_sample(dac_sample), .dac_vol(dac_vol), .dac_wr(dac_wr),
    .dac9_sample(dac9_sample), .dac9_wr(dac9_wr),
    .drq0_pit_level(drq0_pit_level), .drq1_pit_level(drq1_pit_level),
    .drq0_clear(drq0_clear), .drq1_clear(drq1_clear),
    .clock_active(clock_active));

// PIT clock enable: real hardware is CPU-XTAL/4 (16MHz/4MHz); this sim
// clock is functional-only (not calibrated to real MHz -- see Stage A's
// own note), so a plain divide-by-4 of the same functional clk is used
// as a plausible, simple ratio, not a claim of real-time pitch accuracy.
reg [1:0] pce_div;
always @(posedge clk or posedge reset) begin
    if (reset) begin pce_div <= 2'd0; pit_ce <= 1'b0; end
    else begin
        pce_div <= pce_div + 2'd1;
        pit_ce  <= (pce_div == 2'd3);
    end
end

// --- leland_dac_mixer ---
wire signed [15:0] audio_out;
leland_dac_mixer mixer(
    .clk(clk), .reset(reset),
    .dac_sample(dac_sample), .dac_vol(dac_vol), .dac9_sample(dac9_sample),
    .audio_out(audio_out));

// --- Memory model behind leland_sound_board's mem_* passthrough AND
// the Core's instruction port (both address the same flat ROM/RAM,
// exactly matching s80x86_stage_a_tb.sv's model / leland_80186_map_program) ---
reg [7:0] ram [0:16383];
reg [7:0] rom [0:1048575];

string rom_hex_path;
initial begin
    if (!$value$plusargs("ROM_HEX=%s", rom_hex_path))
        rom_hex_path = "audiocpu_offroad.hex";
    $readmemh(rom_hex_path, rom);
    for (int i = 0; i < 16384; i++) ram[i] = 8'h00;
end

initial $readmemb("../rtl/s80x86/microcode/microcode.bin", dut.Microcode.mem);

function automatic [7:0] mem_read_byte(input [19:0] addr);
    if (addr < 20'h20000)
        mem_read_byte = ram[addr & 20'h3fff];
    else
        mem_read_byte = rom[addr];
endfunction

task automatic mem_write_byte(input [19:0] addr, input [7:0] data);
    if (addr < 20'h20000)
        ram[addr & 20'h3fff] = data;
endtask

// Instruction fetch port: single-cycle ack, straight to ROM/RAM.
reg instr_access_prev;
always @(posedge clk) begin
    if (reset) begin
        instr_m_ack <= 1'b0;
        instr_access_prev <= 1'b0;
    end else begin
        instr_access_prev <= instr_m_access;
        if (instr_m_access && !instr_m_ack) begin
            if (!instr_access_prev) begin
                instr_m_ack <= 1'b0;
            end else begin
                instr_m_ack <= 1'b1;
                instr_m_data_in <= {mem_read_byte({instr_m_addr, 1'b1}),
                                     mem_read_byte({instr_m_addr, 1'b0})};
            end
        end else begin
            instr_m_ack <= 1'b0;
        end
    end
end

// leland_sound_board's mem_* port: single-cycle ack, same ROM/RAM.
reg mem_access_prev;
always @(posedge clk) begin
    if (reset) begin
        mem_ack <= 1'b0;
        mem_access_prev <= 1'b0;
    end else begin
        mem_access_prev <= mem_access;
        if (mem_access && !mem_ack) begin
            if (!mem_access_prev) begin
                mem_ack <= 1'b0;
            end else begin
                mem_ack <= 1'b1;
                mem_data_in <= {mem_read_byte({mem_addr, 1'b1}),
                                 mem_read_byte({mem_addr, 1'b0})};
                if (mem_wr_en) begin
                    if (mem_bytesel[0]) mem_write_byte({mem_addr, 1'b0}, mem_data_out[7:0]);
                    if (mem_bytesel[1]) mem_write_byte({mem_addr, 1'b1}, mem_data_out[15:8]);
                end
            end
        end else begin
            mem_ack <= 1'b0;
        end
    end
end

// --- instruction-retirement counter (same "instruction_fifo_rd_en /
// do_next_instruction" convention as s80x86_stage_a_tb.sv) ---
longint unsigned instr_count = 0;
longint unsigned MAX_INSTR;
longint unsigned dac_write_count = 0, dac9_write_count = 0;
longint unsigned dma_byte_count = 0;

// WAIT (0x9B) never-dispatched backstop -- same rationale/method
// as s80x86_stage_a_tb.sv's own monitor, run
// here too since this bench drives real ROM code far past Stage A's
// own instruction count.
longint unsigned wait_dispatch_count = 0;

always @(posedge clk) begin
    if (!reset && dut.do_next_instruction) begin
        instr_count <= instr_count + 1;
    end
    if (dac9_wr) dac9_write_count <= dac9_write_count + 1;
    if (dac_wr[0] || dac_wr[1] || dac_wr[2] || dac_wr[3] || dac_wr[4] || dac_wr[5])
        dac_write_count <= dac_write_count + 1;
    if (dma_byte_done) dma_byte_count <= dma_byte_count + 1;
    if (dut.instruction_fifo_rd_en && dut.next_instruction_value.opcode == 8'h9b) begin
        wait_dispatch_count <= wait_dispatch_count + 1;
        $display("WP9 WARNING: WAIT (0x9B) dispatched at instr %0d", instr_count);
    end
end

// --- WAV writer: sample audio_out on a fixed cadence throughout the
// run (real DAC hold-value behavior between writes, so most of the
// stream will be flat between actual dac_w/dac9 events -- expected,
// not a bug). Two-file (raw PCM, then header+copy) approach to avoid
// needing seek-based header patching. ---
localparam integer SAMPLE_PERIOD_CLKS = 200; // arbitrary decimation, not real-Hz-calibrated
localparam integer WAV_SAMPLE_RATE_HZ = 8000; // nominal, for playability only

integer pcm_fd;
integer sample_div;
longint unsigned wav_sample_count = 0;

task automatic wav_u16(input integer fd_, input integer v);
    begin
        $fwrite(fd_, "%c%c", v[7:0], v[15:8]);
    end
endtask

task automatic wav_u32(input integer fd_, input integer v);
    begin
        $fwrite(fd_, "%c%c%c%c", v[7:0], v[15:8], v[23:16], v[31:24]);
    end
endtask

initial begin
    if (!$value$plusargs("MAX_INSTR=%d", MAX_INSTR))
        MAX_INSTR = 300000;
    pcm_fd = $fopen("leland_sound_smoketest.pcm", "wb");
    sample_div = 0;
    reset = 1;
    repeat (10) @(posedge clk);
    reset = 0;
end

always @(posedge clk) begin
    if (!reset) begin
        sample_div <= sample_div + 1;
        if (sample_div >= SAMPLE_PERIOD_CLKS) begin
            sample_div <= 0;
            wav_u16(pcm_fd, {16'h0, audio_out} & 32'h0000ffff);
            wav_sample_count <= wav_sample_count + 1;
        end
        if (instr_count >= MAX_INSTR) begin
            $display("SMOKETEST DONE: instr_count=%0d dac_write_count=%0d dac9_write_count=%0d dma_byte_count=%0d wav_samples=%0d",
                       instr_count, dac_write_count, dac9_write_count, dma_byte_count, wav_sample_count);
            $display("WP9: wait_dispatch_count=%0d (must be 0)", wait_dispatch_count);
            $display("SMOKETEST reloc=%h pacs=%h mpcs=%h t_control0=%h ext_window_valid=%b ext_window_base=%h",
                       reloc_reg, pacs_reg, mpcs_reg, t_control[0], ext_window_valid, ext_window_base);
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
        wav_fd = $fopen("leland_sound_smoketest.wav", "wb");
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

        rd_fd = $fopen("leland_sound_smoketest.pcm", "rb");
        c = $fgetc(rd_fd);
        while (c != -1) begin
            $fwrite(wav_fd, "%c", c[7:0]);
            c = $fgetc(rd_fd);
        end
        $fclose(rd_fd);
        $fclose(wav_fd);
        $display("WAV written: leland_sound_smoketest.wav (%0d samples @ %0d Hz nominal)",
                   wav_sample_count, WAV_SAMPLE_RATE_HZ);
    end
endtask

// Safety timeout.
initial begin
    #(CLK_PERIOD * 20_000_000);
    $display("SMOKETEST TIMEOUT: only instr_count=%0d retired", instr_count);
    $fclose(pcm_fd);
    stitch_wav();
    $finish;
end

endmodule
