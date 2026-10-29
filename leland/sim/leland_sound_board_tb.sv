// Stage-C-style directed integration test for the board glue: i186_periph
// wired to the real leland_sound_board exactly as the
// real 80186 would see it -- CPU-side bus in, external PCS window +
// I/O-space dac_w decoded, PIT0/PIT1 (KF8253) driving the polled
// DAC-clock status bits. No real s80x86 Core here (that integration is
// deferred to a later integration bench); this bench is a BFM driving
// i186_periph's CPU-side port directly, matching the Stage-B precedent
// in i186_periph_tb.sv/i186_intc_tb.sv.
//
// Covers the plan's Stage C acceptance ("polled DAC path... end-to-end"):
// (a) sequence-accurate: exact captured MAME programming sequences
//     (relocation-register move to memory mode, PACS/MPCS CSU setup,
//     PIT0 mode-2/divisor-423 programming) replayed byte-for-byte and
//     landing at the MAME-observed addresses/values;
// (b) rate-locked: PIT0 counter0's out edge drives clock_active bit2,
//     and a polled dac_w to channel 2 clears it -- checked directly,
//     not eyeballed.
// Plus directed coverage of decode correctness that (a)/(b) alone
// wouldn't exercise: dac9's word-write-only quirk (R10), the DRQ-clear
// region decode (R1/R2), and the select-0 status-register bit mapping.

`timescale 1ns / 1ps

module leland_sound_board_tb;

localparam CLK_PERIOD = 20; // matches i186_periph_tb/i186_intc_tb convention
reg clk = 0;
reg reset = 1;
always #(CLK_PERIOD/2) clk = ~clk;

// --- i186_periph CPU-side port (BFM-driven, stands in for the real core) ---
reg  [19:1] cpu_addr;
wire [15:0] cpu_data_in;
reg  [15:0] cpu_data_out;
reg         cpu_access;
wire        cpu_ack;
reg         cpu_wr_en;
reg  [1:0]  cpu_bytesel;
reg         cpu_d_io;

// --- i186_periph <-> leland_sound_board (sys-side of periph == cpu-side of board) ---
wire [19:1] sb_addr;
wire [15:0] sb_data_in;
wire [15:0] sb_data_out;
wire        sb_access;
wire        sb_ack;
wire        sb_wr_en;
wire [1:0]  sb_bytesel;
wire        sb_d_io;

wire [19:0] ext_window_base;
wire        ext_window_is_mem;
wire        ext_window_valid;
wire [15:0] reloc_reg, umcs_reg, lmcs_reg, pacs_reg, mmcs_reg, mpcs_reg;
wire        tmrout0, tmrout1;
wire [2:0]  timer_irq, timer_tc_pulse;
wire [15:0] t_count[0:2], t_maxA[0:2], t_maxB[0:2], t_control[0:2];
wire        intr; wire [7:0] irq_out; reg inta;
reg         int0_pin_stub, int1_pin_stub; // periph's own int0/int1 inputs -- unused by
                                            // this bench (board module owns the *board-side*
                                            // control-register-driven int0/int1 net,
                                            // wired to periph's int0_pin/int1_pin later)
wire        dma0_irq_req_stub = 1'b0, dma1_irq_req_stub = 1'b0;
wire [7:0]  intc_request_reg, intc_in_service_reg;
wire [2:0]  intc_status_reg;
wire [3:0]  intc_timer0_ctrl_reg, intc_dma0_ctrl_reg, intc_dma1_ctrl_reg;
wire [6:0]  intc_ext0_ctrl_reg, intc_ext1_ctrl_reg;

i186_periph periph(
    .clk(clk), .reset(reset), .ce_8m(1'b1),
    .cpu_data_m_addr(cpu_addr), .cpu_data_m_data_in(cpu_data_in),
    .cpu_data_m_data_out(cpu_data_out), .cpu_data_m_access(cpu_access),
    .cpu_data_m_ack(cpu_ack), .cpu_data_m_wr_en(cpu_wr_en),
    .cpu_data_m_bytesel(cpu_bytesel), .cpu_d_io(cpu_d_io),
    .sys_data_m_addr(sb_addr), .sys_data_m_data_in(sb_data_in),
    .sys_data_m_data_out(sb_data_out), .sys_data_m_access(sb_access),
    .sys_data_m_ack(sb_ack), .sys_data_m_wr_en(sb_wr_en),
    .sys_data_m_bytesel(sb_bytesel), .sys_d_io(sb_d_io),
    .ext_window_base(ext_window_base), .ext_window_is_mem(ext_window_is_mem),
    .ext_window_valid(ext_window_valid),
    .reloc_reg(reloc_reg), .umcs_reg(umcs_reg), .lmcs_reg(lmcs_reg),
    .pacs_reg(pacs_reg), .mmcs_reg(mmcs_reg), .mpcs_reg(mpcs_reg),
    .tmrout0(tmrout0), .tmrout1(tmrout1), .timer_irq(timer_irq),
    .timer_tc_pulse(timer_tc_pulse),
    .t_count(t_count), .t_maxA(t_maxA), .t_maxB(t_maxB), .t_control(t_control),
    .intr(intr), .irq_out(irq_out), .inta(inta),
    .int0_pin(int0_pin_stub), .int1_pin(int1_pin_stub),
    .dma0_irq_req(dma0_irq_req_stub), .dma1_irq_req(dma1_irq_req_stub),
    .intc_request_reg(intc_request_reg), .intc_in_service_reg(intc_in_service_reg),
    .intc_status_reg(intc_status_reg),
    .intc_timer0_ctrl_reg(intc_timer0_ctrl_reg), .intc_dma0_ctrl_reg(intc_dma0_ctrl_reg),
    .intc_dma1_ctrl_reg(intc_dma1_ctrl_reg),
    .intc_ext0_ctrl_reg(intc_ext0_ctrl_reg), .intc_ext1_ctrl_reg(intc_ext1_ctrl_reg));

// --- board's passthrough memory (trivial single-cycle-ack stub) ---
wire [19:1] mem_addr;
wire [15:0] mem_data_in;
wire [15:0] mem_data_out;
wire        mem_access;
reg         mem_ack;
wire        mem_wr_en;
wire [1:0]  mem_bytesel;
wire        mem_d_io;
assign mem_data_in = {13'h0, mem_addr[3:1]}; // echoes low addr bits, enough to prove passthrough
always @(posedge clk) begin
    if (reset) mem_ack <= 1'b0;
    else mem_ack <= mem_access & ~mem_ack;
end

reg  [15:0] cmd_wr_data;
reg         cmd_wr_lo, cmd_wr_hi;
wire [7:0]  response_data;
wire        response_wr;
reg  [7:0]  control_data;
reg         control_wr;
wire        audiocpu_reset_n, audiocpu_test_n, int0_pin, int1_pin;
wire [7:0]  dac_sample[0:5];
wire [7:0]  dac_vol[0:5];
wire        dac_wr[0:5];
wire [9:0]  dac9_sample;
wire        dac9_wr;
wire        drq0_pit_level, drq1_pit_level, drq0_clear, drq1_clear;
wire [6:0]  clock_active;

reg pit_ce;

// Sticky catchers for board.sv's 1-cycle write-strobe outputs -- the
// bus_write task's own settle cycles (dropping cpu_access, one more
// @(posedge clk)) run past the single cycle these pulse for, so a
// direct post-task check would always see them already low again.
reg resp_wr_sticky, dac2_wr_sticky, drq0_clear_sticky, drq1_clear_sticky;
always @(posedge clk) begin
    if (reset) begin
        resp_wr_sticky     <= 1'b0;
        dac2_wr_sticky      <= 1'b0;
        drq0_clear_sticky  <= 1'b0;
        drq1_clear_sticky  <= 1'b0;
    end else begin
        if (response_wr)  resp_wr_sticky     <= 1'b1;
        if (dac_wr[2])     dac2_wr_sticky      <= 1'b1;
        if (drq0_clear)    drq0_clear_sticky  <= 1'b1;
        if (drq1_clear)    drq1_clear_sticky  <= 1'b1;
    end
end

leland_sound_board board(
    .clk(clk), .reset(reset),
    .cpu_addr(sb_addr), .cpu_data_in(sb_data_in), .cpu_data_out(sb_data_out),
    .cpu_access(sb_access), .cpu_ack(sb_ack), .cpu_wr_en(sb_wr_en),
    .cpu_bytesel(sb_bytesel), .cpu_d_io(sb_d_io),
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
    .int0_pin(int0_pin), .int1_pin(int1_pin),
    .dac_sample(dac_sample), .dac_vol(dac_vol), .dac_wr(dac_wr),
    .dac9_sample(dac9_sample), .dac9_wr(dac9_wr),
    .drq0_pit_level(drq0_pit_level), .drq1_pit_level(drq1_pit_level),
    .drq0_clear(drq0_clear), .drq1_clear(drq1_clear),
    .clock_active(clock_active));

// Free-running PIT clock enable -- not calibrated to a real 8/4 MHz
// ratio (this bench cares about edge-count/decode correctness and
// measured-period *ratios*, not absolute Hz); pulses every other clk.
reg pce_div;
always @(posedge clk or posedge reset) begin
    if (reset) begin pce_div <= 1'b0; pit_ce <= 1'b0; end
    else begin pce_div <= ~pce_div; pit_ce <= pce_div; end
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
        while (!cpu_ack && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check({"ack seen for write to ", $sformatf("%05h", {word_addr,1'b0})}, timeout < 200);
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
        while (!cpu_ack && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check({"ack seen for read of ", $sformatf("%05h", {word_addr,1'b0})}, timeout < 200);
        data_out = cpu_data_in;
        @(posedge clk);
        cpu_access = 1'b0;
        @(posedge clk);
    end
endtask

// I/O-mode internal-register port -> word_addr (reset-default RELOC page 0xFF00).
function automatic [19:1] io_port_addr(input [7:0] byte_off);
    io_port_addr = 19'h7F80 + (byte_off >> 1);
endfunction

// Memory-mode internal-register byte offset -> word_addr, given the
// page this bench programs into RELOC (MAME-observed 0x203 -> base 0x20300).
// NOTE: byte_off is the real 80186 port byte address (e.g. PACS=0xA4,
// MPCS=0xA8 -- standard 80186 datasheet map), NOT i186_periph.sv's
// `word_offset` case-label value (which is byte_off>>1, e.g. PACS's
// case label is 7'h52) -- conflating the two was a real bug caught
// while bringing this bench up.
function automatic [19:1] mem_internal_addr(input [7:0] byte_off);
    mem_internal_addr = (20'h20300 + {12'h0, byte_off}) >> 1;
endfunction

// External-window byte offset (0-0x2FF) -> word_addr (base 0x20000, MAME-observed).
function automatic [19:1] win_addr(input [11:0] byte_off);
    win_addr = (20'h20000 + {8'h0, byte_off}) >> 1;
endfunction

// I/O-space dac_w word address for a given (region[1:0], dac_index[2:0]).
// Sets cpu_addr[7:6]=region and cpu_addr[3:1]=dac directly -- the exact
// same bit slices leland_sound_board.sv's drq_region/dac_index read, so
// there's no separate byte<->word re-derivation to get wrong here.
function automatic [19:1] io_dac_addr(input [1:0] region, input [2:0] dac);
    reg [19:1] v;
    begin
        v = 19'h0;
        v[7:6] = region;
        v[3:1] = dac;
        io_dac_addr = v;
    end
endfunction

reg  [15:0] rd;
reg  [2:0]  passthrough_expect;
integer i;

initial begin
    fd = $fopen("leland_sound_board_results.log", "w");
    tests_run = 0; tests_passed = 0; tests_failed = 0;

    cpu_access = 0; cpu_wr_en = 0; cpu_bytesel = 2'b11; cpu_d_io = 0;
    cpu_addr = 0; cpu_data_out = 0;
    cmd_wr_data = 0; cmd_wr_lo = 0; cmd_wr_hi = 0;
    control_data = 8'h00; control_wr = 0;
    inta = 0; int0_pin_stub = 0; int1_pin_stub = 0;

    repeat (5) @(posedge clk);
    reset = 0;
    repeat (5) @(posedge clk);

    // ============================================================
    // Part 1: exact captured CSU bring-up sequence (PACS/MPCS table)
    // ============================================================
    bus_write(io_port_addr(8'hFE), 16'h9203, 2'b11, 1'b1); // RELOC -> mem mode, page 0x203
    check("RELOC readback == 0x9203", reloc_reg == 16'h9203);

    bus_write(mem_internal_addr(8'hA4), 16'h203C, 2'b11, 1'b0); // PACS
    check("PACS readback == 0x203C", pacs_reg == 16'h203C);

    bus_write(mem_internal_addr(8'hA8), 16'hC0FC, 2'b11, 1'b0); // MPCS
    check("MPCS readback == 0xC0FC", mpcs_reg == 16'hC0FC);
    check("ext window valid",   ext_window_valid == 1'b1);
    check("ext window is mem",  ext_window_is_mem == 1'b1);
    check("ext window base == 0x20000", ext_window_base == 20'h20000);

    // ============================================================
    // Part 2: exact captured PIT0 programming sequence, replayed
    // through the external window at select 2 -- must land on KF8253
    // without timing out, same replay kf8253_leland_bus_tb already proved
    // for the wrapper in isolation.
    // ============================================================
    bus_write(win_addr(12'h106), 16'h0034, 2'b01, 1'b0); // control word
    bus_write(win_addr(12'h100), 16'h00A7, 2'b01, 1'b0); // counter0 LSB
    bus_write(win_addr(12'h100), 16'h0001, 2'b01, 1'b0); // counter0 MSB

    // Also program counter2 (drives clock_active[2], Part 3 below) --
    // control byte 0xD4: SC=10(counter2) RW=11(LSB/MSB) MODE=010(rate
    // gen) BCD=0; short divisor (50) purely so this bench doesn't have
    // to wait out a real-world PIT period to see an edge.
    bus_write(win_addr(12'h106), 16'h00D4, 2'b01, 1'b0); // control word (counter2)
    bus_write(win_addr(12'h104), 16'h0032, 2'b01, 1'b0); // counter2 LSB = 50
    bus_write(win_addr(12'h104), 16'h0000, 2'b01, 1'b0); // counter2 MSB = 0

    // Measure counter_0_out's period against the programmed divisor
    // (0x01A7 = 423), same methodology as kf8253_leland_bus_tb.
    begin
        integer t0, t1, edges, wd;
        edges = 0; t0 = 0; t1 = 0; wd = 0;
        fork
            begin
                @(posedge board.pit0_c0_out);
                t0 = $time;
                @(posedge board.pit0_c0_out);
                t1 = $time;
                edges = 1;
            end
            begin
                #200000; // watchdog
            end
        join_any
        disable fork;
        check("PIT0 counter0 produced two edges within watchdog", edges == 1);
        if (edges == 1) begin
            integer measured_period, expected_period;
            measured_period = t1 - t0;
            // pit_ce pulses every 2 clk periods (see the generator
            // above); counter divisor 423 -> 423 pit_ce pulses per
            // half of KF8253's own internal cycling. This check is a
            // ratio/sanity bound (bench pit_ce isn't calibrated to a
            // real 4 MHz), not an absolute-Hz assertion.
            expected_period = 423 * 2 * CLK_PERIOD;
            check("PIT0 counter0 period is in the expected ballpark",
                  (measured_period > expected_period/2) && (measured_period < expected_period*4));
        end
    end

    // ============================================================
    // Part 3: select-0 clock-active status + polled dac_w clear
    // (Stage C (a)/(b): sequence + rate-lock on the polled path)
    // ============================================================
    // Wait for PIT0 counter2's first rising edge (drives clock_active[2]).
    @(posedge board.pit0_c2_out);
    @(posedge clk); @(posedge clk); // let the edge-detect register settle
    check("clock_active[2] set after PIT0 out2 rising edge", clock_active[2] == 1'b1);

    bus_read(win_addr(12'h000), 2'b11, 1'b0, rd);
    check("select-0 status reflects clock_active[2] (bit1 of readback)",
          rd[1] == 1'b1);

    // Polled write to DAC channel 2 (region 00, matching the plan's
    // "manual" polled-channel decode -- DRQ0/1 only associate with
    // region 0x40/0x60, i.e. dac 0/1).
    bus_write(io_dac_addr(2'b00, 3'd2), 16'h5A00, 2'b01, 1'b1);
    check("dac_sample[2] latched", dac_sample[2] == 8'h00);
    check("dac_wr[2] pulsed", dac2_wr_sticky == 1'b1);
    @(posedge clk);
    check("clock_active[2] cleared by dac_w", clock_active[2] == 1'b0);
    check("drq0_clear NOT asserted for region-00 write", drq0_clear == 1'b0);
    check("drq1_clear NOT asserted for region-00 write", drq1_clear == 1'b0);

    // Volume (high byte lane) write to the same channel.
    bus_write(io_dac_addr(2'b00, 3'd2), 16'h5A77, 2'b10, 1'b1);
    @(posedge clk);
    check("dac_vol[2] latched", dac_vol[2] == 8'h5A);

    // ============================================================
    // Part 4: DRQ-clear region decode (R1/R2) for dac 0/1
    // ============================================================
    bus_write(io_dac_addr(2'b10, 3'd0), 16'h0011, 2'b01, 1'b1); // region 0x40 -> drq0
    check("drq0_clear asserted for region-10/dac0 write", drq0_clear_sticky == 1'b1);
    check("dac_sample[0] latched via DMA-region write", dac_sample[0] == 8'h11);

    bus_write(io_dac_addr(2'b11, 3'd1), 16'h0022, 2'b01, 1'b1); // region 0x60 -> drq1
    check("drq1_clear asserted for region-11/dac1 write", drq1_clear_sticky == 1'b1);
    check("dac_sample[1] latched via DMA-region write", dac_sample[1] == 8'h22);

    // ============================================================
    // Part 5: dac9 word-write-only quirk (R10)
    // ============================================================
    // Test vector's low 10 bits (0x4300 -> 0x300) deliberately avoid
    // 0x200/10'd512 -- dac9_sample's reset default
    // (leland_sound_board.sv: the neutral 10'd512), which would make
    // this check pass vacuously regardless of whether the byte write
    // was actually ignored.
    bus_write(win_addr(12'h200), 16'h4300, 2'b01, 1'b0); // byte write -- must be IGNORED
    @(posedge clk);
    check("dac9 ignores byte-lane write (R10)", dac9_sample != 10'h300);

    bus_write(win_addr(12'h200), 16'h0345, 2'b11, 1'b0); // full word -- accepted
    @(posedge clk);
    check("dac9 accepts word write", dac9_sample == 10'h345);
    check("clock_active[6] cleared by dac9 write", clock_active[6] == 1'b0);

    // TMROUT0 (timer 0) terminal count sets clock_active[6] -- program
    // timer 0 for a short period and confirm the bit sets without
    // waiting on a real dac9 poll loop.
    bus_write(mem_internal_addr(8'h52), 16'h0005, 2'b11, 1'b0); // T0CMPA = 5
    // T0CON: EN, continuous, no ALT -- the captured 0x8021 is a
    // *readback* value (INH/bit14 always reads 0, i186_periph.sv's
    // mask_control()); the write that actually latches EN must set
    // INH(bit14) itself in the same write, or EN is silently ignored
    // and the old (post-reset 0) value is kept -- a real 80186 quirk,
    // not a bug in this bench's first draft (caught here) nor in the
    // DUT.
    bus_write(mem_internal_addr(8'h56), 16'hC021, 2'b11, 1'b0);
    begin
        integer wd2;
        wd2 = 0;
        fork
            begin
                wait (clock_active[6] == 1'b1);
                wd2 = 1;
            end
            #500000;
        join_any
        disable fork;
        check("clock_active[6] set by timer0 terminal count", wd2 == 1);
    end

    // ============================================================
    // Part 6: command/response latch (select 1) + control register
    // ============================================================
    cmd_wr_data = 16'hBEEF;
    cmd_wr_lo = 1'b1; @(posedge clk); cmd_wr_lo = 1'b0; @(posedge clk);
    cmd_wr_hi = 1'b1; @(posedge clk); cmd_wr_hi = 1'b0; @(posedge clk);
    bus_read(win_addr(12'h080), 2'b11, 1'b0, rd);
    check("select-1 read returns Z80-written command latch", rd == 16'hBEEF);

    bus_write(win_addr(12'h080), 16'h0042, 2'b01, 1'b0);
    check("response_wr pulsed", resp_wr_sticky == 1'b1);
    check("response_data latched", response_data == 8'h42);

    control_data = 8'hB0; // /RESET deasserted(bit7=1), /TEST deasserted(bit4=1), INT0=1, INT1=0
    control_wr = 1'b1; @(posedge clk); control_wr = 1'b0; @(posedge clk);
    check("audiocpu_reset_n follows control bit7", audiocpu_reset_n == 1'b1);
    check("audiocpu_test_n follows control bit4",  audiocpu_test_n == 1'b1);
    check("int0_pin follows control bit5",          int0_pin == 1'b1);
    check("int1_pin follows control bit3",          int1_pin == 1'b0);

    // ============================================================
    // Part 7: passthrough (an access outside both the I/O space and
    // the ext window must reach the system memory stub unmodified)
    // ============================================================
    bus_read(19'h08000, 2'b11, 1'b0, rd); // arbitrary ROM-space address
    passthrough_expect = 19'h08000 & 19'h00007;
    check("passthrough read reaches mem stub", rd == {13'h0, passthrough_expect});

    $fwrite(fd, "RESULT: tests_run=%0d passed=%0d failed=%0d\n",
            tests_run, tests_passed, tests_failed);
    $fclose(fd);
    $display("RESULT: tests_run=%0d passed=%0d failed=%0d", tests_run, tests_passed, tests_failed);
    $finish;
end

endmodule
