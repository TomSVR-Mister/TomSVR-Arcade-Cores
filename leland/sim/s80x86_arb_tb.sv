// Seam-gate bench for G2/G3/G5:
// Core.sv -> MemArbiter (combines the CPU's own instr+data ports,
// exactly MemArbiter's intended use per its "data port has priority
// over prefetch" comment) -> a SECOND MemArbiter combining that CPU
// side against a bench-only fake-DMA master (DMA given priority; the
// CPU simply sees delayed ack) -> the same flat RAM/ROM memory model used in
// sim/s80x86_stage_a_tb.sv.
//
// This is a separate file from s80x86_stage_a_tb.sv (Stage A itself
// doesn't need arbitration -- no second bus master exists yet there)
// rather than folding the arbiters into that bench unconditionally.

`timescale 1ns / 1ps

module s80x86_arb_tb;

localparam CLK_PERIOD = 20;

reg clk = 0;
reg reset = 1;
always #(CLK_PERIOD/2) clk = ~clk;

initial begin
    reset = 1;
    repeat (10) @(posedge clk);
    reset = 0;
end

wire nmi = 1'b0;
wire intr = 1'b0;
wire [7:0] irq = 8'h0;
wire inta;

// CPU-side instruction and data ports (pre-arbiter).
wire [19:1] instr_m_addr;
wire [15:0] instr_m_data_in;
wire        instr_m_access;
wire        instr_m_ack;
wire [19:1] data_m_addr;
wire [15:0] data_m_data_in;
wire [15:0] data_m_data_out;
wire        data_m_access;
wire        data_m_ack;
wire        data_m_wr_en;
wire [1:0]  data_m_bytesel;
wire        d_io;
wire        lock;

wire        debug_stopped;
wire [15:0] debug_val;

Core dut(.clk(clk), .reset(reset), .nmi(nmi), .intr(intr), .irq(irq), .inta(inta),
         .instr_m_addr(instr_m_addr), .instr_m_data_in(instr_m_data_in),
         .instr_m_access(instr_m_access), .instr_m_ack(instr_m_ack),
         .data_m_addr(data_m_addr), .data_m_data_in(data_m_data_in),
         .data_m_data_out(data_m_data_out), .data_m_access(data_m_access),
         .data_m_ack(data_m_ack), .data_m_wr_en(data_m_wr_en),
         .data_m_bytesel(data_m_bytesel), .d_io(d_io), .lock(lock),
         .debug_stopped(debug_stopped), .debug_seize(1'b0), .debug_addr(8'h0),
         .debug_run(1'b0), .debug_val(debug_val), .debug_wr_val(16'h0), .debug_wr_en(1'b0));

// --- Arbiter 1: combine the CPU's own instr (a, lower priority) and
// data (b, higher priority) ports into one, per MemArbiter's own
// intended usage (see rtl/s80x86/MemArbiter.sv: data port has
// priority over prefetch, grant_to_b <= b_m_access).
wire [19:1] cpu_q_addr;
wire [15:0] cpu_q_data_in;
wire [15:0] cpu_q_data_out;
wire        cpu_q_access;
wire        cpu_q_ack;
wire        cpu_q_wr_en;
wire [1:0]  cpu_q_bytesel;
wire        cpu_q_b; // 1 = granted to data port, 0 = instruction port

MemArbiter arb1(.clk(clk), .reset(reset),
                 .a_m_addr(instr_m_addr), .a_m_data_in(instr_m_data_in),
                 .a_m_data_out(16'h0), .a_m_access(instr_m_access), .a_m_ack(instr_m_ack),
                 .a_m_wr_en(1'b0), .a_m_bytesel(2'b11),
                 .b_m_addr(data_m_addr), .b_m_data_in(data_m_data_in),
                 .b_m_data_out(data_m_data_out), .b_m_access(data_m_access), .b_m_ack(data_m_ack),
                 .b_m_wr_en(data_m_wr_en), .b_m_bytesel(data_m_bytesel),
                 .q_m_addr(cpu_q_addr), .q_m_data_in(cpu_q_data_in), .q_m_data_out(cpu_q_data_out),
                 .q_m_access(cpu_q_access), .q_m_ack(cpu_q_ack), .q_m_wr_en(cpu_q_wr_en),
                 .q_m_bytesel(cpu_q_bytesel), .q_b(cpu_q_b));

// --- Fake DMA master (bench-driven, G2/G3/G5 stimulus) ---
reg [19:1] fake_dma_addr;
reg        fake_dma_access;
reg        fake_dma_wr_en;
reg [1:0]  fake_dma_bytesel;
wire [15:0] fake_dma_data_in;
wire        fake_dma_ack;

// --- Arbiter 2: CPU combined (a, lower priority) vs fake DMA (b,
// higher priority) -> system bus that the memory model actually serves.
wire [19:1] sys_addr;
wire [15:0] sys_data_in;
wire [15:0] sys_data_out;
wire        sys_access;
reg         sys_ack;
wire        sys_wr_en;
wire [1:0]  sys_bytesel;
wire        sys_q_b; // 1 = granted to fake DMA, 0 = granted to CPU

MemArbiter arb2(.clk(clk), .reset(reset),
                 .a_m_addr(cpu_q_addr), .a_m_data_in(cpu_q_data_in),
                 .a_m_data_out(cpu_q_data_out), .a_m_access(cpu_q_access), .a_m_ack(cpu_q_ack),
                 .a_m_wr_en(cpu_q_wr_en), .a_m_bytesel(cpu_q_bytesel),
                 .b_m_addr(fake_dma_addr), .b_m_data_in(fake_dma_data_in),
                 .b_m_data_out(16'h0), .b_m_access(fake_dma_access), .b_m_ack(fake_dma_ack),
                 .b_m_wr_en(fake_dma_wr_en), .b_m_bytesel(fake_dma_bytesel),
                 .q_m_addr(sys_addr), .q_m_data_in(sys_data_in), .q_m_data_out(sys_data_out),
                 .q_m_access(sys_access), .q_m_ack(sys_ack), .q_m_wr_en(sys_wr_en),
                 .q_m_bytesel(sys_bytesel), .q_b(sys_q_b));

// --- Memory model (same address map/content as s80x86_stage_a_tb.sv,
// single-cycle ack -- G2 doesn't need randomized timing, just a
// forced-alignment preemption scenario).
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

reg [15:0] sys_data_in_r;
assign sys_data_in = sys_data_in_r;

// Fixed multi-cycle ack delay (not single-cycle, unlike Stage A/G1's
// memory model): G2's fake-DMA request is triggered off the shared bus
// itself (sys_access && !sys_q_b), which only becomes visible to the
// stimulus process one clock edge after the condition is first true
// (ordinary NBA cross-process delay), so the "target" transaction needs
// to still be in flight one full cycle later for the intended overlap
// to actually happen -- a single-cycle-ack transaction is already gone
// by then. 6 cycles gives comfortable margin without slowing the bench
// down much.
localparam SYS_ACK_DELAY = 6;
reg [3:0] sys_delay_remaining;
always @(posedge clk) begin
    if (reset) begin
        sys_ack <= 1'b0;
        sys_delay_remaining <= 4'h0;
    end else begin
        if (sys_access & ~sys_ack) begin
            if (sys_delay_remaining == 4'h0) begin
                sys_delay_remaining <= SYS_ACK_DELAY[3:0] - 4'h1;
                sys_ack <= 1'b0;
            end else if (sys_delay_remaining == 4'h1) begin
                sys_ack <= 1'b1;
                sys_delay_remaining <= 4'h0;
                if (d_io && sys_q_b == 1'b0 && cpu_q_b == 1'b1) begin
                    // d_io only reflects the CPU's data port's own I/O
                    // flag; fake-DMA transactions here are always memory
                    // reads, so this only applies when arb2 has granted
                    // the CPU's data port through.
                    sys_data_in_r <= 16'hffff;
                end else begin
                    sys_data_in_r <= {mem_read_byte({sys_addr, 1'b1}),
                                       mem_read_byte({sys_addr, 1'b0})};
                end
                if (sys_wr_en && !(d_io && cpu_q_b)) begin
                    if (sys_bytesel[0])
                        mem_write_byte({sys_addr, 1'b0}, sys_data_out[7:0]);
                    if (sys_bytesel[1])
                        mem_write_byte({sys_addr, 1'b1}, sys_data_out[15:8]);
                end
            end else begin
                sys_delay_remaining <= sys_delay_remaining - 4'h1;
                sys_ack <= 1'b0;
            end
        end else begin
            sys_ack <= 1'b0;
        end
    end
end

// --- G2 stimulus: fire the fake DMA request the first time the shared
// (post-arbiter) bus shows a CPU transaction ALREADY GRANTED and
// holding the grant (sys_access && !sys_q_b) -- triggering off the
// post-arbiter signal itself (rather than trying to time it off the
// CPU's raw pre-arbiter pin, which has arbitration-latency skew
// relative to when the transaction actually appears on the shared bus)
// guarantees the DMA request lands exactly inside a known in-flight,
// already-granted CPU transaction, no timing guesswork. Skip the first
// few transactions (boot-time reset-vector fetches) so this is a
// steady-state occurrence, not a boot artifact. Held until granted+acked.
reg dma_fired;
integer sys_txn_count;
reg sys_access_prev; // hoisted: used below and by the G2 verification block

// --- G3 (bounded grant latency, §5.1): repeat the fake-DMA request
// continuously at randomized alignment relative to CPU bus activity
// (rather than G2's single deliberately-aligned occurrence), measuring
// request-to-first-grant latency each time. +G3_MODE=1 enables this;
// G2's clean single-shot check above still runs regardless (its
// "first occurrence" is unaffected by G3 continuing afterward).
int g3_mode;
int g5_mode; // hoisted: gates the shared stimulus always block below too
longint unsigned g3_assert_cycle, g3_sample_count, g3_max_latency, g3_min_latency, g3_sum_latency;
integer g3_idle_seed;
reg [7:0] g3_idle_remaining;
integer g3_fd;
localparam int G3_TARGET_SAMPLES = 1000;

initial begin
    fake_dma_addr = 19'h04000; // distinct RAM word, well clear of CPU traffic
    fake_dma_access = 1'b0;
    fake_dma_wr_en = 1'b0;
    fake_dma_bytesel = 2'b11;
    sys_txn_count = 0;
    if (!$value$plusargs("G3_MODE=%d", g3_mode))
        g3_mode = 0;
    g3_idle_seed = 99;
    g3_sample_count = 0;
    g3_max_latency = 0;
    g3_min_latency = 64'hFFFF_FFFF_FFFF_FFFF;
    g3_sum_latency = 0;
    g3_fd = $fopen("g3_latency_log.txt", "w");
end

wire sys_access_rise = sys_access && !sys_access_prev;
wire dma_granted_now = sys_access && sys_q_b && sys_access_rise;

// Cycle counter for latency measurement (simulation time / CLK_PERIOD
// would work too, but an explicit counter is clearer to read back).
longint unsigned cycle_num;
always @(posedge clk) begin
    if (reset) cycle_num <= 0;
    else cycle_num <= cycle_num + 1;
end

always @(posedge clk) begin
    if (reset) begin
        dma_fired <= 1'b0;
        fake_dma_access <= 1'b0;
        g3_idle_remaining <= 8'h0;
    end else begin
        if (sys_access_rise)
            sys_txn_count <= sys_txn_count + 1;

        if (dma_granted_now && fake_dma_access) begin
            // This grant is servicing our currently-outstanding request.
            if (g3_mode) begin
                automatic longint unsigned latency = cycle_num - g3_assert_cycle;
                g3_sample_count <= g3_sample_count + 1;
                g3_sum_latency <= g3_sum_latency + latency;
                if (latency > g3_max_latency) g3_max_latency <= latency;
                if (latency < g3_min_latency) g3_min_latency <= latency;
                $fwrite(g3_fd, "sample %0d: latency=%0d cycles\n", g3_sample_count, latency);
            end
        end

        if (!g5_mode && !dma_fired && sys_access && !sys_q_b && sys_txn_count > 20) begin
            fake_dma_access <= 1'b1;
            dma_fired <= 1'b1;
            g3_assert_cycle <= cycle_num;
        end else if (!g5_mode && fake_dma_access && fake_dma_ack) begin
            fake_dma_access <= 1'b0;
            if (g3_mode) begin
                // Re-arm after a small pseudo-random idle gap (0-15
                // cycles) so requests land at varied alignment: idle,
                // mid-instruction-fetch, mid-data-access, back-to-back.
                g3_idle_remaining <= $random(g3_idle_seed) & 8'hF;
                dma_fired <= 1'b0;
            end
        end else if (g5_mode && fake_dma_access && fake_dma_ack) begin
            // G5's own periodic generator (below) owns re-arming; just
            // clear the outstanding flag here so it can detect overrun
            // vs. a freshly-serviced request correctly.
            fake_dma_access <= 1'b0;
        end else if (g3_mode && !dma_fired && !fake_dma_access) begin
            if (g3_idle_remaining == 8'h0) begin
                fake_dma_access <= 1'b1;
                dma_fired <= 1'b1;
                g3_assert_cycle <= cycle_num;
            end else begin
                g3_idle_remaining <= g3_idle_remaining - 8'h1;
            end
        end
    end
end

initial begin
    if (g3_mode) begin
        wait (g3_sample_count >= G3_TARGET_SAMPLES);
        $fwrite(g3_fd, "G3 RESULT: samples=%0d min=%0d max=%0d avg=%0d (SYS_ACK_DELAY=%0d)\n",
                g3_sample_count, g3_min_latency, g3_max_latency,
                g3_sum_latency / g3_sample_count, SYS_ACK_DELAY);
        $display("G3 RESULT: samples=%0d min=%0d max=%0d avg=%0d", g3_sample_count, g3_min_latency, g3_max_latency, g3_sum_latency / g3_sample_count);
        $fclose(g3_fd);
        $finish;
    end
end

// --- G2 verification ---
// (a) the in-flight CPU transaction must complete unmolested: once
// arb2 has granted the CPU side (sys_q_b==0, grant_active), that grant
// must not flip to DMA mid-transaction regardless of fake_dma_access.
// (b) the very next transaction to appear on the shared (sys_*) bus
// after that CPU transaction completes must be the fake-DMA's.
reg cpu_grant_in_progress;
reg cpu_grant_glitched;
reg armed_for_next_check;
reg g2_next_is_dma;
reg g2_next_checked;
integer g2_fd;

initial begin
    cpu_grant_glitched = 1'b0;
    armed_for_next_check = 1'b0;
    g2_next_is_dma = 1'b0;
    g2_next_checked = 1'b0;
    g2_fd = $fopen("g2_bus_log.txt", "w");
end

always @(posedge clk) begin
    if (reset) begin
        sys_access_prev <= 1'b0;
        cpu_grant_in_progress <= 1'b0;
    end else begin
        sys_access_prev <= sys_access;

        // Track whether we're currently inside a CPU-granted transaction
        // that was ALREADY IN FLIGHT at the moment fake_dma_access first
        // asserted -- that's the specific transaction G2 cares about.
        if (sys_access && !sys_access_prev) begin
            $fwrite(g2_fd, "t=%0t start addr=%05x master=%s fake_dma_access=%b dma_fired=%b cgip=%b\n", $time,
                    {sys_addr, 1'b0}, sys_q_b ? "DMA" : (cpu_q_b ? "DATA" : "INSTR"),
                    fake_dma_access, dma_fired, cpu_grant_in_progress);
        end

        // Any cycle a CPU-granted transaction is active (sys_access,
        // !sys_q_b) and fake_dma_access is (now or becomes) asserted,
        // treat this as the preempted-in-flight transaction -- checked
        // every cycle of the grant window, not just its rising edge, so
        // a fake_dma_access that asserts a cycle or two into the
        // transaction (arbitration latency between the CPU's raw pin
        // and the granted system bus) still counts.
        if (sys_access && !sys_q_b && fake_dma_access && !armed_for_next_check
            && !cpu_grant_in_progress) begin
            cpu_grant_in_progress <= 1'b1;
        end

        if (cpu_grant_in_progress) begin
            if (sys_q_b) begin
                // Grant flipped to DMA while we thought a CPU transaction
                // was still in flight -- preemption glitch.
                cpu_grant_glitched <= 1'b1;
                $fwrite(g2_fd, "t=%0t G2 VIOLATION (a): grant flipped to DMA mid-CPU-transaction\n", $time);
            end
            if (sys_ack) begin
                cpu_grant_in_progress <= 1'b0;
                armed_for_next_check <= 1'b1;
            end
        end

        if (armed_for_next_check && sys_access && !sys_access_prev) begin
            armed_for_next_check <= 1'b0;
            g2_next_checked <= 1'b1;
            g2_next_is_dma <= sys_q_b;
            $fwrite(g2_fd, "t=%0t G2 check (b): next transaction master=%s\n", $time, sys_q_b ? "DMA" : "CPU");
        end
    end
end

longint unsigned g2_cycle_count = 0;
initial begin
    if (!g5_mode) begin
        #(CLK_PERIOD * 200_000);
        $fwrite(g2_fd, "G2 RESULT: cpu_grant_glitched=%0d g2_next_checked=%0d g2_next_is_dma=%0d\n",
                cpu_grant_glitched, g2_next_checked, g2_next_is_dma);
        if (!cpu_grant_glitched && g2_next_checked && g2_next_is_dma)
            $fwrite(g2_fd, "G2: PASS\n");
        else
            $fwrite(g2_fd, "G2: FAIL\n");
        $fclose(g2_fd);
        $finish;
    end
end

// --- G5 (no starvation either direction) ---
// A fixed-period DRQ-style generator (period `G5_DRQ_PERIOD`, default
// 10 CPU clocks -- deliberately aggressive; the real observed rate
// (PIT0 divisor 423 @ 4MHz) translates to a period
// nowhere near this aggressive -- used here
// because it's a genuinely adversarial stress case) instead of
// G2/G3's "re-request after the previous one completes" pattern: if a
// new DRQ period elapses while the previous request is STILL
// unserviced, that's an overrun (the exact failure this gate checks
// for). Models "two channels" worst case as a single fake-DMA master
// requesting at combined-channel rate rather than building a third
// arbitration level for an actual second channel -- documented
// simplification, real per-channel topology is not modeled.
int g5_drq_period;
longint unsigned g5_period_counter;
longint unsigned g5_overrun_count;
longint unsigned g5_request_count;
integer g5_fd;

initial begin
    if (!$value$plusargs("G5_MODE=%d", g5_mode))
        g5_mode = 0;
    if (!$value$plusargs("G5_DRQ_PERIOD=%d", g5_drq_period))
        g5_drq_period = 10;
    g5_period_counter = 0;
    g5_overrun_count = 0;
    g5_request_count = 0;
    if (g5_mode)
        g5_fd = $fopen("g5_result.txt", "w");
end

always @(posedge clk) begin
    if (reset) begin
        g5_period_counter <= 0;
    end else if (g5_mode) begin
        if (g5_period_counter + 1 >= g5_drq_period) begin
            g5_period_counter <= 0;
            g5_request_count <= g5_request_count + 1;
            if (fake_dma_access) begin
                // Previous DRQ-driven request still outstanding when the
                // next period elapsed -- overrun.
                g5_overrun_count <= g5_overrun_count + 1;
                $fwrite(g5_fd, "t=%0t OVERRUN: request %0d still pending\n", $time, g5_request_count);
            end else begin
                fake_dma_access <= 1'b1;
                dma_fired <= 1'b1;
                g3_assert_cycle <= cycle_num;
            end
        end else begin
            g5_period_counter <= g5_period_counter + 1;
        end
    end
end

// PC-fetch retirement counter (reused pattern from
// sim/s80x86_stage_a_tb.sv) to confirm the CPU still makes forward
// progress under worst-case DMA pressure -- G5 doesn't need the actual
// trace values, just proof of continued, non-livelocked retirement.
longint unsigned g5_instr_count = 0;
int g5_target_instr;
initial begin
    if (!$value$plusargs("G5_TARGET_INSTR=%d", g5_target_instr))
        g5_target_instr = 500;
end

always @(posedge clk) begin
    if (g5_mode && !reset && dut.do_next_instruction) begin
        g5_instr_count <= g5_instr_count + 1;
    end
end

initial begin
    if (g5_mode) begin
        fork
            begin
                wait (g5_instr_count >= g5_target_instr);
                $fwrite(g5_fd, "G5: CPU retired %0d instructions (target %0d) -- no livelock\n",
                        g5_target_instr, g5_target_instr);
            end
            begin
                #(CLK_PERIOD * 4_000_000);
                $fwrite(g5_fd, "G5 TIMEOUT: only %0d/%0d instructions retired -- possible livelock/starvation\n",
                        g5_instr_count, g5_target_instr);
            end
        join_any
        disable fork;
        $fwrite(g5_fd, "G5 RESULT: instr_retired=%0d/%0d dma_requests=%0d dma_overruns=%0d\n",
                g5_instr_count, g5_target_instr, g5_request_count, g5_overrun_count);
        if (g5_instr_count >= g5_target_instr && g5_overrun_count == 0)
            $fwrite(g5_fd, "G5: PASS\n");
        else
            $fwrite(g5_fd, "G5: FAIL\n");
        $display("G5 RESULT: instr_retired=%0d/%0d dma_requests=%0d dma_overruns=%0d",
                  g5_instr_count, g5_target_instr, g5_request_count, g5_overrun_count);
        $fclose(g5_fd);
        $finish;
    end
end

endmodule
