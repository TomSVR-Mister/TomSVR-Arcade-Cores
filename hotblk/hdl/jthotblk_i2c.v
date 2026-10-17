/* SPDX-FileCopyrightText: 2026 Tom Sveen
 * SPDX-License-Identifier: GPL-3.0-or-later
 * 24C02 serial EEPROM (256 bytes, 8-byte write pages) following MAME's i2cmem device:
 * the CPU bit-bangs SCL/SDA through a port; sda is the chip's output (1 when it is not driving).
 * The contents are loaded from the ROM download (prog_* port). */

module jthotblk_i2c(
    input            rst,
    input            clk,
    input            scl,
    input            sdaw,
    output reg       sda,
    // download
    input      [7:0] prog_addr,
    input      [7:0] prog_data,
    input            prog_we
);

localparam [2:0] IDLE=0, DEVSEL=1, ADDR=2, DATAIN=3, READSELACK=4, DATAOUT=5;

reg  [2:0] st;
reg        scl_l, sdaw_l;
reg  [3:0] bits;
reg  [7:0] shift, byteaddr;
reg  [2:0] pofs;
reg        we;
reg  [7:0] waddr, wdata;
wire [7:0] q;
wire [7:0] wa = { byteaddr[7:3], byteaddr[2:0] + pofs };

always @(posedge clk) begin
    we <= 0;
    if( rst ) begin
        st <= IDLE; sda <= 1; scl_l <= 1; sdaw_l <= 1; bits <= 0;
    end else begin
        scl_l  <= scl;
        sdaw_l <= sdaw;
        // start / stop: SDA changes while SCL is high
        if( sdaw != sdaw_l && scl ) begin
            if( sdaw ) st <= IDLE;
            else begin st <= DEVSEL; bits <= 0; end
            sda <= 1;
        end else if( scl != scl_l ) begin
            case( st )
                DEVSEL, ADDR, DATAIN: begin
                    if( bits < 8 ) begin
                        if( scl ) begin shift <= { shift[6:0], sdaw }; bits <= bits + 1'd1; end
                    end else if( scl ) bits <= bits + 1'd1;
                    else if( bits == 8 ) begin
                        sda <= 0;   // acknowledge
                        case( st )
                            DEVSEL:
                                if( shift[7:4] != 4'b1010 ) begin st <= IDLE; sda <= 1; end
                                else st <= shift[0] ? READSELACK : ADDR;
                            ADDR: begin byteaddr <= shift; pofs <= 0; st <= DATAIN; end
                            DATAIN: begin
                                we    <= 1;
                                waddr <= wa;
                                wdata <= shift;
                                pofs  <= pofs + 1'd1;
                            end
                            default:;
                        endcase
                    end else begin
                        bits <= 0;
                        sda  <= 1;
                    end
                end
                READSELACK: begin bits <= 0; st <= DATAOUT; end
                DATAOUT: begin
                    if( bits < 8 ) begin
                        if( scl ) bits <= bits + 1'd1;
                        else begin
                            if( bits == 0 ) begin
                                sda      <= q[7];
                                shift    <= { q[6:0], 1'b0 };
                                byteaddr <= byteaddr + 1'd1;
                            end else begin
                                sda   <= shift[7];
                                shift <= { shift[6:0], 1'b0 };
                            end
                        end
                    end else begin
                        if( scl ) begin
                            if( sdaw ) st <= IDLE;  // no acknowledge from the CPU
                            bits <= 0;
                        end else sda <= 1;
                    end
                end
                default:;
            endcase
        end
    end
end

jtframe_dual_ram #(.DW(8),.AW(8)) u_mem(
    .clk0   ( clk       ),
    .data0  ( wdata     ),
    .addr0  ( waddr     ),
    .we0    ( we        ),
    .q0     (           ),
    .clk1   ( clk       ),
    .data1  ( prog_data ),
    .addr1  ( prog_we ? prog_addr : byteaddr ),
    .we1    ( prog_we   ),
    .q1     ( q         )
);

endmodule
