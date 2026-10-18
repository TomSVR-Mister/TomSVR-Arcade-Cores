/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Playmark sound (MAME playmark.cpp): PIC16C57 at 12 MHz (3 MIPS) driving an OKI M6295 (1 MHz, pin 7 high).
 *   Port A write: OKI bank (data & 7, masked by the number of 128 kB banks)
 *   Port B read:  control & 38 = 30 -> sound latch, = 28 -> OKI status & 0f, else 0.   Port B write: OKI command byte
 *   Port C read:  bit 6 = 0 while a sound latch byte is pending (the read acknowledges it), else 40
 *   Port C write: control; (data & 38) = 18 writes the command byte to the OKI.
 *   OKI address space: 00000-1ffff fixed, 20000-3ffff banked (bank * 20000 of the sample ROM).
 *   hm (Hot Mind): port A not wired, the bank comes from port C bits 1-0 (MAME snd_control_w<3>).
 * The PIC program comes in the download as the Intel HEX text MAME uses: the ":10" records are decoded here,
 * 8 little-endian words each, in file order (as MAME's decode_pic_hex_dump does). */

module jtplaymark_sound(
    input              rst,
    input              clk,
    input              cen_pic,     // 3 MHz
    input              cen_oki,     // 1 MHz
    input       [ 1:0] nbank,       // number of OKI banks - 1 (1: 2 banks, 3: 4 banks)
    input              hm,
    // PIC HEX download
    input              hex_we,
    input       [ 7:0] hex_data,
    input              hex_first,   // the current HEX byte is the first of the file
    // sound latch
    input       [ 7:0] latch,
    input              snd_wr,
    // OKI ROM
    output      [18:0] rom_addr,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output signed [13:0] pcm
);

// ---------------- HEX loader ----------------
reg  [ 3:0] hst;
reg  [ 4:0] hcnt;       // hex digits of the current record field
reg  [15:0] hword;
reg  [10:0] pwa;        // program write address
reg  [11:0] pwd;
reg         pwe;
reg  [ 2:0] skipc;
wire [ 3:0] nib = hex_data >= "a" ? hex_data - "a" + 4'd10 :
                  hex_data >= "A" ? hex_data - "A" + 4'd10 : hex_data[3:0];
localparam [3:0] H_IDLE=0, H_L1=1, H_L0=2, H_SKIP=3, H_DATA=4, H_DONE=5;

always @(posedge clk) begin
    pwe <= 0;
    if( hex_we && hex_first ) begin
        hst <= hex_data == ":" ? H_L1 : H_IDLE;
        pwa <= 0;
    end else if( hex_we ) begin
        case( hst )
            H_IDLE: if( hex_data == ":" ) hst <= H_L1;
            H_L1:   hst <= hex_data == "1" ? H_L0 : H_IDLE;
            H_L0:   if( hex_data == "0" ) begin hst <= H_SKIP; skipc <= 0; end else hst <= H_IDLE;   // ":10"
            H_SKIP: begin   // address (4 digits) and record type (2 digits)
                skipc <= skipc + 1'd1;
                if( skipc==5 ) begin hst <= H_DATA; hcnt <= 0; end
            end
            H_DATA: begin   // 32 digits = 8 words: lo byte, hi byte
                hword <= { hword[11:0], nib };
                hcnt  <= hcnt + 1'd1;
                if( hcnt[1:0]==3 ) begin
                    pwd <= { nib, hword[11:4] };    // digits: lo-hi, lo-lo, hi-hi (0), hi-lo -> 12 bits { hi-lo, lo }
                    pwe <= 1;
                end
                if( hcnt==31 ) hst <= H_IDLE;
            end
            default: hst <= H_IDLE;
        endcase
    end
    if( pwe ) pwa <= pwa + 1'd1;
end

// ---------------- PIC ----------------
wire [10:0] prog_addr;
wire [11:0] prog_data;
wire [ 3:0] pa_out;
wire [ 7:0] pb_out, pc_out;
wire        pa_wr, pb_wr, pc_wr, pb_rd, pc_rd;
reg  [ 7:0] ctrl, cmd;
reg  [ 2:0] bank;
reg         pend;
wire [ 7:0] oki_dout;
reg         oki_wrn;
wire [ 7:0] pb_in = (ctrl & 8'h38)==8'h30 ? latch : (ctrl & 8'h38)==8'h28 ? { 4'd0, oki_dout[3:0] } : 8'd0;
wire [ 7:0] pc_in = pend ? 8'h00 : 8'h40;

jtframe_dual_ram #(.DW(12),.AW(11)) u_prog(
    .clk0   ( clk       ),
    .data0  ( pwd       ),
    .addr0  ( pwa       ),
    .we0    ( pwe       ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( 12'd0     ),
    .addr1  ( prog_addr ),
    .we1    ( 1'b0      ),
    .q1     ( prog_data )
);

jtplaymark_pic u_pic(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_pic   ),
    .prog_addr  ( prog_addr ),
    .prog_data  ( prog_data ),
    .pa_in      ( 4'hf      ),
    .pa_out     ( pa_out    ),
    .pa_wr      ( pa_wr     ),
    .pb_in      ( pb_in     ),
    .pb_out     ( pb_out    ),
    .pb_wr      ( pb_wr     ),
    .pb_rd      ( pb_rd     ),
    .pc_in      ( pc_in     ),
    .pc_out     ( pc_out    ),
    .pc_wr      ( pc_wr     ),
    .pc_rd      ( pc_rd     )
);

always @(posedge clk) begin
    if( rst ) begin
        ctrl <= 0; cmd <= 0; bank <= 0; pend <= 0; oki_wrn <= 1;
    end else begin
        if( snd_wr ) pend <= 1;
        else if( pc_rd && pend ) pend <= 0;
        if( pa_wr && !hm ) bank <= pa_out[2:0] & { 1'b0, nbank };
        if( pb_wr ) cmd  <= pb_out;
        if( pc_wr ) begin
            ctrl <= pc_out;
            if( hm ) bank <= { 1'b0, pc_out[1:0] & nbank };
            if( (pc_out & 8'h38)==8'h18 ) oki_wrn <= 0;
        end
        if( cen_oki ) oki_wrn <= 1;     // hold the write for one OKI clock
    end
end

wire [17:0] oki_a;
`ifdef SIMULATION
always @(posedge clk) begin
    if( hex_we && hex_first ) $display("PIC HEX download starts");
    if( pc_wr && (pc_out & 8'h38)==8'h18 ) $display("OKI write %02X", cmd);
    if( snd_wr ) $display("Sound latch %02X", latch);
end
`endif

assign rom_addr = oki_a[17] ? { bank[1:0], oki_a[16:0] } : { 2'b00, oki_a[16:0] };

jt6295 #(.INTERPOL(0)) u_pcm(
    .rst      ( rst           ),
    .clk      ( clk           ),
    .cen      ( cen_oki       ),
    .ss       ( 1'b1          ),
    .wrn      ( oki_wrn       ),
    .din      ( cmd           ),
    .dout     ( oki_dout      ),
    .rom_addr ( oki_a         ),
    .rom_data ( rom_data      ),
    .rom_ok   ( rom_ok        ),
    .sound    ( pcm           ),
    .sample   (               )
);

endmodule
