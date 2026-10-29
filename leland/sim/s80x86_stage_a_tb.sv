// Stage-A bench: s80x86 Core.sv +
// flat SOR audiocpu ROM/RAM model, no interrupts, no peripherals. Logs
// every retired instruction's (CS,IP) to a PC-fetch trace for diffing
// against a MAME reference trace.
//
// Memory model: single-cycle-ack BRAM-style array, address space per
// leland_80186_map_program (leland_a.cpp): RAM 0x00000-0x03FFF mirrored
// x8 up to 0x1FFFF, ROM 0x20000-0xFFFFF identity-mapped from the
// audiocpu ROM region. I/O-space (d_io) accesses are ACKed with a dummy
// value -- Stage A only cares about the instruction stream, not
// peripheral correctness.
//
// The ROM image is NOT checked into this repo (copyright) -- regenerate
// it from the real offroad ROM set, then point ROM_HEX_PATH at the
// resulting .hex file (plusarg or edit below).

`timescale 1ns / 1ps

module s80x86_stage_a_tb;

localparam CLK_PERIOD = 20; // 50MHz sim clock -- arbitrary, functional only

reg clk = 0;
reg reset = 1;

always #(CLK_PERIOD/2) clk = ~clk;

// Interrupts tied off -- Stage A per plan §4.3 is "no interrupts".
wire nmi = 1'b0;
wire intr = 1'b0;
wire [7:0] irq = 8'h0;
wire inta;

// Instruction bus
wire [19:1] instr_m_addr;
reg  [15:0] instr_m_data_in;
wire        instr_m_access;
reg         instr_m_ack;

// Data bus
wire [19:1] data_m_addr;
reg  [15:0] data_m_data_in;
wire [15:0] data_m_data_out;
wire        data_m_access;
reg         data_m_ack;
wire        data_m_wr_en;
wire [1:0]  data_m_bytesel;
wire        d_io;
wire        lock;

// Debug port tied off (not used by Stage A)
wire        debug_stopped;
wire        debug_seize = 1'b0;
wire [7:0]  debug_addr = 8'h0;
wire        debug_run = 1'b0;
wire [15:0] debug_val;
wire [15:0] debug_wr_val = 16'h0;
wire        debug_wr_en = 1'b0;

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
         .data_m_addr(data_m_addr),
         .data_m_data_in(data_m_data_in),
         .data_m_data_out(data_m_data_out),
         .data_m_access(data_m_access),
         .data_m_ack(data_m_ack),
         .data_m_wr_en(data_m_wr_en),
         .data_m_bytesel(data_m_bytesel),
         .d_io(d_io),
         .lock(lock),
         .debug_stopped(debug_stopped),
         .debug_seize(debug_seize),
         .debug_addr(debug_addr),
         .debug_run(debug_run),
         .debug_val(debug_val),
         .debug_wr_val(debug_wr_val),
         .debug_wr_en(debug_wr_en));

// --- Memory model ---
// RAM: 16KB, mirrored x8 across 0x00000-0x1FFFF.
// ROM: 1MB flat image, identity-mapped 0x00000-0xFFFFF within the image
// (region byte offset == CPU address, per leland.cpp's
// .region("audiocpu", 0x20000)); only 0x20000-0xFFFFF is ever
// fetched from it (0x00000-0x1FFFF is RAM on the CPU side).
reg [7:0] ram [0:16383];
reg [7:0] rom [0:1048575];

string rom_hex_path;
initial begin
    if (!$value$plusargs("ROM_HEX=%s", rom_hex_path))
        rom_hex_path = "audiocpu_offroad.hex";
    $readmemh(rom_hex_path, rom);
    for (int i = 0; i < 16384; i++) ram[i] = 8'h00;
end

// Microcode.sv's own `initial $readmemb({{`MICROCODE_ROM_PATH, ...}}, mem);`
// (rtl/s80x86/microcode/Microcode.sv) relies on a compile-time
// `MICROCODE_ROM_PATH` macro + brace string concatenation that either
// isn't resolving under this ModelSim or isn't finding the file
// silently (no warning emitted either way) -- reload it explicitly here
// via a hierarchical reference so Stage A doesn't depend on getting
// that macro plumbing right under this tool.
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
    // ROM writes are dropped (real hardware would ignore them too).
endtask

// --- Ack timing model (seam-gate G1: stall tolerance) ---
// Default is single-cycle ack (ack the cycle after access first asserts).
// +RANDOM_ACK=1 switches to an independently randomized 1-500 cycle ack
// delay per access on each port (a fresh countdown drawn every time
// access rises from low), seeded via +ACK_SEED=<n> for reproducibility
// -- the seed must be recorded alongside the result, hence the plusarg
// rather than $random with no seed control.
int random_ack_mode;
int ack_seed;
initial begin
    if (!$value$plusargs("RANDOM_ACK=%d", random_ack_mode))
        random_ack_mode = 0;
    if (!$value$plusargs("ACK_SEED=%d", ack_seed))
        ack_seed = 1;
    if (random_ack_mode)
        $display("G1: random ack delay mode, ACK_SEED=%0d", ack_seed);
end

function automatic int rand_delay(inout int seed);
    // 1-500 inclusive.
    rand_delay = ($random(seed) % 500);
    if (rand_delay < 0) rand_delay = -rand_delay;
    rand_delay = rand_delay + 1;
endfunction

// Instruction fetch port.
reg instr_m_access_prev, instr_m_ack_prev;
reg [15:0] instr_delay_remaining;
always @(posedge clk) begin
    if (reset) begin
        instr_m_ack <= 1'b0;
        instr_m_access_prev <= 1'b0;
        instr_m_ack_prev <= 1'b0;
        instr_delay_remaining <= 16'h0;
    end else begin
        instr_m_access_prev <= instr_m_access;
        instr_m_ack_prev <= instr_m_ack;
        if (instr_m_access & ~instr_m_ack) begin
            if (~instr_m_access_prev) begin
                // Access just rose: pick this access's ack latency.
                instr_delay_remaining <= random_ack_mode ?
                    rand_delay(ack_seed)[15:0] : 16'd1;
                instr_m_ack <= 1'b0;
            end else if (instr_delay_remaining <= 16'd1) begin
                instr_m_ack <= 1'b1;
                instr_m_data_in <= {mem_read_byte({instr_m_addr, 1'b1}),
                                     mem_read_byte({instr_m_addr, 1'b0})};
            end else begin
                instr_delay_remaining <= instr_delay_remaining - 16'd1;
                instr_m_ack <= 1'b0;
            end
        end else begin
            instr_m_ack <= 1'b0;
        end
    end
end

// Data port (byte-lane aware, otherwise identical timing model).
reg data_m_access_prev, data_m_ack_prev;
reg [15:0] data_delay_remaining;
always @(posedge clk) begin
    if (reset) begin
        data_m_ack <= 1'b0;
        data_m_access_prev <= 1'b0;
        data_m_ack_prev <= 1'b0;
        data_delay_remaining <= 16'h0;
    end else begin
        data_m_access_prev <= data_m_access;
        data_m_ack_prev <= data_m_ack;
        if (data_m_access & ~data_m_ack) begin
            if (~data_m_access_prev) begin
                data_delay_remaining <= random_ack_mode ?
                    rand_delay(ack_seed)[15:0] : 16'd1;
                data_m_ack <= 1'b0;
            end else if (data_delay_remaining <= 16'd1) begin
                data_m_ack <= 1'b1;
                if (d_io) begin
                    data_m_data_in <= 16'hffff; // dummy I/O read value
                end else begin
                    data_m_data_in <= {mem_read_byte({data_m_addr, 1'b1}),
                                        mem_read_byte({data_m_addr, 1'b0})};
                end
                if (data_m_wr_en && !d_io) begin
                    if (data_m_bytesel[0])
                        mem_write_byte({data_m_addr, 1'b0}, data_m_data_out[7:0]);
                    if (data_m_bytesel[1])
                        mem_write_byte({data_m_addr, 1'b1}, data_m_data_out[15:8]);
                end
            end else begin
                data_delay_remaining <= data_delay_remaining - 16'd1;
                data_m_ack <= 1'b0;
            end
        end else begin
            data_m_ack <= 1'b0;
        end
    end
end

// --- G1 checker: `access && !ack |=> access` on both ports (no real SVA
// support in this ModelSim edition -- "System Verilog assertions are
// supported only in Questasim", confirmed by an isolated test; this is
// the plain-Verilog equivalent of the property). The core must hold its
// access request until acknowledged, never drop mid-request.
// property: access && !ack |=> access -- i.e. access must never drop
// except in response to ack. Checked as: whenever access falls
// (access_prev=1, access=0 now), either the live ack or last cycle's
// ack must be 1 -- covers both "ack causes access to drop
// combinationally the same edge" and "one cycle later" DUT timing
// without depending on exactly which; either way, an access drop with
// NO ack ever observed (neither this cycle nor last) is unambiguously
// the violation this property exists to catch.
longint unsigned access_violations = 0;
always @(posedge clk) begin
    if (!reset) begin
        if (instr_m_access_prev && !instr_m_access && !instr_m_ack && !instr_m_ack_prev) begin
            $display("G1 VIOLATION: instr_m_access dropped without ack at t=%0t", $time);
            access_violations <= access_violations + 1;
        end
        if (data_m_access_prev && !data_m_access && !data_m_ack && !data_m_ack_prev) begin
            $display("G1 VIOLATION: data_m_access dropped without ack at t=%0t", $time);
            access_violations <= access_violations + 1;
        end
    end
end

// --- PC-fetch trace ---
// `ip_current` (IP.sv's `val`/`cur_val`) is the PREFETCHER's fetch
// pointer, which runs ahead of instruction retirement by however many
// bytes are already queued in the prefetch FIFO -- sampling it at
// retirement time does NOT give the retiring instruction's own address
// (confirmed empirically: jump targets never appeared in an earlier
// version of this trace that sampled ip_current directly). IP.sv
// itself solves exactly this problem internally for rollback purposes
// via a second register, `instruction_start_addr`, latched from
// `cur_val` (pre-increment) at the same edge `start_instruction`
// (= Core.sv's `instruction_fifo_rd_en`, i.e. instruction DISPATCH,
// not retirement) fires. We mirror that same capture here rather than
// reaching into IP.sv's internals directly, to sidestep any doubt
// about exact intra-cycle NBA-update ordering: latch (cs, IP.cur_val)
// into `pending_cs`/`pending_ip` at dispatch time, and use whatever
// they hold (i.e. the PRIOR dispatch's snapshot, since the NBA update
// below hasn't taken effect yet in the same time step even if dispatch
// and retire coincide on one edge) when `do_next_instruction` (retire)
// fires. Hierarchical reference into dut's internal wires -- fine for
// a bench, not part of the DUT.
integer trace_fd;
longint unsigned instr_count = 0;
longint unsigned MAX_INSTR;
// Initialized to the architectural 80186 reset vector (CS=FFFF,IP=0000)
// so the very first retirement (before any dispatch has run to give
// pending_cs/pending_ip a real captured value) reports correctly too,
// instead of X.
reg [15:0] pending_cs = 16'hFFFF, pending_ip = 16'h0000;

string trace_path;
initial begin
    if (!$value$plusargs("MAX_INSTR=%d", MAX_INSTR))
        MAX_INSTR = 2000;
    if (!$value$plusargs("TRACE_OUT=%s", trace_path))
        trace_path = "s80x86_stage_a_trace.log";
    trace_fd = $fopen(trace_path, "w");
    reset = 1;
    repeat (10) @(posedge clk);
    reset = 0;
end

// --- WAIT (opcode 0x9B) never-dispatched backstop assertion ---
// A real 13M-instruction MAME trace found zero WAIT mnemonics in a
// execution covering boot through early attract -- the
// core's stock WAIT-as-NOP microcode (rtl/s80x86/microcode/wait.us,
// `.at 0x9b; next_instruction;`, i.e. no /TEST-gated spin at all) is
// very likely fine as-is for SOR, so this is a cheap directed
// backstop. `Microcode.sv`'s own
// dispatch (`starting_instruction = !stall && (next_addr ==
// {..., next_instruction_value.opcode})`) confirms the microcode ROM is
// opcode-address-mapped for simple one-byte opcodes, so a fresh
// instruction's *decoded* opcode field (`next_instruction_value.opcode`,
// latched by the real InsnDecoder, not a raw/static byte scan --
// a static scan finds ~600 candidate 0x9B hits that are linear-decode
// misalignment artifacts) is a reliable, real-time signal for "was WAIT ever
// actually dispatched", sampled at the same `instruction_fifo_rd_en`
// (dispatch) edge the PC-trace above already uses.
integer wait_dispatch_count = 0;

always @(posedge clk) begin
    if (!reset && dut.do_next_instruction) begin
        $fwrite(trace_fd, "%0d: %04X:%04X\n", instr_count, pending_cs, pending_ip);
        instr_count <= instr_count + 1;
        if (instr_count + 1 >= MAX_INSTR) begin
            $fwrite(trace_fd, "trace complete at %0d instructions\n", instr_count + 1);
            $display("access_violations=%0d", access_violations);
            $display("WP9: wait_dispatch_count=%0d (must be 0)", wait_dispatch_count);
            $fclose(trace_fd);
            $finish;
        end
    end
    if (dut.instruction_fifo_rd_en) begin
        pending_cs <= dut.cs;
        pending_ip <= dut.IP.cur_val;
        if (dut.next_instruction_value.opcode == 8'h9b) begin
            wait_dispatch_count <= wait_dispatch_count + 1;
            $display("WP9 WARNING: WAIT (0x9B) dispatched at instr %0d (CS:IP %04X:%04X)",
                      instr_count, dut.cs, dut.IP.cur_val);
        end
    end
end

// Safety timeout in case the core never retires an instruction (stuck).
initial begin
    #(CLK_PERIOD * 2_000_000);
    $fwrite(trace_fd, "TIMEOUT: only %0d instructions retired\n", instr_count);
    $display("WP9: wait_dispatch_count=%0d (must be 0)", wait_dispatch_count);
    $fclose(trace_fd);
    $finish;
end

endmodule
