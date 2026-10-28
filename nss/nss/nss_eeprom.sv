/*  nss_eeprom.sv - Mitsubishi M6M80011 serial EEPROM (128 x 16) of the NSS (coinage settings)
 *
 *  Copyright (C) 2026 TomSVR. Written for the TomSVR NSS core.
 *  Protocol follows nocash fullsnes ("all values transferred LSB first") and the state machine of
 *  MAME src/devices/machine/m6m80011ap.cpp (Angelo Salese). GPL-3.0-or-later.
 *
 *  Written by the Z80 at e000-ffff: bit 4 = clock (0 = low), bit 3 = data in, bit 0 = select (1 = selected).
 *  A bit is taken each time the clock goes low (as MAME). Commands: c5 write enable, 05 write disable,
 *  25 write (addr, lsb, msb), 15 read (addr, then 16 bits out), 95 status. READ_LSB_FIRST selects the
 *  order of the read data (nocash: LSB first; MAME: MSB first).
 */
module nss_eeprom #(
    parameter READ_LSB_FIRST = 1
)(
    input             clk,
    input             reset,
    input             we,
    input       [7:0] din,
    output reg        dout,

    input             nv_wr,          // NVRAM load/save, one 16-bit word per address
    input       [6:0] nv_addr,
    input      [15:0] nv_din,
    output reg [15:0] nv_dout,
    output reg        nv_chg
);

reg [15:0] mem[128];

localparam S_CMD = 3'd0, S_READ = 3'd1, S_WRITE = 3'd2, S_WEN = 3'd3, S_WDIS = 3'd4, S_STAT = 3'd5;
reg  [2:0] st;
reg  [4:0] pos;
reg [23:0] sh;
reg  [6:0] addr;
reg        wen;
reg        clk_o;
reg [15:0] rd_word;
reg        rd_load;
reg        wr_pend;
reg [15:0] wr_val;

wire [23:0] sh24 = {din[3], sh[23:1]};
wire  [7:0] sh8  = {din[3], sh[7:1]};
wire  [4:0] pos1 = pos + 1'd1;

always @(posedge clk) begin
    nv_chg  <= 0;
    wr_pend <= 0;
    rd_load <= 0;
    // one write port: the BIOS write, else the NVRAM load
    if (wr_pend) begin mem[addr] <= wr_val; nv_chg <= 1; end
    else if (nv_wr) mem[nv_addr] <= nv_din;
    if (rd_load) rd_word <= mem[addr];
    if (reset) begin
        st <= S_CMD; pos <= 0; sh <= 0; wen <= 0; clk_o <= 1; dout <= 0;
    end else if (we) begin
        clk_o <= din[4];
        if (~din[0]) begin
            st <= S_CMD; pos <= 0; sh <= 0;
        end else if (clk_o & ~din[4]) begin
            case (st)
            S_CMD: begin
                sh  <= {sh[23:8], sh8};
                pos <= pos1;
                if (pos1 == 5'd8) begin
                    pos <= 0;
                    case (sh8)
                        8'hc5: st <= S_WEN;
                        8'h05: st <= S_WDIS;
                        8'h25: st <= S_WRITE;
                        8'h15: st <= S_READ;
                        8'h95: st <= S_STAT;
                        default: ;
                    endcase
                end
            end
            S_READ, S_WRITE: begin
                sh  <= sh24;
                pos <= pos1;
                if (pos1 == 5'd8) begin
                    addr <= sh24[22:16];
                    if (st == S_READ) rd_load <= 1;
                end
                // the BIOS (nss-ic14.02 6ceb) clocks low, clocks high, then samples: bit n is out after the
                // (n+1)th clock following the address
                if (st == S_READ && pos1 > 5'd8)
                    dout <= READ_LSB_FIRST ? rd_word[pos1 - 5'd9] : rd_word[5'd24 - pos1];
                if (pos1 == 5'd24) begin
                    st <= S_CMD; pos <= 0;
                    if (st == S_WRITE && wen) begin wr_pend <= 1; wr_val <= sh24[23:8]; end
                end
            end
            default: begin   // S_WEN / S_WDIS / S_STAT: one more byte
                pos <= pos1;
                if (pos1 == 5'd8) begin
                    if (st == S_WEN)  wen <= 1;
                    if (st == S_WDIS) wen <= 0;
                    st <= S_CMD; pos <= 0;
                end
            end
            endcase
        end
    end
end

// NVRAM read port
always @(posedge clk) nv_dout <= mem[nv_addr];

endmodule
