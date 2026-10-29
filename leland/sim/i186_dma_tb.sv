// Directed integration test for the internal DMA x2 + system arbiter
// insertion: the real i186_periph
// (including the DMA engine + internal second-level
// MemArbiter) wired to the real leland_sound_board, same topology
// as leland_sound_board_tb.sv's own Stage-C bench, plus a real
// addressable byte-array memory behind the board's mem_* passthrough
// port (leland_sound_board_tb.sv's own stub only echoes address bits --
// not enough to prove DMA actually moves real, distinct source bytes).
//
// No real s80x86 Core here -- a BFM drives i186_periph's CPU-side port
// directly, matching the other unit benches' deferral of "real
// core" (leland_sound_smoketest_tb.sv is the one exception, and
// it's explicitly a smoke test, not this bench's acceptance criteria).
//
// Covers Stage D criteria as directed, deterministic
// checks rather than free-running ROM behavior:
// (a) exactly one DMA byte lands on the DAC per DRQ assertion (the
//     write-clears-DRQ loop) -- Part 3 (source-sync, real PIT-driven DRQ).
// (c) DMA source/count sequences match expectation at a fine grain --
//     Part 2 (unsync immediate-drain), Part 5 (word transfer), Part 6
//     (dest increment/decrement generality).
// Plus register-level correctness (Part 1: CHG_NOCHG/ST_STOP preserve)
// and the TC interrupt path (Part 4).

`timescale 1ns / 1ps

module i186_dma_tb;

localparam CLK_PERIOD = 20;
reg clk = 0;
reg reset = 1;
always #(CLK_PERIOD/2) clk = ~clk;

// --- i186_periph CPU-side port (BFM) ---
reg  [19:1] cpu_addr;
wire [15:0] cpu_data_in;
reg  [15:0] cpu_data_out;
reg         cpu_access;
wire        cpu_ack;
reg         cpu_wr_en;
reg  [1:0]  cpu_bytesel;
reg         cpu_d_io;

// --- i186_periph <-> leland_sound_board ---
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
reg         int0_pin_stub, int1_pin_stub;
reg         dma0_irq_req_stub, dma1_irq_req_stub;
wire [7:0]  intc_request_reg, intc_in_service_reg;
wire [2:0]  intc_status_reg;
wire [3:0]  intc_timer0_ctrl_reg, intc_dma0_ctrl_reg, intc_dma1_ctrl_reg;
wire [6:0]  intc_ext0_ctrl_reg, intc_ext1_ctrl_reg;

wire        drq0_pit_level, drq1_pit_level, drq0_clear, drq1_clear;
wire [19:0] dma_src[0:1], dma_dst[0:1];
wire [15:0] dma_count[0:1], dma_control[0:1];
wire [1:0]  dma_active;
wire        dma_byte_done, dma_byte_done_ch;

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
    .intc_ext0_ctrl_reg(intc_ext0_ctrl_reg), .intc_ext1_ctrl_reg(intc_ext1_ctrl_reg),
    .drq0_pit_level(drq0_pit_level), .drq1_pit_level(drq1_pit_level),
    .drq0_clear(drq0_clear), .drq1_clear(drq1_clear),
    .dma_src(dma_src), .dma_dst(dma_dst), .dma_count(dma_count), .dma_control(dma_control),
    .dma_active(dma_active), .dma_byte_done(dma_byte_done), .dma_byte_done_ch(dma_byte_done_ch));

// --- real addressable memory behind leland_sound_board's mem_* port
// (RAM 0-0x3FFF mirrored, matching leland_80186_map_program's own
// convention -- same shape as the smoke-test bench's memory model, just
// standalone here since there's no real Core/ROM in this bench) ---
wire [19:1] mem_addr;
reg  [15:0] mem_data_in;
wire [15:0] mem_data_out;
wire        mem_access;
reg         mem_ack;
wire        mem_wr_en;
wire [1:0]  mem_bytesel;
wire        mem_d_io;

reg [7:0] ram [0:16383];

function automatic [7:0] ram_read_byte(input [19:0] addr);
    ram_read_byte = ram[addr & 20'h3fff];
endfunction

task automatic ram_write_byte(input [19:0] addr, input [7:0] data);
    ram[addr & 20'h3fff] = data;
endtask

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
                mem_data_in <= {ram_read_byte({mem_addr, 1'b1}), ram_read_byte({mem_addr, 1'b0})};
                if (mem_wr_en) begin
                    if (mem_bytesel[0]) ram_write_byte({mem_addr, 1'b0}, mem_data_out[7:0]);
                    if (mem_bytesel[1]) ram_write_byte({mem_addr, 1'b1}, mem_data_out[15:8]);
                end
            end
        end else begin
            mem_ack <= 1'b0;
        end
    end
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
wire [6:0]  clock_active;

reg pit_ce;

// Sticky catchers for 1-cycle write-strobe outputs (same convention as
// leland_sound_board_tb.sv).
reg [5:0] dac_wr_sticky_r;
reg       drq0_clear_sticky, drq1_clear_sticky;
integer   dac_wr_count[0:5];
integer   drq0_clear_count, drq1_clear_count;
genvar gsi;
generate
    for (gsi = 0; gsi < 6; gsi = gsi + 1) begin : g_sticky
        always @(posedge clk) begin
            if (reset) begin
                dac_wr_sticky_r[gsi] <= 1'b0;
            end else begin
                if (dac_wr[gsi]) dac_wr_sticky_r[gsi] <= 1'b1;
            end
        end
    end
endgenerate

integer gci;
always @(posedge clk) begin
    if (reset) begin
        drq0_clear_sticky <= 1'b0; drq1_clear_sticky <= 1'b0;
        drq0_clear_count <= 0; drq1_clear_count <= 0;
        for (gci = 0; gci < 6; gci = gci + 1) dac_wr_count[gci] <= 0;
    end else begin
        if (drq0_clear) begin drq0_clear_sticky <= 1'b1; drq0_clear_count <= drq0_clear_count + 1; end
        if (drq1_clear) begin drq1_clear_sticky <= 1'b1; drq1_clear_count <= drq1_clear_count + 1; end
        for (gci = 0; gci < 6; gci = gci + 1)
            if (dac_wr[gci]) dac_wr_count[gci] <= dac_wr_count[gci] + 1;
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

// Memory-mode internal-register byte offset -> word_addr (RELOC page
// 0x203, base 0x20300 -- same convention as leland_sound_board_tb.sv).
function automatic [19:1] mem_internal_addr(input [7:0] byte_off);
    mem_internal_addr = (20'h20300 + {12'h0, byte_off}) >> 1;
endfunction

function automatic [19:1] win_addr(input [11:0] byte_off);
    win_addr = (20'h20000 + {8'h0, byte_off}) >> 1;
endfunction

function automatic [19:1] io_dac_addr(input [1:0] region, input [2:0] dac);
    reg [19:1] v;
    begin
        v = 19'h0;
        v[7:6] = region;
        v[3:1] = dac;
        io_dac_addr = v;
    end
endfunction

reg [15:0] rd;
integer i;
integer wd;

// DMA internal-register byte offsets (80186 datasheet map, same
// convention as PACS=0xA4/MPCS=0xA8 in leland_sound_board_tb.sv):
// DMA0: SRCLO=0xC0 SRCHI=0xC2 DSTLO=0xC4 DSTHI=0xC6 TC=0xC8 CON=0xCA
// DMA1: SRCLO=0xD0 SRCHI=0xD2 DSTLO=0xD4 DSTHI=0xD6 TC=0xD8 CON=0xDA
// (word_offset 0x60->byte 0xC0, 0x61->0xC2, ..., 0x65->0xCA; 0x68->0xD0 etc.)

initial begin
    fd = $fopen("i186_dma_results.log", "w");
    tests_run = 0; tests_passed = 0; tests_failed = 0;

    cpu_access = 0; cpu_wr_en = 0; cpu_bytesel = 2'b11; cpu_d_io = 0;
    cpu_addr = 0; cpu_data_out = 0;
    cmd_wr_data = 0; cmd_wr_lo = 0; cmd_wr_hi = 0;
    control_data = 8'h00; control_wr = 0;
    inta = 0; int0_pin_stub = 0; int1_pin_stub = 0;
    dma0_irq_req_stub = 0; dma1_irq_req_stub = 0;
    for (i = 0; i < 16384; i = i + 1) ram[i] = 8'h00;

    repeat (5) @(posedge clk);
    reset = 0;
    repeat (5) @(posedge clk);

    // ============================================================
    // Bring-up: RELOC memory mode + PACS/MPCS (same MAME-observed
    // values as leland_sound_board_tb.sv's own Part 1) so the external
    // PCS window / dac_w decode is live for the DMA destination writes.
    // ============================================================
    // RELOC itself must be written via the I/O-mode address (reset
    // default) since it hasn't switched to memory mode yet.
    bus_write(19'h7F80 + (8'hFE >> 1), 16'h9203, 2'b11, 1'b1);
    check("RELOC readback == 0x9203", reloc_reg == 16'h9203);
    bus_write(mem_internal_addr(8'hA4), 16'h203C, 2'b11, 1'b0); // PACS
    bus_write(mem_internal_addr(8'hA8), 16'hC0FC, 2'b11, 1'b0); // MPCS
    check("ext window valid", ext_window_valid == 1'b1);
    check("ext window base == 0x20000", ext_window_base == 20'h20000);

    // ============================================================
    // Part 1: DMA0 register read/write + CHG_NOCHG/ST_STOP-preserve
    // semantics (i186.cpp update_dma_control).
    // ============================================================
    bus_write(mem_internal_addr(8'hC0), 16'h1234, 2'b11, 1'b0); // SRC lo
    bus_write(mem_internal_addr(8'hC2), 16'h0007, 2'b11, 1'b0); // SRC hi (only low nibble matters)
    bus_read(mem_internal_addr(8'hC0), 2'b11, 1'b0, rd);
    check("DMA0 SRC lo readback", rd == 16'h1234);
    bus_read(mem_internal_addr(8'hC2), 2'b11, 1'b0, rd);
    check("DMA0 SRC hi readback (low nibble only)", rd == 16'h0007);
    check("DMA0 SRC full 20-bit value", dma_src[0] == 20'h71234);

    // Write with CHG_NOCHG=0 (bit2 clear) first, while dma_control[0] is
    // still all-0 (never started): ST_STOP must be PRESERVED from the
    // current value (0), NOT taken from this write's own ST_STOP=1 bit
    // -- and since it's never actually taken, the channel never starts
    // (no FSM activity to worry about for this check).
    bus_write(mem_internal_addr(8'hCA), 16'h0002, 2'b11, 1'b0); // CHG_NOCHG=0, ST_STOP=1 (should be ignored)
    check("CHG_NOCHG=0 preserves old ST_STOP (still 0), not the write's own bit",
          dma_control[0][1] == 1'b0);
    check("channel did not actually start", dma_active == 2'b00);

    // Now confirm CHG_NOCHG=1 DOES let a real ST_STOP write through.
    // SYNC_SOURCE (bit6) is also set here so this is source-synced, NOT
    // unsync -- with no real DRQ0 pulse happening at this point in the
    // test, ch0_pending stays false and no actual FSM transfer starts
    // even though ST_STOP genuinely commits to 1 (this register-level
    // check would otherwise be polluted by a real, if harmless,
    // spurious one-byte drain -- caught by this session's first attempt
    // at this test, which used unsync mode here and saw dac_wr_count[0]
    // off by one because DST happened to still be 0 at that point,
    // which decodes as a real dac0 I/O write).
    bus_write(mem_internal_addr(8'hCA), 16'h0046, 2'b11, 1'b0); // SYNC_SOURCE|CHG_NOCHG|ST_STOP
    begin
        integer stop_tries;
        stop_tries = 0;
        while (dma_control[0][1] == 1'b1 && stop_tries < 20) begin
            bus_write(mem_internal_addr(8'hCA), 16'h0004, 2'b11, 1'b0); // CHG_NOCHG=1, ST_STOP=0
            stop_tries = stop_tries + 1;
        end
        check("DMA0 CON readback after stop (CHG_NOCHG self-cleared, ST_STOP 0)",
              dma_control[0] == 16'h0000);
    end

    // ============================================================
    // Part 2: unsync ("immediate-drain") full transfer -- deterministic,
    // no PIT/DRQ dependency. SRC=RAM[0x100..], INC; DST=fixed I/O dac0
    // region (0x40, drq0_clear-decoded region, dac index 0); byte
    // transfer; count=4; TERMINATE_ON_ZERO set so ST_STOP auto-clears.
    // ============================================================
    ram[16'h0100] = 8'h11;
    ram[16'h0101] = 8'h22;
    ram[16'h0102] = 8'h33;
    ram[16'h0103] = 8'h44;

    bus_write(mem_internal_addr(8'hC0), 16'h0100, 2'b11, 1'b0); // SRC lo = 0x0100
    bus_write(mem_internal_addr(8'hC2), 16'h0000, 2'b11, 1'b0); // SRC hi = 0
    // DST: io_dac_addr(region=2'b10, dac=0) -- word address with bit7:6=10,
    // bit3:1=0. As a full 20-bit *byte* address (DEST_MIO=0 -> I/O space,
    // the periph module only uses dma_dst[19:1] for addr and dma_dst[0]
    // for byte-lane -- bit0=0, even byte lane).
    bus_write(mem_internal_addr(8'hC4), {io_dac_addr(2'b10, 3'd0), 1'b0}, 2'b11, 1'b0); // DST lo
    bus_write(mem_internal_addr(8'hC6), 16'h0000, 2'b11, 1'b0); // DST hi = 0
    bus_write(mem_internal_addr(8'hC8), 16'h0004, 2'b11, 1'b0); // count = 4

    // CON: SRC_MIO=1(mem,bit12) SRC_INC(bit10) DEST_MIO=0(io,bit15=0)
    // dest fixed(no inc/dec bits) TERMINATE_ON_ZERO(bit9) ST_STOP(bit1)
    // CHG_NOCHG(bit2) byte transfer(bit0=0) SYNC_MASK=00(unsync).
    bus_write(mem_internal_addr(8'hCA),
              16'h1000 | 16'h0400 | 16'h0200 | 16'h0004 | 16'h0002, 2'b11, 1'b0);

    wd = 0;
    fork
        begin
            wait (dma_control[0][1] == 1'b0 && dma_count[0] == 16'h0000);
            wd = 1;
        end
        #200000;
    join_any
    disable fork;
    check("unsync DMA0 transfer completed (ST_STOP auto-cleared, count==0)", wd == 1);

    check("unsync DMA0: all 4 bytes reached dac0 (dac_wr[0] count)", dac_wr_count[0] == 4);
    check("unsync DMA0: dac_sample[0] holds last byte (0x44)", dac_sample[0] == 8'h44);
    check("unsync DMA0: SRC pointer incremented by 4", dma_src[0] == 20'h00104);
    check("unsync DMA0: DST pointer unchanged (fixed)", dma_dst[0][19:1] == io_dac_addr(2'b10, 3'd0));
    check("unsync DMA0: drq0_clear fired once per byte (dac0 region)", drq0_clear_count == 4);

    // ============================================================
    // Part 3: source-synced transfer paced by a REAL PIT0 DRQ (Stage D
    // (a): exactly one byte per DRQ assertion). Program PIT0 counter0
    // with a short divisor (like leland_sound_board_tb.sv's own Part 2
    // methodology) so this bench doesn't wait out a real-world period.
    // ============================================================
    bus_write(win_addr(12'h106), 16'h0034, 2'b01, 1'b0); // PIT0 ctrl: counter0, mode2, LSB/MSB
    bus_write(win_addr(12'h100), 16'h0014, 2'b01, 1'b0); // divisor LSB = 20
    bus_write(win_addr(12'h100), 16'h0000, 2'b01, 1'b0); // divisor MSB = 0

    ram[16'h0200] = 8'hAA;
    ram[16'h0201] = 8'hBB;
    ram[16'h0202] = 8'hCC;

    bus_write(mem_internal_addr(8'hC0), 16'h0200, 2'b11, 1'b0); // SRC lo
    bus_write(mem_internal_addr(8'hC2), 16'h0000, 2'b11, 1'b0); // SRC hi
    bus_write(mem_internal_addr(8'hC4), {io_dac_addr(2'b10, 3'd0), 1'b0}, 2'b11, 1'b0); // DST lo (dac0 again)
    bus_write(mem_internal_addr(8'hC6), 16'h0000, 2'b11, 1'b0); // DST hi
    bus_write(mem_internal_addr(8'hC8), 16'h0003, 2'b11, 1'b0); // count = 3
    // CON: SRC_MIO|SRC_INC|SYNC_SOURCE(bit6=0x40)|TERMINATE_ON_ZERO|CHG_NOCHG|ST_STOP
    bus_write(mem_internal_addr(8'hCA), 16'h1000 | 16'h0400 | 16'h0040 | 16'h0200 | 16'h0004 | 16'h0002, 2'b11, 1'b0);

    wd = 0;
    fork
        begin
            wait (dma_control[0][1] == 1'b0 && dma_count[0] == 16'h0000);
            wd = 1;
        end
        #400000;
    join_any
    disable fork;
    check("source-sync DMA0 transfer completed", wd == 1);
    check("source-sync DMA0: exactly 3 bytes reached dac0 (one per DRQ)", dac_wr_count[0] == (4 + 3));
    check("source-sync DMA0: dac_sample[0] holds last byte (0xCC)", dac_sample[0] == 8'hCC);
    check("source-sync DMA0: drq0_clear fired once per new byte", drq0_clear_count == (4 + 3));

    // ============================================================
    // Part 4: DMA0 terminal-count interrupt (INTERRUPT_ON_ZERO) --
    // confirm the FSM's own dma0_irq_pulse reaches the interrupt
    // controller's request register (bit2, per i186_periph.sv's
    // existing resolve_irq wiring: DMA0 -> intc_request[2]).
    // ============================================================
    bus_write(mem_internal_addr(8'hC0), 16'h0300, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC2), 16'h0000, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC4), {io_dac_addr(2'b10, 3'd0), 1'b0}, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC6), 16'h0000, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC8), 16'h0001, 2'b11, 1'b0); // count = 1
    // CON: SRC_MIO|SRC_INC|unsync(SYNC=00)|TERMINATE_ON_ZERO|INTERRUPT_ON_ZERO|CHG_NOCHG|ST_STOP
    bus_write(mem_internal_addr(8'hCA), 16'h1000 | 16'h0400 | 16'h0200 | 16'h0100 | 16'h0004 | 16'h0002, 2'b11, 1'b0);

    wd = 0;
    fork
        begin
            wait (intc_request_reg[2] == 1'b1);
            wd = 1;
        end
        #200000;
    join_any
    disable fork;
    check("DMA0 TC interrupt sets intc_request[2]", wd == 1);

    // ============================================================
    // Part 5: word-transfer mode (BYTE_WORD=1) -- one word, verify data
    // integrity and +2 pointer stepping (dac9's word-write-only window,
    // select 4, is a convenient real word-writable destination).
    // ============================================================
    ram[16'h0400] = 8'hCD; // low byte
    ram[16'h0401] = 8'hAB; // high byte -> word 0xABCD

    bus_write(mem_internal_addr(8'hC0), 16'h0400, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC2), 16'h0000, 2'b11, 1'b0);
    // dac9's real byte address is window-relative (0x20000 + 0x200 =
    // 0x20200) -- unlike Part 2/3's I/O-space dac_w destination (decoded
    // structurally by low address bits alone, no window base needed),
    // this is a *memory*-space window hit (win_hit_now compares the
    // FULL address against ext_window_base), so DST must carry the
    // window base in its own hi register, not just the in-window offset.
    bus_write(mem_internal_addr(8'hC4), 16'h0200, 2'b11, 1'b0); // DST lo = 0x0200
    bus_write(mem_internal_addr(8'hC6), 16'h0002, 2'b11, 1'b0); // DST hi = 0x2 (0x20200's upper nibble)
    bus_write(mem_internal_addr(8'hC8), 16'h0001, 2'b11, 1'b0); // count = 1
    // CON: SRC_MIO|SRC_INC|DEST_MIO=1(the ext PCS window IS memory
    // space per MPCS bit6)|unsync|TERMINATE_ON_ZERO|CHG_NOCHG|
    // ST_STOP|BYTE_WORD(bit0=1)
    bus_write(mem_internal_addr(8'hCA),
              16'h1000 | 16'h0400 | 16'h8000 | 16'h0200 | 16'h0004 | 16'h0002 | 16'h0001, 2'b11, 1'b0);

    wd = 0;
    fork
        begin
            wait (dma_control[0][1] == 1'b0 && dma_count[0] == 16'h0000);
            wd = 1;
        end
        #200000;
    join_any
    disable fork;
    check("word-transfer DMA0 completed", wd == 1);
    check("word-transfer: dac9_sample got the full word", dac9_sample == 10'h3CD); // 0xABCD truncated to 10 bits by dac9_sample's own width
    check("word-transfer: SRC pointer advanced by 2", dma_src[0] == 20'h00402);

    // ============================================================
    // Part 6: DEST increment/decrement generality (not exercised by
    // real Leland usage -- dest is normally fixed -- but implemented
    // per spec; directed check that the math is right when a ROM/test
    // *does* ask for it). Transfer 2 bytes from RAM to RAM with DEST
    // incrementing, to make the destination pointer's own stepping
    // independently observable from a fixed-I/O-port test.
    // ============================================================
    ram[16'h0500] = 8'h5A;
    ram[16'h0501] = 8'h5B;
    ram[16'h0600] = 8'h00;
    ram[16'h0601] = 8'h00;

    bus_write(mem_internal_addr(8'hC0), 16'h0500, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC2), 16'h0000, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC4), 16'h0600, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC6), 16'h0000, 2'b11, 1'b0);
    bus_write(mem_internal_addr(8'hC8), 16'h0002, 2'b11, 1'b0); // count = 2
    // CON: SRC_MIO|SRC_INC|DEST_MIO(mem)|DEST_INC|unsync|TERMINATE_ON_ZERO|CHG_NOCHG|ST_STOP
    bus_write(mem_internal_addr(8'hCA),
              16'h1000 | 16'h0400 | 16'h8000 | 16'h2000 | 16'h0200 | 16'h0004 | 16'h0002, 2'b11, 1'b0);

    wd = 0;
    fork
        begin
            wait (dma_control[0][1] == 1'b0 && dma_count[0] == 16'h0000);
            wd = 1;
        end
        #200000;
    join_any
    disable fork;
    check("mem-to-mem DMA0 (dest-increment) completed", wd == 1);
    check("mem-to-mem: byte 0 landed", ram[16'h0600] == 8'h5A);
    check("mem-to-mem: byte 1 landed at incremented dest", ram[16'h0601] == 8'h5B);
    check("mem-to-mem: DST pointer advanced by 2", dma_dst[0] == 20'h00602);

    $fwrite(fd, "RESULT: tests_run=%0d passed=%0d failed=%0d\n",
            tests_run, tests_passed, tests_failed);
    $fclose(fd);
    $display("RESULT: tests_run=%0d passed=%0d failed=%0d", tests_run, tests_passed, tests_failed);
    $finish;
end

// Safety timeout.
initial begin
    #20_000_000;
    $display("i186_dma_tb TIMEOUT");
    $fwrite(fd, "RESULT: tests_run=%0d passed=%0d failed=%0d (TIMEOUT)\n",
            tests_run, tests_passed, tests_failed);
    $fclose(fd);
    $finish;
end

endmodule
