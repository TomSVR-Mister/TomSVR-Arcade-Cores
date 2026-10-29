// Stage-B-style directed unit test for i186_periph.
// Drives i186_periph's CPU-side bus directly via a small BFM (bus
// functional model) rather than routing through real x86 code -- this
// module is a pure bus responder, and directed register-level tests are
// a closer match to "Stage B: internal-register + CSU conformance...
// directed unit tests per register" than adding real-CPU/instruction-
// encoding complexity would buy.

`timescale 1ns / 1ps

module i186_periph_tb;

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
    .pacs_reg(pacs_reg), .mmcs_reg(mmcs_reg), .mpcs_reg(mpcs_reg));

// Trivial sys-side stub: single-cycle ack, echoes address as data (so
// pass-through tests can confirm the request reached the far side
// unmodified without needing a real memory array).
always @(posedge clk) begin
    if (reset) begin
        sys_ack <= 1'b0;
    end else begin
        sys_ack <= sys_access & ~sys_ack;
        if (sys_access & ~sys_ack)
            sys_data_in <= {sys_addr[15:1], 1'b0} ^ 16'hBEEF;
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

// word_addr is the [19:1] bus value (== byte address with bit0
// implicitly 0, per this bus's addressing convention).
// Both tasks force one full idle cycle (access held low) before
// asserting a new access, rather than trusting the previous
// call's cleanup alone: `cpu_access` toggling 1->0->1 across
// back-to-back task calls with no intervening `@(posedge clk)` in
// between (e.g. right after a `check(...)` call, which has no timing
// control) means the DUT's ack-clear logic -- which only re-evaluates
// at clock edges -- can genuinely never observe the low period, so its
// registered ack output stays stuck high from the previous transaction
// and the very next wait-for-ack loop exits instantly on a stale
// value. Confirmed empirically (added entry-point debug prints
// showing `cpu_ack` already 1, `timeout=0`, before this fix).
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

reg [15:0] rd;

initial begin
    fd = $fopen("i186_periph_result.txt", "w");
    tests_run = 0; tests_passed = 0; tests_failed = 0;
    cpu_access = 0; cpu_wr_en = 0; cpu_bytesel = 2'b11; cpu_d_io = 0;
    cpu_addr = 0; cpu_data_out = 0;

    reset = 1;
    repeat (5) @(posedge clk);
    reset = 0;
    @(posedge clk);

    // --- Reset defaults ---
    check("reset: reloc == 0x20FF", reloc_reg == 16'h20FF);
    check("reset: umcs == 0", umcs_reg == 16'h0000);
    check("reset: ext_window_valid == 0", ext_window_valid == 1'b0);

    // --- I/O-mode access (default reloc, page 0xFF -> port base 0xFF00) ---
    // UMCS is at page-byte-offset 0xA0 -> port 0xFFA0 -> word_addr = 0xFFA0>>1 = 0x7FD0.
    bus_write(19'h7FD0, 16'h1234, 2'b11, 1'b1);
    check("I/O-mode UMCS write applies forced bits", umcs_reg == (16'h1234 | 16'hC038));
    bus_read(19'h7FD0, 2'b11, 1'b1, rd);
    check("I/O-mode UMCS readback matches", rd == umcs_reg);

    // Access to the SAME port address but with d_io=0 (memory cycle)
    // must NOT hit the internal page while still in I/O mode -- should
    // pass through to the sys stub instead.
    bus_read(19'h7FD0, 2'b11, 1'b0, rd);
    check("I/O-mode: memory-space access to same address passes through",
          rd == (16'hFFA0 ^ 16'hBEEF));

    // --- Switch to memory mode: write RELOC (port 0xFFFE -> word_addr
    // 0xFFFE>>1 = 0x7FFF) to the MAME-observed value 0x9203.
    bus_write(19'h7FFF, 16'h9203, 2'b11, 1'b1);
    check("RELOC write in I/O mode succeeds", reloc_reg == 16'h9203);

    // --- Now in memory mode: page base = (0x9203 & 0xFFF) << 8 = 0x20300.
    // PACS at page-byte-offset 0xA4 -> physical 0x203A4 -> word_addr
    // 0x203A4 >> 1 = 0x101D2.
    bus_write(19'h101D2, 16'h203C, 2'b11, 1'b0);
    check("memory-mode PACS write (WP0 observed value)",
          pacs_reg == (16'h203C | 16'h0038));

    // Same physical address but d_io=1 must NOT hit now (we're in
    // memory mode) -- passes through instead.
    bus_read(19'h101D2, 2'b11, 1'b1, rd);
    check("memory-mode: I/O-space access to same address passes through",
          rd == (16'h03A4 ^ 16'hBEEF));

    // MMCS at offset 0xA6 -> physical 0x203A6 -> word_addr 0x101D3.
    bus_write(19'h101D3, 16'h01FC, 2'b11, 1'b0);
    check("memory-mode MMCS write (WP0 observed value)",
          mmcs_reg == (16'h01FC | 16'h01F8));

    check("ext_window_valid still 0 before MPCS written", ext_window_valid == 1'b0);

    // MPCS at offset 0xA8 -> physical 0x203A8 -> word_addr 0x101D4.
    bus_write(19'h101D4, 16'hC0FC, 2'b11, 0);
    check("memory-mode MPCS write (WP0 observed value)",
          mpcs_reg == (16'hC0FC | 16'h8038));

    // --- Central finding: external PCS window ends up at
    // physical 0x20000, memory-mapped (MPCS bit6=1).
    check("ext_window_base == 0x20000 (WP0 observed)", ext_window_base == 20'h20000);
    check("ext_window_is_mem == 1 (WP0 observed, MPCS bit6)", ext_window_is_mem == 1'b1);
    check("ext_window_valid == 1 after MPCS write", ext_window_valid == 1'b1);

    // --- Byte-swap quirk: PACS currently 0x203C|0x38=0x203C. Write a
    // byte to the HIGH half only (word_addr same, bytesel=10) and
    // confirm only the high byte changes, low byte preserved.
    bus_write(19'h101D2, 16'h00AB, 2'b10, 1'b0);
    check("byte-swap: high-byte write preserves low byte",
          pacs_reg[7:0] == 8'h3C && pacs_reg[15:8] == 8'hAB);

    // Write the LOW half only and confirm the (now-changed) high byte
    // from the previous step is preserved. Uses 0xFF (not e.g. 0xCD)
    // so it trivially satisfies PACS's forced-OR-0x0038 mask -- this
    // test is about byte-swap preservation, not re-deriving the
    // forced-bits behavior already covered by the "memory-mode PACS
    // write" case above (0xCD | 0x0038 = 0xFD, not 0xCD -- a real trap
    // for this test's *expected value*, not a DUT bug, caught here).
    bus_write(19'h101D2, 16'h00FF, 2'b01, 1'b0);
    check("byte-swap: low-byte write preserves high byte",
          pacs_reg[15:8] == 8'hAB && pacs_reg[7:0] == 8'hFF);

    $fwrite(fd, "RESULT: tests_run=%0d passed=%0d failed=%0d\n", tests_run, tests_passed, tests_failed);
    if (tests_failed == 0)
        $fwrite(fd, "i186_periph Stage-B: PASS\n");
    else
        $fwrite(fd, "i186_periph Stage-B: FAIL\n");
    $display("RESULT: tests_run=%0d passed=%0d failed=%0d", tests_run, tests_passed, tests_failed);
    $fclose(fd);
    $finish;
end

endmodule
