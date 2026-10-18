/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * PIC16C57 (12-bit core) for the Playmark sound boards. Written from the Microchip PIC16C5x data sheet and
 * MAME's pic16c5x.cpp behaviour.
 *   2048 x 12 program (pages of 512 via STATUS PA1-PA0), 72 bytes of RAM (FSR bits 6-5 select the bank of 10-1f),
 *   2-level stack, ports A (4 bits), B, C with TRIS, TMR0 with the OPTION prescaler. No watchdog, no sleep wake-up.
 *   One instruction every 4 oscillator clocks: cen pulses once per instruction cycle; jumps take two cycles.
 *   Reset vector 7ff.
 * Ports: a port read returns (input & tris) | (latch & ~tris) and pulses the port's rd strobe (read side effects
 * happen for every instruction that reads the register, BSF/BCF included, as in MAME). */

module jtplaymark_pic(
    input             rst,
    input             clk,
    input             cen,          // instruction cycle (osc / 4)

    // program memory
    output     [10:0] prog_addr,
    input      [11:0] prog_data,

    input      [ 3:0] pa_in,
    output reg [ 3:0] pa_out,
    output reg        pa_wr,
    input      [ 7:0] pb_in,
    output reg [ 7:0] pb_out,
    output reg        pb_wr,
    output reg        pb_rd,
    input      [ 7:0] pc_in,
    output reg [ 7:0] pc_out,
    output reg        pc_wr,
    output reg        pc_rd
);

reg  [10:0] pc;
reg  [10:0] stk0, stk1;
reg  [ 7:0] w, status, fsr, tmr0, opt, psc;
reg  [ 3:0] trisa;
reg  [ 7:0] trisb, trisc;
reg  [ 7:0] ram[0:127];
reg         skip;           // dead cycle: 2nd cycle of a jump (pc already loaded) or of a skip (pc moves past the skipped one)
reg         skipinc;

wire [11:0] op  = prog_data;
wire [ 4:0] f   = op[4:0];
wire        d   = op[5];
wire [ 2:0] b   = op[7:5];
wire [ 7:0] k   = op[7:0];
// indirect addressing through FSR when f == 0
wire [ 6:0] fa0 = f==0 ? fsr[6:0] : { fsr[6:5], f };
wire [ 6:0] fa  = fa0[4] ? fa0 : { 2'b00, fa0[4:0] };   // 00-0f are common to all banks
wire [ 4:0] fr  = fa[4:0];
reg  [ 7:0] fval;
reg  [ 7:0] res;
reg         wr_f, wr_w, setz, setc, setdc, cbit, dcbit, doskip;

assign prog_addr = pc;

// register read
always @* begin
    case( fr )
        5'h00: fval = 8'd0;     // INDF through FSR=0
        5'h01: fval = tmr0;
        5'h02: fval = pc[7:0];
        5'h03: fval = status;
        5'h04: fval = fsr | 8'h80;
        5'h05: fval = { 4'hf, (pa_in & trisa) | (pa_out & ~trisa) };
        5'h06: fval = (pb_in & trisb) | (pb_out & ~trisb);
        5'h07: fval = (pc_in & trisc) | (pc_out & ~trisc);
        default: fval = ram[fa];
    endcase
end

// does this instruction read register f?
wire reads_f = (op[11:10]==2'b00 && op[9:6]!=4'b0000) ||    // ALU with f (not NOP/OPTION/TRIS/MOVWF/CLRW/CLRF groups)
               (op[11:10]==2'b01);                          // bit operations
wire [8:0] sum_add = { 1'b0, fval } + { 1'b0, w };
wire [8:0] sum_sub = { 1'b0, fval } + { 1'b0, ~w } + 9'd1;
wire [4:0] dc_add  = { 1'b0, fval[3:0] } + { 1'b0, w[3:0] };
wire [4:0] dc_sub  = { 1'b0, fval[3:0] } + { 1'b0, ~w[3:0] } + 5'd1;

always @* begin
    res = 0; wr_f = 0; wr_w = 0; setz = 0; setc = 0; setdc = 0; cbit = 0; dcbit = 0; doskip = 0;
    casez( op )
        12'b0000_001?_????: begin res = w; wr_f = 1; end                                    // MOVWF
        12'b0000_0100_0000: begin res = 0; wr_w = 1; setz = 1; end                          // CLRW
        12'b0000_011?_????: begin res = 0; wr_f = 1; setz = 1; end                          // CLRF
        12'b0000_10??_????: begin res = sum_sub[7:0]; setz=1; setc=1; cbit=sum_sub[8]; setdc=1; dcbit=dc_sub[4]; wr_f=d; wr_w=!d; end // SUBWF
        12'b0000_11??_????: begin res = fval - 1'd1; setz=1; wr_f=d; wr_w=!d; end          // DECF
        12'b0001_00??_????: begin res = fval | w; setz=1; wr_f=d; wr_w=!d; end              // IORWF
        12'b0001_01??_????: begin res = fval & w; setz=1; wr_f=d; wr_w=!d; end              // ANDWF
        12'b0001_10??_????: begin res = fval ^ w; setz=1; wr_f=d; wr_w=!d; end              // XORWF
        12'b0001_11??_????: begin res = sum_add[7:0]; setz=1; setc=1; cbit=sum_add[8]; setdc=1; dcbit=dc_add[4]; wr_f=d; wr_w=!d; end // ADDWF
        12'b0010_00??_????: begin res = fval; setz=1; wr_f=d; wr_w=!d; end                  // MOVF
        12'b0010_01??_????: begin res = ~fval; setz=1; wr_f=d; wr_w=!d; end                 // COMF
        12'b0010_10??_????: begin res = fval + 1'd1; setz=1; wr_f=d; wr_w=!d; end          // INCF
        12'b0010_11??_????: begin res = fval - 1'd1; wr_f=d; wr_w=!d; doskip = res==0; end // DECFSZ
        12'b0011_00??_????: begin res = { status[0], fval[7:1] }; setc=1; cbit=fval[0]; wr_f=d; wr_w=!d; end // RRF
        12'b0011_01??_????: begin res = { fval[6:0], status[0] }; setc=1; cbit=fval[7]; wr_f=d; wr_w=!d; end // RLF
        12'b0011_10??_????: begin res = { fval[3:0], fval[7:4] }; wr_f=d; wr_w=!d; end    // SWAPF
        12'b0011_11??_????: begin res = fval + 1'd1; wr_f=d; wr_w=!d; doskip = res==0; end // INCFSZ
        12'b0100_????_????: begin res = fval & ~(8'd1<<b); wr_f=1; end                      // BCF
        12'b0101_????_????: begin res = fval |  (8'd1<<b); wr_f=1; end                      // BSF
        12'b0110_????_????: begin doskip = !fval[b]; end                                    // BTFSC
        12'b0111_????_????: begin doskip =  fval[b]; end                                    // BTFSS
        12'b1000_????_????: begin res = k; wr_w = 1; end                                    // RETLW
        12'b1100_????_????: begin res = k; wr_w = 1; end                                    // MOVLW
        12'b1101_????_????: begin res = w | k; wr_w = 1; setz = 1; end                      // IORLW
        12'b1110_????_????: begin res = w & k; wr_w = 1; setz = 1; end                      // ANDLW
        12'b1111_????_????: begin res = w ^ k; wr_w = 1; setz = 1; end                      // XORLW
        default:;
    endcase
end

// TMR0 clock: instruction cycle, through the prescaler when PSA (OPTION bit 3) = 0
wire [7:0] psc_n  = psc + 1'd1;
wire       tmr_inc = opt[5] ? 1'b0 : (opt[3] ? 1'b1 : psc_n[opt[2:0]] & ~psc[opt[2:0]]);

integer i;
always @(posedge clk) begin
    pa_wr <= 0; pb_wr <= 0; pc_wr <= 0; pb_rd <= 0; pc_rd <= 0;
    if( rst ) begin
        pc <= 11'h7ff; status <= 8'h18; fsr <= 0; w <= 0; opt <= 8'h3f; psc <= 0; tmr0 <= 0;
        trisa <= 4'hf; trisb <= 8'hff; trisc <= 8'hff; skip <= 0; skipinc <= 0; stk0 <= 0; stk1 <= 0;
        pa_out <= 0; pb_out <= 0; pc_out <= 0;
    end else if( cen ) begin
        if( !opt[5] ) begin
            psc <= psc_n;
            if( tmr_inc ) tmr0 <= tmr0 + 1'd1;
        end
        if( skip ) begin
            skip <= 0;
            if( skipinc ) pc <= pc + 1'd1;
        end else begin
            skipinc <= 0;
            pc <= pc + 1'd1;
            if( reads_f ) begin
                if( fr==5'h06 ) pb_rd <= 1;
                if( fr==5'h07 ) pc_rd <= 1;
            end
            // status flags
            if( setz  ) status[2] <= res==0;
            if( setc  ) status[0] <= cbit;
            if( setdc ) status[1] <= dcbit;
            if( wr_w ) w <= res;
            if( wr_f ) begin
                case( fr )
                    5'h00:;
                    5'h01: begin tmr0 <= res; psc <= 0; end
                    5'h02: begin pc <= { status[6:5], 1'b0, res }; skip <= 1; end
                    5'h03: status <= { status[7], res[6:5], status[4:3], (setz||setc||setdc) ? status[2:0] : res[2:0] };
                    5'h04: fsr <= res;
                    5'h05: begin pa_out <= res[3:0]; pa_wr <= 1; end
                    5'h06: begin pb_out <= res; pb_wr <= 1; end
                    5'h07: begin pc_out <= res; pc_wr <= 1; end
                    default: ram[fa] <= res;
                endcase
            end
            if( doskip ) begin skip <= 1; skipinc <= 1; end
            casez( op )
                12'b0000_0000_0010: opt <= w;                                       // OPTION
                12'b0000_0000_0101: trisa <= w[3:0];                                // TRIS 5
                12'b0000_0000_0110: trisb <= w;                                     // TRIS 6
                12'b0000_0000_0111: trisc <= w;                                     // TRIS 7
                12'b1000_????_????: begin pc <= stk0; stk0 <= stk1; skip <= 1; end  // RETLW
                12'b1001_????_????: begin                                           // CALL
                    stk1 <= stk0; stk0 <= pc + 1'd1;
                    pc <= { status[6:5], 1'b0, k }; skip <= 1;
                end
                12'b101?_????_????: begin pc <= { status[6:5], op[8:0] }; skip <= 1; end // GOTO
                default:;
            endcase
        end
    end
end

endmodule
