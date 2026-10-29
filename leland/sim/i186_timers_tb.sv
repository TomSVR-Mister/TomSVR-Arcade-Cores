// Stage-B-style directed unit test for i186_periph's timer block.
// Drives the CPU-side bus directly via the same BFM pattern
// as sim/i186_periph_tb.sv -- register-level directed tests, no
// real x86 code needed since this module is a pure bus responder plus
// a free-running counter datapath.
//
// Uses I/O-mode addressing at the reset-default page (0xFF00) so no
// RELOC reprogram is needed first: timer offsets are word-offset
// 0x28-0x33 within the page -> port 0xFF50-0xFF66 -> word_addr
// (0xFF00+byte_offset)>>1.

`timescale 1ns / 1ps

module i186_timers_tb;

localparam CLK_PERIOD = 20;
reg clk = 0;
reg reset = 1;
always #(CLK_PERIOD/2) clk = ~clk;

reg  [19:1] cpu_addr;
wire [15:0] cpu_data_in;
reg  [15:0] cpu_data_out;
reg         cpu_access;
wire        cpu_ack;
reg         cpu_wr_en;
reg  [1:0]  cpu_bytesel;
reg         cpu_d_io;

wire [19:1] sys_addr;
reg  [15:0] sys_data_in;
wire [15:0] sys_data_out;
wire        sys_access;
reg         sys_ack;
wire        sys_wr_en;
wire [1:0]  sys_bytesel;
wire        sys_d_io;

wire [19:0] ext_window_base;
wire        ext_window_is_mem;
wire        ext_window_valid;
wire [15:0] reloc_reg, umcs_reg, lmcs_reg, pacs_reg, mmcs_reg, mpcs_reg;

wire        tmrout0, tmrout1;
wire [2:0]  timer_irq;
wire [15:0] t_count[0:2], t_maxA[0:2], t_maxB[0:2], t_control[0:2];

i186_periph dut(
    .clk(clk), .reset(reset), .ce_8m(1'b1),
    .cpu_data_m_addr(cpu_addr), .cpu_data_m_data_in(cpu_data_in),
    .cpu_data_m_data_out(cpu_data_out), .cpu_data_m_access(cpu_access),
    .cpu_data_m_ack(cpu_ack), .cpu_data_m_wr_en(cpu_wr_en),
    .cpu_data_m_bytesel(cpu_bytesel), .cpu_d_io(cpu_d_io),
    .sys_data_m_addr(sys_addr), .sys_data_m_data_in(sys_data_in),
    .sys_data_m_data_out(sys_data_out), .sys_data_m_access(sys_access),
    .sys_data_m_ack(sys_ack), .sys_data_m_wr_en(sys_wr_en),
    .sys_data_m_bytesel(sys_bytesel), .sys_d_io(sys_d_io),
    .ext_window_base(ext_window_base), .ext_window_is_mem(ext_window_is_mem),
    .ext_window_valid(ext_window_valid),
    .reloc_reg(reloc_reg), .umcs_reg(umcs_reg), .lmcs_reg(lmcs_reg),
    .pacs_reg(pacs_reg), .mmcs_reg(mmcs_reg), .mpcs_reg(mpcs_reg),
    .tmrout0(tmrout0), .tmrout1(tmrout1), .timer_irq(timer_irq),
    .t_count(t_count), .t_maxA(t_maxA), .t_maxB(t_maxB), .t_control(t_control));

always @(posedge clk) begin
    if (reset) begin
        sys_ack <= 1'b0;
    end else begin
        sys_ack <= sys_access & ~sys_ack;
    end
end

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

task automatic bus_write(input [19:1] word_addr, input [15:0] data,
                          input [1:0] bytesel, input d_io);
    integer timeout;
    begin
        cpu_access = 1'b0;
        @(posedge clk);
        cpu_addr = word_addr;
        cpu_data_out = data;
        cpu_bytesel = bytesel;
        cpu_d_io = d_io;
        cpu_wr_en = 1'b1;
        cpu_access = 1'b1;
        timeout = 0;
        while (!cpu_ack && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(posedge clk);
        cpu_access = 1'b0;
        cpu_wr_en = 1'b0;
        @(posedge clk);
    end
endtask

task automatic bus_read(input [19:1] word_addr, input [1:0] bytesel,
                         input d_io, output [15:0] data_out);
    integer timeout;
    begin
        cpu_access = 1'b0;
        @(posedge clk);
        cpu_addr = word_addr;
        cpu_bytesel = bytesel;
        cpu_d_io = d_io;
        cpu_wr_en = 1'b0;
        cpu_access = 1'b1;
        timeout = 0;
        while (!cpu_ack && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        data_out = cpu_data_in;
        @(posedge clk);
        cpu_access = 1'b0;
        @(posedge clk);
    end
endtask

// I/O-mode port -> word_addr helper (page 0xFF00, reset-default RELOC).
// word_addr = (0xFF00 + byte_off) >> 1 = 0x7F80 + (byte_off >> 1),
// valid for the even byte_off values (word-aligned registers) used here.
function automatic [19:1] port_addr(input [7:0] byte_off);
    port_addr = 19'h7F80 + (byte_off >> 1);
endfunction

localparam [7:0] T0CNT = 8'h50, T0CMPA = 8'h52, T0CMPB = 8'h54, T0CON = 8'h56;
localparam [7:0] T1CNT = 8'h58, T1CMPA = 8'h5a, T1CMPB = 8'h5c, T1CON = 8'h5e;
localparam [7:0] T2CNT = 8'h60, T2CMPA = 8'h62,                T2CON = 8'h66;

reg [15:0] rd;
integer i;
integer irq_pulses;

// Waits for the next rising strobe of timer_irq[0] (bounded, so a
// stuck/never-elapsing timer fails loudly instead of hanging the sim).
task automatic wait_next_irq0;
    integer timeout;
    begin
        timeout = 0;
        while (!timer_irq[0] && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(posedge clk); // let the elapse-driven register updates settle
    end
endtask

initial begin
    fd = $fopen("i186_timers_result.txt", "w");
    tests_run = 0; tests_passed = 0; tests_failed = 0;
    cpu_access = 0; cpu_wr_en = 0; cpu_bytesel = 2'b11; cpu_d_io = 1'b1;
    cpu_addr = 0; cpu_data_out = 0;

    reset = 1;
    repeat (5) @(posedge clk);
    reset = 0;
    @(posedge clk);

    // --- Reset defaults ---
    check("reset: T0CON == 0", t_control[0] == 16'h0000);
    check("reset: T0CNT == 0", t_count[0] == 16'h0000);
    check("reset: tmrout0 == 0", tmrout0 == 1'b0);

    // --- Sanity: port_addr helper lands where expected (0xFF50 -> word
    // addr 0x7FA8).
    check("port_addr(T0CNT) == 0x7FA8", port_addr(T0CNT) == 19'h7FA8);

    // =====================================================================
    // Test 1: Timer 0, continuous mode (CONT=1, no ALT), small maxA,
    // confirm it free-runs and elapses at maxA, TMROUT0 pulses to 1,
    // MC bit sets, count resets to 0, and it reprimes (count keeps
    // going after the first elapse -- confirms continuous mode, not
    // single-shot).
    // control = EN(0x8000) | INH(0x4000, so EN write takes) | INTEN(0x2000)
    //         | CONT(0x0001) = 0xE001
    // maxA = 8 (small, so the (up to 500-cycle) test budget comfortably
    // covers several full periods: 8 counts * 4 clk/tick = 32 clk cycles
    // per period).
    bus_write(port_addr(T0CNT),  16'h0000, 2'b11, 1'b1);
    bus_write(port_addr(T0CMPA), 16'h0008, 2'b11, 1'b1);
    bus_write(port_addr(T0CON),  16'hE001, 2'b11, 1'b1);
    check("T0CMPA readback == 8", t_maxA[0] == 16'h0008);
    check("T0CON readback has EN set", t_control[0][15] == 1'b1);
    check("T0CON readback has INH cleared (bit14 always reads 0)",
          t_control[0][14] == 1'b0);

    // Wait for at least two full elapses (2 * 8 * 4 = 64 clk cycles,
    // give it generous margin).
    irq_pulses = 0;
    for (i = 0; i < 200; i = i + 1) begin
        @(posedge clk);
        if (timer_irq[0]) irq_pulses = irq_pulses + 1;
    end
    check("timer0 continuous mode: at least 2 IRQ pulses in 200 cycles",
          irq_pulses >= 2);
    check("timer0 MC bit (bit5) set after elapsing", t_control[0][5] == 1'b1);
    check("timer0 still enabled (continuous mode reprimes)",
          t_control[0][15] == 1'b1);
    check("TMROUT0 driven high (ALT=0 -> always 1 on elapse)",
          tmrout0 == 1'b1);

    // --- Rate check: with maxA=8, tick period = 4 clk, so time between
    // successive elapses should be exactly 32 clk cycles (8*4). Measure
    // it directly by watching two consecutive timer_irq[0] pulses.
    begin
        integer t0, t1, gap;
        automatic int guard;
        t0 = -1; t1 = -1; guard = 0;
        while (t1 < 0 && guard < 2000) begin
            @(posedge clk);
            guard = guard + 1;
            if (timer_irq[0]) begin
                if (t0 < 0) t0 = guard;
                else t1 = guard;
            end
        end
        gap = t1 - t0;
        check("timer0 elapse period == 32 clk cycles (maxA=8, tick=CLKOUT/4)",
              gap == 32);
    end

    // =====================================================================
    // Test 2: single-shot mode (CONT=0, ALT=0) stops after one elapse --
    // EN clears, no further IRQ pulses.
    bus_write(port_addr(T0CNT),  16'h0000, 2'b11, 1'b1);
    bus_write(port_addr(T0CMPA), 16'h0004, 2'b11, 1'b1);
    bus_write(port_addr(T0CON),  16'hC000, 2'b11, 1'b1); // EN|INH, CONT=0, INTEN=0
    // Wait past one full period (4*4=16 cycles) plus margin.
    repeat (60) @(posedge clk);
    check("single-shot timer0: EN cleared after one elapse",
          t_control[0][15] == 1'b0);
    check("single-shot timer0: MC bit set", t_control[0][5] == 1'b1);

    // Confirm it really stopped: count should stay wherever it landed
    // (0, since it reset-to-0 on elapse) rather than continuing to
    // increment.
    rd = t_count[0];
    repeat (40) @(posedge clk);
    check("single-shot timer0: count no longer advancing",
          t_count[0] == rd);

    // =====================================================================
    // Test 3: INH semantics -- writing CON without INH (bit14=0) must
    // NOT change EN, even if the write's own bit15 differs from the
    // current EN state.
    bus_write(port_addr(T0CMPA), 16'h0010, 2'b11, 1'b1);
    bus_write(port_addr(T0CON),  16'hC001, 2'b11, 1'b1); // EN|INH|CONT, INTEN=0
    check("INH test setup: EN is 1 before the no-INH write",
          t_control[0][15] == 1'b1);
    // Write with bit15=0 (asking for EN=0) but INH(bit14) NOT set --
    // per i186.cpp this must be ignored, EN stays 1.
    bus_write(port_addr(T0CON), 16'h0001, 2'b11, 1'b1);
    check("write without INH leaves EN unchanged (stays 1)",
          t_control[0][15] == 1'b1);
    // Now write with INH set and bit15=0 -- EN really clears this time.
    bus_write(port_addr(T0CON), 16'h4000, 2'b11, 1'b1);
    check("write with INH set actually updates EN (clears to 0)",
          t_control[0][15] == 1'b0);

    // =====================================================================
    // Test 4: ALT mode -- alternates maxA/maxB, TMROUT0 alternates
    // 1/0 across the two halves, RIU (bit12) toggles.
    // count isn't auto-reset by re-enabling/reprogramming maxA/maxB
    // (i186.cpp's restart_timer reuses whatever `count` already holds
    // -- real hardware behavior, not a bug) -- zero it explicitly so
    // this test's period measurements start from a known point, same
    // as real firmware would do before arming a fresh mode.
    bus_write(port_addr(T0CNT),  16'h0000, 2'b11, 1'b1);
    bus_write(port_addr(T0CMPA), 16'h0004, 2'b11, 1'b1); // maxA period
    bus_write(port_addr(T0CMPB), 16'h0006, 2'b11, 1'b1); // maxB period
    bus_write(port_addr(T0CON),  16'hE003, 2'b11, 1'b1); // EN|INH|INTEN|ALT
    check("ALT setup: ALT bit set", t_control[0][1] == 1'b1);
    check("ALT setup: RIU starts at 0 (maxA half first)",
          t_control[0][12] == 1'b0);

    // Wait for the actual timer0 IRQ pulse rather than a fixed cycle
    // count -- RIU keeps alternating every period for as long as EN
    // stays set (CONT=1 here), so a fixed-duration wait can easily
    // straddle more than one toggle and land on the wrong parity.
    // "wait_next_irq0" waits strictly for a *new* pulse (edge), not
    // just "IRQ currently asserted", since timer_irq is itself only
    // ever a single-cycle strobe.
    wait_next_irq0;
    check("ALT: after first elapse, RIU toggled to 1 (now counting maxB)",
          t_control[0][12] == 1'b1);
    check("ALT: TMROUT0 reflects pre-toggle RIU (0) after first elapse",
          tmrout0 == 1'b0);

    wait_next_irq0;
    check("ALT: after second elapse, RIU toggled back to 0",
          t_control[0][12] == 1'b0);
    check("ALT: TMROUT0 reflects pre-toggle RIU (1) after second elapse",
          tmrout0 == 1'b1);

    // =====================================================================
    // Test 5: timer 2 prescaling timer 1 (control bits [3:2]=="10" on
    // timer 1, per i186.cpp's 0x800c==0x8008 pattern). Timer 1 should
    // NOT free-run off CLKOUT/4 directly -- it should only increment on
    // timer 2's own terminal count.
    // Timer 2: continuous, maxA=5, no int (keep it simple/fast: period
    // = 5*4 = 20 clk).
    bus_write(port_addr(T2CMPA), 16'h0005, 2'b11, 1'b1);
    bus_write(port_addr(T2CON),  16'hC001, 2'b11, 1'b1); // EN|INH|CONT
    // Timer 1: EN|INH|INTEN|CONT, prescale bit3=1, EXT bit2=0 -> 0xE009
    bus_write(port_addr(T1CMPA), 16'h0003, 2'b11, 1'b1);
    bus_write(port_addr(T1CON),  16'hE009, 2'b11, 1'b1);

    // After 20 clk (one timer-2 period), timer1's count should be
    // exactly 1 (incremented once by the timer-2 elapse), NOT ~5 (which
    // is what it would be if it were wrongly free-running off CLKOUT/4
    // directly, since tick period is 4 clk -> 20/4 = 5 ticks).
    repeat (20) @(posedge clk);
    check("timer1 prescaled by timer2: count == 1 after one T2 period",
          t_count[1] == 16'h0001);

    // After 3 timer-2 periods (60 clk), timer1 (maxA=3) should have
    // elapsed exactly once (at the 3rd T2 tick) and reprimed (CONT=1),
    // so its count should be back near 0-1, and at least one IRQ pulse
    // should have fired.
    irq_pulses = 0;
    for (i = 0; i < 60; i = i + 1) begin
        @(posedge clk);
        if (timer_irq[1]) irq_pulses = irq_pulses + 1;
    end
    check("timer1 prescaled: at least one IRQ pulse over 3 more T2 periods",
          irq_pulses >= 1);

    // =====================================================================
    // Test 6: EXT-clock bit (bit2) disables internal ticking entirely
    // (no TMRIN wiring in this system -- §2 of the plan: "stub, assert
    // unused"). Confirm count simply never advances when EXT=1.
    bus_write(port_addr(T0CMPA), 16'h0002, 2'b11, 1'b1);
    bus_write(port_addr(T0CON),  16'hC005, 2'b11, 1'b1); // EN|INH|CONT|EXT(bit2)
    rd = t_count[0];
    repeat (100) @(posedge clk);
    check("EXT-clock timer0: count never advances (no TMRIN driven)",
          t_count[0] == rd);

    $fwrite(fd, "RESULT: tests_run=%0d passed=%0d failed=%0d\n", tests_run, tests_passed, tests_failed);
    if (tests_failed == 0)
        $fwrite(fd, "i186_timers (WP3) Stage-B: PASS\n");
    else
        $fwrite(fd, "i186_timers (WP3) Stage-B: FAIL\n");
    $display("RESULT: tests_run=%0d passed=%0d failed=%0d", tests_run, tests_passed, tests_failed);
    $fclose(fd);
    $finish;
end

endmodule
