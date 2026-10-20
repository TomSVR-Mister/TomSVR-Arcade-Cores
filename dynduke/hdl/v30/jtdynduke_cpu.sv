/* SPDX-License-Identifier: GPL-3.0-or-later
   NEC V30 at 8 MHz (48 MHz / 6) for JTDYNDUKE, around the V30 bus adapter from the MiSTer Irem M72 core.
   The clock enable is withheld while an SDRAM read is pending and the lost cycles are caught up later, at
   most one T-state every three clocks (the multicycle constraint in syn/timing.sdc relies on that gap). */

module jtdynduke_cpu(
    input             rst,
    input             clk,
    input             stall,      // SDRAM data not ready yet

    output     [19:1] addr,
    output     [ 1:0] be,         // [0] low byte, [1] high byte
    output     [15:0] dout,
    input      [15:0] din,
    output            mem_rd,
    output            mem_wr,
    output            io_rd,
    output            io_wr,

    input             int_req,
    input      [ 7:0] int_vector,
    output            int_ack
);

reg  [2:0] div;
reg  [3:0] owed;
reg  [1:0] gap;
reg        ce;
wire       tick = div==5;
wire [19:0] full_addr;

assign addr = full_addr[19:1];

always @(posedge clk) begin
    div <= tick ? 3'd0 : div + 3'd1;
    ce  <= 0;
    if( gap!=0 ) gap <= gap - 2'd1;
    if( !stall && owed!=0 && gap==0 ) begin
        ce   <= 1;
        gap  <= 2;
        owed <= owed - 4'd1 + {3'd0, tick};
    end else if( tick && owed!=4'hf ) begin
        owed <= owed + 4'd1;
    end
end

ssbus_if ssb();
assign ssb.data   = 64'd0;
assign ssb.addr   = 32'd0;
assign ssb.select = 8'd0;
assign ssb.write  = 1'b0;
assign ssb.read   = 1'b0;
assign ssb.query  = 1'b0;

v30_bus u_v30(
    .clk            ( clk           ),
    .ce             ( ce            ),
    .reset          ( rst           ),
    .ready          ( 1'b1          ),
    .cpu_addr       ( full_addr     ),
    .cpu_be         ( be            ),
    .cpu_dout       ( dout          ),
    .cpu_din        ( din           ),
    .mem_rd         ( mem_rd        ),
    .io_rd          ( io_rd         ),
    .mem_wr_pending (               ),
    .mem_wr         ( mem_wr        ),
    .io_wr          ( io_wr         ),
    .code_fetch     (               ),
    .int_req        ( int_req       ),
    .int_vector     ( int_vector    ),
    .int_ack        ( int_ack       ),
    .dbg_regs       (               ),
    .ssbus          ( ssb           ),
    .ss_restore_done( 1'b0          ),
    .ss_quiet       (               )
);

endmodule
