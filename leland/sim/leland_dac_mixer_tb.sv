// Testbench for rtl/audio/leland_dac_mixer.sv. Two parts:
//
//  Part A -- directed digital checks against a reference model
//  (`model_mix`, a line-by-line mirror of the RTL's fixed-point math)
//  covering proportionality, sign, dac9-dominance, and saturation.
//  This is a regression check against arithmetic mistakes in either the
//  RTL or a hand-derived expected value, not an independent derivation
//  of the gain math itself (that derivation lives in leland_dac_mixer.sv's
//  own header comment).
//
//  Part B -- "synthetic full-scale test tones per channel" (the
//  acceptance criterion, alongside the Stage C WAV
//  criterion): drives each of the 6 8-bit channels and dac9 in turn
//  with a full-scale square wave at a distinct audible frequency and
//  records the mixer's real output into a real 16-bit PCM mono WAV
//  file (`leland_dac_mixer_tones.wav`) -- the actual audible deliverable,
//  not just a pass/fail count.

`timescale 1ns / 1ps

module leland_dac_mixer_tb;

localparam CLK_PERIOD = 20;
reg clk = 0;
reg reset = 1;
always #(CLK_PERIOD/2) clk = ~clk;

reg  [7:0] dac_sample[0:5];
reg  [7:0] dac_vol[0:5];
reg  [9:0] dac9_sample;
wire signed [15:0] audio_out;

leland_dac_mixer dut(
    .clk(clk), .reset(reset),
    .dac_sample(dac_sample), .dac_vol(dac_vol), .dac9_sample(dac9_sample), .ym_left(16'sd0), .ym_right(16'sd0),
    .audio_out(audio_out));

integer fd;
integer tests_run, tests_passed, tests_failed;

task automatic check(input string name, input logic cond);
    begin
        tests_run = tests_run + 1;
        if (cond) begin
            tests_passed = tests_passed + 1;
            $fwrite(fd, "PASS: %s\n", name);
        end else begin
            tests_failed = tests_failed + 1;
            $fwrite(fd, "FAIL: %s\n", name);
        end
    end
endtask

// --- reference model (mirrors leland_dac_mixer.sv's math exactly) ---
function automatic signed [15:0] model_mix(
    input [7:0] samp[0:5], input [7:0] vol[0:5], input [9:0] samp9);
    integer i;
    logic signed [8:0]  sd;
    logic signed [17:0] pr;
    logic signed [26:0] gp;
    logic signed [17:0] gd;
    logic signed [10:0] sd9;
    logic signed [17:0] d9full;
    logic signed [26:0] gp9;
    logic signed [17:0] gd9;
    logic signed [20:0] tot;
    begin
        tot = 21'sd0;
        for (i = 0; i < 6; i = i + 1) begin
            sd = $signed({1'b0, samp[i]}) - 9'sd128;
            pr = sd * $signed({1'b0, vol[i]});
            gp = pr * 10'sd102;
            gd = gp >>> 8;
            tot = tot + gd;
        end
        sd9    = $signed({1'b0, samp9}) - 11'sd512;
        d9full = sd9 * 11'sd64;
        gp9    = d9full * 9'sd255;
        gd9    = gp9 >>> 8;
        tot    = tot + gd9;

        if (tot > 21'sd32767)       model_mix = 16'sd32767;
        else if (tot < -21'sd32768) model_mix = -16'sd32768;
        else                        model_mix = tot[15:0];
    end
endfunction

task automatic set_neutral;
    integer i;
    begin
        for (i = 0; i < 6; i = i + 1) begin
            dac_sample[i] = 8'd128;
            dac_vol[i]    = 8'd0;
        end
        dac9_sample = 10'd512;
    end
endtask

task automatic settle_and_check(input string name);
    logic [7:0] s_snap[0:5];
    logic [7:0] v_snap[0:5];
    logic [9:0] s9_snap;
    integer i;
    begin
        for (i = 0; i < 6; i = i + 1) begin
            s_snap[i] = dac_sample[i];
            v_snap[i] = dac_vol[i];
        end
        s9_snap = dac9_sample;
        repeat (3) @(posedge clk);
        check(name, audio_out == model_mix(s_snap, v_snap, s9_snap));
    end
endtask

// --- WAV file writer (16-bit PCM mono) ---
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

task automatic wav_header(input integer fd_, input integer num_samples, input integer sample_rate);
    integer data_bytes, byte_rate, riff_bytes;
    begin
        data_bytes = num_samples * 2;
        byte_rate  = sample_rate * 2;
        riff_bytes = 36 + data_bytes;
        $fwrite(fd_, "RIFF");
        wav_u32(fd_, riff_bytes);
        $fwrite(fd_, "WAVE");
        $fwrite(fd_, "fmt ");
        wav_u32(fd_, 16);
        wav_u16(fd_, 1);  // PCM
        wav_u16(fd_, 1);  // mono
        wav_u32(fd_, sample_rate);
        wav_u32(fd_, byte_rate);
        wav_u16(fd_, 2);  // block align
        wav_u16(fd_, 16); // bits/sample
        $fwrite(fd_, "data");
        wav_u32(fd_, data_bytes);
    end
endtask

task automatic wav_sample(input integer fd_, input signed [15:0] s);
    begin
        wav_u16(fd_, {16'h0, s} & 32'h0000ffff);
    end
endtask

localparam integer SAMPLE_RATE   = 8000;
localparam integer SAMPLES_PER_SEG = 4000; // 0.5s per channel

integer wav_fd;

task automatic play_tone_channel(input integer ch_index, input integer freq_hz);
    integer half_period, s, phase, is_high;
    reg signed [15:0] sample_val;
    begin
        half_period = SAMPLE_RATE / (2 * freq_hz);
        set_neutral();
        dac_vol[ch_index] = 8'd220; // near-full-scale gain
        phase = 0; is_high = 0;
        for (s = 0; s < SAMPLES_PER_SEG; s = s + 1) begin
            if (phase == 0) is_high = ~is_high;
            dac_sample[ch_index] = is_high ? 8'd255 : 8'd0; // full-scale square wave
            phase = phase + 1;
            if (phase >= half_period) phase = 0;
            repeat (3) @(posedge clk);
            sample_val = audio_out;
            wav_sample(wav_fd, sample_val);
        end
    end
endtask

task automatic play_tone_dac9(input integer freq_hz);
    integer half_period, s, phase, is_high;
    reg signed [15:0] sample_val;
    begin
        half_period = SAMPLE_RATE / (2 * freq_hz);
        set_neutral();
        phase = 0; is_high = 0;
        for (s = 0; s < SAMPLES_PER_SEG; s = s + 1) begin
            if (phase == 0) is_high = ~is_high;
            dac9_sample = is_high ? 10'd1023 : 10'd0; // full-scale square wave
            phase = phase + 1;
            if (phase >= half_period) phase = 0;
            repeat (3) @(posedge clk);
            sample_val = audio_out;
            wav_sample(wav_fd, sample_val);
        end
    end
endtask

initial begin
    fd = $fopen("leland_dac_mixer_results.log", "w");
    tests_run = 0; tests_passed = 0; tests_failed = 0;

    set_neutral();
    repeat (5) @(posedge clk);
    reset = 0;
    repeat (5) @(posedge clk);

    // ============================================================
    // Part A: directed digital checks
    // ============================================================
    set_neutral();
    settle_and_check("silence (all neutral) -> audio_out == model (0)");
    check("silence is exactly zero", audio_out == 16'sd0);

    set_neutral();
    dac_sample[0] = 8'd255; dac_vol[0] = 8'd255; // channel 0 full positive
    settle_and_check("channel0 full-positive matches model");
    check("channel0 full-positive is > 0", audio_out > 16'sd0);

    set_neutral();
    dac_sample[0] = 8'd0; dac_vol[0] = 8'd255; // channel 0 full negative
    settle_and_check("channel0 full-negative matches model");
    check("channel0 full-negative is < 0", audio_out < 16'sd0);

    set_neutral();
    dac_sample[2] = 8'd255; dac_vol[2] = 8'd128; // half volume
    settle_and_check("channel2 half-volume matches model");

    set_neutral();
    dac_sample[2] = 8'd255; dac_vol[2] = 8'd255; // full volume, same channel
    settle_and_check("channel2 full-volume matches model");
    // Proportionality: full volume should be ~2x half volume (within the
    // fixed-point rounding this gain stage introduces).
    begin
        reg signed [15:0] full_val, half_val;
        full_val = audio_out;
        set_neutral();
        dac_sample[2] = 8'd255; dac_vol[2] = 8'd128;
        repeat (3) @(posedge clk);
        half_val = audio_out;
        check("full-volume ~2x half-volume (channel2)",
              (full_val > (half_val * 2 - 200)) && (full_val < (half_val * 2 + 200)));
    end

    set_neutral();
    dac9_sample = 10'd1023;
    settle_and_check("dac9 full-positive matches model");
    begin
        reg signed [15:0] dac9_val, ch_val;
        dac9_val = audio_out;
        set_neutral();
        dac_sample[0] = 8'd255; dac_vol[0] = 8'd255;
        repeat (3) @(posedge clk);
        ch_val = audio_out;
        // dac9's gain (1.0) is ~5x an 8-bit channel's (0.2); after this
        // module's DAC9_SCALE normalization the two full-scale magnitudes
        // should land in the same ballpark, not differ by orders of
        // magnitude -- a sanity bound on the normalization choice, not a
        // bit-exact MAME gain match (see leland_dac_mixer.sv header).
        check("dac9 and an 8-bit channel are within the same order of magnitude",
              (dac9_val > (ch_val / 4)) && (dac9_val < (ch_val * 8)));
    end

    // Saturation: all 6 channels + dac9 simultaneously at full positive.
    set_neutral();
    begin
        integer i;
        for (i = 0; i < 6; i = i + 1) begin
            dac_sample[i] = 8'd255;
            dac_vol[i]    = 8'd255;
        end
        dac9_sample = 10'd1023;
    end
    settle_and_check("full-scale-all-channels matches saturating model");
    check("full-scale-all-channels saturates to +32767", audio_out == 16'sd32767);

    set_neutral();
    begin
        integer i;
        for (i = 0; i < 6; i = i + 1) begin
            dac_sample[i] = 8'd0;
            dac_vol[i]    = 8'd255;
        end
        dac9_sample = 10'd0;
    end
    settle_and_check("full-scale-negative-all-channels matches saturating model");
    check("full-scale-negative-all-channels saturates to -32768", audio_out == -16'sd32768);

    $fwrite(fd, "RESULT: tests_run=%0d passed=%0d failed=%0d\n",
            tests_run, tests_passed, tests_failed);
    $display("RESULT: tests_run=%0d passed=%0d failed=%0d", tests_run, tests_passed, tests_failed);

    // ============================================================
    // Part B: synthetic full-scale test tones per channel -> real WAV
    // ============================================================
    wav_fd = $fopen("leland_dac_mixer_tones.wav", "wb");
    wav_header(wav_fd, SAMPLES_PER_SEG * 7, SAMPLE_RATE);
    play_tone_channel(0, 300);
    play_tone_channel(1, 400);
    play_tone_channel(2, 500);
    play_tone_channel(3, 600);
    play_tone_channel(4, 700);
    play_tone_channel(5, 800);
    play_tone_dac9(1000);
    $fclose(wav_fd);
    $display("WAV written: leland_dac_mixer_tones.wav (%0d samples @ %0d Hz)",
              SAMPLES_PER_SEG * 7, SAMPLE_RATE);

    $fclose(fd);
    $finish;
end

endmodule
