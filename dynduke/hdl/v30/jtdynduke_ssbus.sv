/* SPDX-License-Identifier: GPL-3.0-or-later
   Minimal save-state bus interface for the V30 bus adapter. JTDYNDUKE has no save states, so the bus
   stays idle (select = 8'hff) and these tasks never fire. Written to match the port the adapter expects. */

interface ssbus_if();
    logic [63:0] data;
    logic [31:0] addr;
    logic [ 7:0] select;
    logic        write;
    logic        read;
    logic        query;
    logic [63:0] data_out;
    logic        ack;

    function logic access(int idx);
        return (select == idx[7:0]) & ~query & (read | write);
    endfunction

    task setup(int idx, input [31:0] count, int width);
        ack <= 0;
    endtask

    task read_response(int idx, input [63:0] dout);
        if (select == idx[7:0]) begin
            data_out <= dout;
            ack <= 1;
        end
    endtask

    task write_ack(int idx);
        if (select == idx[7:0]) ack <= 1;
    endtask

    modport master(
        output data, addr, select, write, read, query,
        input data_out, ack
    );

    modport slave(
        input data, addr, select, write, read, query,
        output data_out, ack,
        import access,
        import setup,
        import read_response,
        import write_ack
    );
endinterface
