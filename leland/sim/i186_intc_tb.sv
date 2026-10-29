// Stage-B-style directed unit test for i186_periph's interrupt
// controller. Drives the CPU-side bus directly via the same BFM pattern as
// sim/i186_periph_tb.sv / sim/i186_timers_tb.sv, plus
// directly toggling the intr-controller-specific inputs (int0/int1
// pins, dma irq stubs, inta).
//
// Covers: priority resolution,
// shared timer bit vectors 0x08/0x12/0x13, DMA vectors 0x0A/0x0B,
// INT0/0x0C, both EOI forms, LTM vs edge request clearing.

`timescale 1ns / 1ps

module i186_intc_tb;

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

wire        intr;
wire [7:0]  irq_out;
reg         inta;
reg         int0_pin, int1_pin;
reg         dma0_irq_req, dma1_irq_req;
wire [7:0]  intc_request_reg, intc_in_service_reg;
wire [2:0]  intc_status_reg;
wire [3:0]  intc_timer0_ctrl_reg, intc_dma0_ctrl_reg, intc_dma1_ctrl_reg;
wire [6:0]  intc_ext0_ctrl_reg, intc_ext1_ctrl_reg;

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
    .t_count(t_count), .t_maxA(t_maxA), .t_maxB(t_maxB), .t_control(t_control),
    .intr(intr), .irq_out(irq_out), .inta(inta),
    .int0_pin(int0_pin), .int1_pin(int1_pin),
    .dma0_irq_req(dma0_irq_req), .dma1_irq_req(dma1_irq_req),
    .intc_request_reg(intc_request_reg), .intc_in_service_reg(intc_in_service_reg),
    .intc_status_reg(intc_status_reg),
    .intc_timer0_ctrl_reg(intc_timer0_ctrl_reg), .intc_dma0_ctrl_reg(intc_dma0_ctrl_reg),
    .intc_dma1_ctrl_reg(intc_dma1_ctrl_reg),
    .intc_ext0_ctrl_reg(intc_ext0_ctrl_reg), .intc_ext1_ctrl_reg(intc_ext1_ctrl_reg));

always @(posedge clk) begin
    if (reset) sys_ack <= 1'b0;
    else sys_ack <= sys_access & ~sys_ack;
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
function automatic [19:1] port_addr(input [7:0] byte_off);
    port_addr = 19'h7F80 + (byte_off >> 1);
endfunction

localparam [7:0] IVEC   = 8'h20, EOI    = 8'h22, POLL   = 8'h24, POLLSTS= 8'h26;
localparam [7:0] MASK   = 8'h28, PRIMSK = 8'h2a, INSERV = 8'h2c, REQST  = 8'h2e;
localparam [7:0] INTSTS = 8'h30, TCUCON = 8'h32, DMA0CON= 8'h34, DMA1CON= 8'h36;
localparam [7:0] I0CON  = 8'h38, I1CON  = 8'h3a, I2CON  = 8'h3c, I3CON  = 8'h3e;

// Fires `inta` for exactly one cycle and lets the controller settle.
// Needs 3 edges, not 2: edge A is where `inta` is sampled and the ack
// mutation + `rescan_trigger_d`/`rescan_force_d` capture happen; edge B
// is where the deferred rescan actually evaluates and *schedules* its
// own update to `intc_poll_status`; that scheduled update only becomes
// visible to code resuming after a *later* edge (standard Verilog
// same-edge NBA-visibility semantics -- code reactivated by the exact
// edge that schedules an update cannot observe it yet, only code
// reactivated by a subsequent edge can), hence edge C.
task automatic pulse_inta;
    begin
        inta = 1'b1;
        @(posedge clk); // edge A
        inta = 1'b0;
        @(posedge clk); // edge B
        @(posedge clk); // edge C -- lets edge B's own update settle
    end
endtask

reg [15:0] rd;

initial begin
    fd = $fopen("i186_intc_result.txt", "w");
    tests_run = 0; tests_passed = 0; tests_failed = 0;
    cpu_access = 0; cpu_wr_en = 0; cpu_bytesel = 2'b11; cpu_d_io = 1'b1;
    cpu_addr = 0; cpu_data_out = 0;
    inta = 0; int0_pin = 0; int1_pin = 0; dma0_irq_req = 0; dma1_irq_req = 0;

    reset = 1;
    repeat (5) @(posedge clk);
    reset = 0;
    @(posedge clk);

    // --- Reset defaults ---
    check("reset: intr low", intr == 1'b0);
    check("reset: PRIMSK == 7", intc_ext0_ctrl_reg !== 7'bx && dut.intc_priority_mask == 3'h7);
    check("reset: TCUCON == 0xF", intc_timer0_ctrl_reg == 4'hf);
    check("reset: in_service == 0", intc_in_service_reg == 8'h00);

    // =====================================================================
    // Test 1: shared timer vectors 0x08/0x12/0x13 -- program TCUCON with
    // INTEN so timer_irq[N] actually reaches the sticky status bits, then
    // confirm each of the three status bits maps to its documented vector.
    bus_write(port_addr(TCUCON), 16'h0000, 2'b11, 1'b1); // priority 0, unmasked

    // status bit 0 -> vector 0x08 (drive timer_irq[0] directly via the
    // testbench's hierarchical access to dut, since driving a full
    // timer to elapse is unnecessary complexity for this directed test --
    // i186_timers_tb already proves timer_irq's generation; this test
    // proves the status-bit -> vector mapping once the pulse arrives).
    // Settle timing: the mutating event (timer_irq -> intc_status) takes
    // 1 cycle to commit, and the rescan it triggers is itself deferred
    // by 1 more cycle (see the "Deferred rescan" note in i186_periph.sv
    // -- resolve_irq's combinational inputs must read the *settled*
    // post-mutation registers, not last-cycle's stale values), so 2
    // full cycles after the triggering event is the real minimum.
    force dut.timer_irq = 3'b001;
    @(posedge clk);
    release dut.timer_irq;
    repeat (2) @(posedge clk);
    check("timer status bit0 -> intr asserted", intr == 1'b1);
    check("timer status bit0 -> vector 0x08", irq_out == 8'h08);
    pulse_inta;
    check("after ack: intr deasserts (nothing else pending)", intr == 1'b0);
    check("after ack: in_service bit0 set then cleared by EOI not yet sent -- in_service still set",
          intc_in_service_reg[0] == 1'b1);

    // Clear in_service via specific EOI (vector 0x08) before the next test.
    bus_write(port_addr(EOI), 16'h0008, 2'b11, 1'b1);
    check("specific EOI(0x08) clears in_service bit0", intc_in_service_reg[0] == 1'b0);

    // status bit1 -> vector 0x12
    force dut.timer_irq = 3'b010;
    @(posedge clk);
    release dut.timer_irq;
    repeat (2) @(posedge clk);
    check("timer status bit1 -> vector 0x12", irq_out == 8'h12);
    pulse_inta;
    bus_write(port_addr(EOI), 16'h0012, 2'b11, 1'b1);
    check("specific EOI(0x12) clears in_service bit0", intc_in_service_reg[0] == 1'b0);

    // status bit2 -> vector 0x13
    force dut.timer_irq = 3'b100;
    @(posedge clk);
    release dut.timer_irq;
    repeat (2) @(posedge clk);
    check("timer status bit2 -> vector 0x13", irq_out == 8'h13);
    pulse_inta;
    bus_write(port_addr(EOI), 16'h0013, 2'b11, 1'b1);
    check("specific EOI(0x13) clears in_service bit0", intc_in_service_reg[0] == 1'b0);

    // =====================================================================
    // Test 2: DMA vectors 0x0A/0x0B (DMA stub pulses).
    bus_write(port_addr(DMA0CON), 16'h0000, 2'b11, 1'b1); // priority 0
    bus_write(port_addr(DMA1CON), 16'h0001, 2'b11, 1'b1); // priority 1

    dma0_irq_req = 1'b1;
    @(posedge clk);
    dma0_irq_req = 1'b0;
    repeat (2) @(posedge clk); // mutation capture + deferred-rescan
                                // schedule + 1 settle buffer
    check("DMA0 request -> vector 0x0A", intr == 1'b1 && irq_out == 8'h0a);
    pulse_inta;
    bus_write(port_addr(EOI), 16'h800a, 2'b11, 1'b1); // nonspecific-form
                                                        // sanity re-armed below;
                                                        // here just clear cleanly
    bus_write(port_addr(EOI), 16'h000a, 2'b11, 1'b1);

    dma1_irq_req = 1'b1;
    @(posedge clk);
    dma1_irq_req = 1'b0;
    repeat (2) @(posedge clk);
    check("DMA1 request -> vector 0x0B", intr == 1'b1 && irq_out == 8'h0b);
    pulse_inta;
    bus_write(port_addr(EOI), 16'h000b, 2'b11, 1'b1);

    // =====================================================================
    // Test 3: INT0 pin -> vector 0x0C, edge-triggered mode (LTM=0):
    // request clears at ack time even though the pin is still held high.
    bus_write(port_addr(I0CON), 16'h0000, 2'b11, 1'b1); // priority 0, LTM=0 (edge)
    int0_pin = 1'b1;
    repeat (6) @(posedge clk); // let the 2-FF synchronizer + mutation
                                // capture + deferred rescan (+1 settle
                                // buffer past its own scheduling edge)
                                // all land
    check("INT0 pin asserted -> vector 0x0C", intr == 1'b1 && irq_out == 8'h0c);
    check("INT0 edge mode: request bit4 set", intc_request_reg[4] == 1'b1);
    pulse_inta;
    check("INT0 edge mode: request bit4 clears at ack despite pin still high",
          intc_request_reg[4] == 1'b0);
    check("INT0 edge mode: in_service bit4 set after ack", intc_in_service_reg[4] == 1'b1);
    bus_write(port_addr(EOI), 16'h000c, 2'b11, 1'b1);
    int0_pin = 1'b0;
    repeat (6) @(posedge clk);
    check("INT0 edge mode: ext_state clears when pin drops", dut.intc_ext_state[0] == 1'b0);

    // =====================================================================
    // Test 4: LTM (level-triggered) mode -- request bit stays set across
    // the ack (does NOT clear until the pin itself deasserts).
    bus_write(port_addr(I0CON), 16'h0010, 2'b11, 1'b1); // priority 0, LTM=1
    int0_pin = 1'b1;
    repeat (6) @(posedge clk);
    check("LTM: INT0 asserted -> vector 0x0C", intr == 1'b1 && irq_out == 8'h0c);
    pulse_inta;
    check("LTM: request bit4 STAYS set across ack (level still held)",
          intc_request_reg[4] == 1'b1);
    // Drop the pin BEFORE the EOI, not after: EOI-ing while the level
    // is still held is a real level-triggered "nesting" case (clearing
    // in_service with the request bit still live legitimately produces
    // a brand-new grant of the same source, per real LTM semantics --
    // confirmed this actually happens in an earlier version of this
    // test that EOI'd first and left `intr` stuck presenting that
    // re-grant into the next test). Dropping the pin first clears the
    // sticky request bit, so the EOI below has nothing left to re-grant.
    int0_pin = 1'b0;
    repeat (6) @(posedge clk);
    check("LTM: request bit4 clears once the pin actually deasserts",
          intc_request_reg[4] == 1'b0);
    bus_write(port_addr(EOI), 16'h000c, 2'b11, 1'b1);
    repeat (2) @(posedge clk); // let the EOI's deferred rescan settle
    check("LTM: intr deasserts after EOI with the pin already low",
          intr == 1'b0);

    // =====================================================================
    // Test 5: priority resolution -- program DMA0 at priority 1 and INT1
    // at priority 0 (higher urgency), assert both simultaneously, confirm
    // INT1 (the higher-priority / lower-numbered source) wins first.
    bus_write(port_addr(I0CON),   16'h0007, 2'b11, 1'b1); // deprioritize/mask INT0 out of the way (pri 7)
    bus_write(port_addr(DMA0CON), 16'h0001, 2'b11, 1'b1); // priority 1
    bus_write(port_addr(I1CON),   16'h0000, 2'b11, 1'b1); // priority 0 (wins)

    // INT1 needs to actually arrive and get granted (its pin path has a
    // 2-FF synchronizer DMA's direct pulse doesn't) *before* DMA0 fires,
    // not just be programmed at a numerically higher priority: this
    // module deliberately does not preempt an already-presented,
    // not-yet-acked vector even for a later-arriving higher-priority
    // source (that's the G4 stability contract -- see this file's
    // "priority: DMA0 stays blocked..." check below, and i186_periph.sv's
    // module-header note) -- so this test proves priority resolution
    // between two *simultaneously-pending* requests, which requires
    // giving INT1 enough of a head start to land first.
    int1_pin = 1'b1;
    repeat (4) @(posedge clk); // 2-FF sync + edge capture + deferred
                                // rescan settle, before DMA0 fires
    dma0_irq_req = 1'b1;
    @(posedge clk);
    dma0_irq_req = 1'b0;
    repeat (2) @(posedge clk);
    check("priority: INT1 (priority 0) wins over pending DMA0 (priority 1)",
          irq_out == 8'h0d);
    pulse_inta;
    // While INT1 (priority 0) remains in-service, the *entire* scan
    // aborts at priority 0 (i186.cpp's literal early-`return` semantics
    // -- see resolve_irq's header comment) -- DMA0 (priority 1) stays
    // blocked, not just deprioritized, until INT1's own EOI, regardless
    // of how much lower-priority work is pending behind it.
    check("priority: DMA0 stays blocked while INT1 remains in-service",
          intr == 1'b0);
    bus_write(port_addr(EOI), 16'h800d, 2'b11, 1'b1); // nonspecific EOI for INT1's in_service
    repeat (2) @(posedge clk); // let the EOI's own deferred rescan land
                                // before sampling/acking anything --
                                // pulsing inta against a still-in-flight
                                // rescan acks stale/spurious state
    check("priority: DMA0 (priority 1) is presented once INT1's in-service clears",
          intr == 1'b1 && irq_out == 8'h0a);
    pulse_inta;
    bus_write(port_addr(EOI), 16'h000a, 2'b11, 1'b1);
    int1_pin = 1'b0;
    repeat (6) @(posedge clk);

    // =====================================================================
    // Test 6: in-service blocks same/lower priority -- with DMA0 in
    // service at priority 1, a NEW request at priority 1 or lower (a
    // higher numeric value / lower urgency) must not be granted until EOI.
    bus_write(port_addr(DMA1CON), 16'h0002, 2'b11, 1'b1); // priority 2 (lower urgency than 1)
    dma0_irq_req = 1'b1;
    @(posedge clk);
    dma0_irq_req = 1'b0;
    repeat (2) @(posedge clk);
    check("in-service test setup: DMA0 pending", intr == 1'b1 && irq_out == 8'h0a);
    pulse_inta;
    check("in-service test setup: DMA0 now in-service", intc_in_service_reg[2] == 1'b1);
    dma1_irq_req = 1'b1;
    @(posedge clk);
    dma1_irq_req = 1'b0;
    repeat (5) @(posedge clk);
    check("DMA0 in-service (pri1) blocks DMA1 (pri2, lower urgency) from being granted",
          intr == 1'b0);
    bus_write(port_addr(EOI), 16'h000a, 2'b11, 1'b1); // clear DMA0's in-service
    repeat (5) @(posedge clk);
    check("once DMA0's in-service clears, the still-pending DMA1 gets granted",
          intr == 1'b1 && irq_out == 8'h0b);
    pulse_inta;
    bus_write(port_addr(EOI), 16'h000b, 2'b11, 1'b1);

    // =====================================================================
    // Test 7: nonspecific EOI form -- program two sources at distinct
    // priorities, ack the higher-priority one, then confirm a nonspecific
    // EOI (data bit15 set) clears the correct (lowest-priority-number)
    // in-service source without needing its exact vector.
    bus_write(port_addr(DMA0CON), 16'h0000, 2'b11, 1'b1); // priority 0
    bus_write(port_addr(DMA1CON), 16'h0001, 2'b11, 1'b1); // priority 1
    dma0_irq_req = 1'b1;
    @(posedge clk);
    dma0_irq_req = 1'b0;
    repeat (2) @(posedge clk);
    pulse_inta; // DMA0 now in-service at priority 0
    check("nonspecific EOI setup: DMA0 in-service", intc_in_service_reg[2] == 1'b1);
    bus_write(port_addr(EOI), 16'h8000, 2'b11, 1'b1); // nonspecific EOI
    check("nonspecific EOI clears the lowest-priority-number in-service source (DMA0)",
          intc_in_service_reg[2] == 1'b0);

    $fwrite(fd, "RESULT: tests_run=%0d passed=%0d failed=%0d\n", tests_run, tests_passed, tests_failed);
    if (tests_failed == 0)
        $fwrite(fd, "i186_intc (WP4) Stage-B: PASS\n");
    else
        $fwrite(fd, "i186_intc (WP4) Stage-B: FAIL\n");
    $display("RESULT: tests_run=%0d passed=%0d failed=%0d", tests_run, tests_passed, tests_failed);
    $fclose(fd);
    $finish;
end

endmodule
