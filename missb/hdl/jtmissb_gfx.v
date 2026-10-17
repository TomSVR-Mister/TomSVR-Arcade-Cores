/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 29-05-2020
 * Miss Bubble II changes (2026, Tom Sveen): 8 bpp tiles (MAME missb2.cpp), two 32-bit words per tile row:
 *   word 0 = { region 1 row bytes 1,0, region 0 row bytes 1,0 } on one bus, word 1 = same for regions 2 and 3 on a second
 *   bus in another SDRAM bank, both read at once (ROM data inverted).
 *   Pen bit 7 = region 0 high nibble ... bit 0 = region 3 low nibble; pixel q of a byte half: high nibble bit 4+q, low nibble bit q.
 *   Pen 0xFF is transparent. The colour bits of the tile attribute are not used. */

module jtmissb_gfx(
    input               rst,
    input               clk,
    input               clk_cpu,
    input               pxl2_cen,
    input               pxl_cen,
    // PROMs
    input      [ 7:0]   prog_addr,
    input      [ 3:0]   prog_data,
    input               prom_we,
    // Screen
    input               flip,
    input               LHBL,
    input               LVBL,
    input      [8:0]    hdump,
    input      [7:0]    vdump,
    // CPU interface
    input               vram_cs,
    output reg [ 7:0]   vram_dout,
    input               cpu_rnw,
    input      [12:0]   cpu_addr,
    input      [ 7:0]   cpu_dout,
    // SDRAM interface
    output     [18:2]   rom_addr,
    input      [31:0]   rom_data,
    input               rom_ok,
    output reg          rom_cs,
    input      [31:0]   rom2_data,
    input               rom2_ok,
    // Color address to palette
    output     [ 7:0]   col_addr
);

wire [ 7:0] scan0_data, scan1_data, scan2_data, scan3_data;
wire [ 7:0] vram0_dout, vram1_dout, vram2_dout, vram3_dout;
wire [10:0] vram_addr = cpu_addr[11:1];
reg  [ 3:0] vram_we, cpu_cc;
reg  [ 7:0] line_din;
reg  [63:0] pxw;
reg  [ 8:0] line_addr;
reg         line_we;
wire [ 3:0] dec_dout;
wire [ 7:0] dec_addr;
reg  [ 4:0] vn;

always @(*) begin
    cpu_cc = 4'd0;
    cpu_cc[{cpu_addr[12],cpu_addr[0]}] = 1;
    vram_we = cpu_cc & {4{~cpu_rnw & vram_cs}};
end


always @(*) begin
    case( cpu_cc )
        4'b0001: vram_dout = vram0_dout;
        4'b0010: vram_dout = vram1_dout;
        4'b0100: vram_dout = vram2_dout;
        4'b1000: vram_dout = vram3_dout;
        default: vram_dout = 8'hff;
    endcase
end

localparam [10:0] OBJ_START = 11'h140;

reg  [ 9:0] code0, code1, code_mux;
// Let's follow the original signal names but in lower case
reg  [ 8:0] oa;   // VRAM address for first read (object)
reg         oatop;
wire [11:0] sa;   // VRAM address for second read (char)
reg  [ 7:0] vsub, sa_base, hotpxl;
reg  [31:0] pxl_data;

reg  [ 8:0] hpos;
reg  [ 3:0] bank, pal0, pal1, pal_mux;
wire [10:0] cbus; // address to read VRAM
reg         ch;
reg  [ 1:0] hflip, vflip;
reg         hf_mux, vf_mux;
reg  [ 1:0] waitok;
//reg         last_LHBL;
reg         busy, idle; // extra cycle to wait for memories
wire [15:0] vrmux;
wire        lden_b, next;
reg         half, newdata;

assign cbus      = ch ? { sa[10:6],oa[0],sa[4:0] } : {1'b1, oatop, oa };
assign rom_addr  = { bank, code_mux, vsub[2:0]^{3{vf_mux}}  }; // 17 bits
assign sa        = { sa_base[7]&sa_base[5], sa_base[4:0], 1'b1 /*unused bit*/,
                     dec_dout[1:0], vsub[5:3] };
assign dec_addr  = { LVBL, sa_base[7:5], vsub[7:4] };
assign vrmux     = sa[11] ? {scan3_data, scan2_data} : {scan1_data, scan0_data};
assign lden_b    = dec_dout[2];
assign next      = dec_dout[3];

//always @(posedge clk) last_LHBL <= LHBL;

`ifdef SIMULATION
wire [1:0] phase = { ch, oa[0] };
`endif

// Collection of tile information
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        oa      <= 9'd0;
        ch      <= 0;
        idle    <= 0;
        code0   <= 10'd0;
        code1   <= 10'd0;
        bank    <= 4'd0;
        vsub    <= 8'd0;
        hflip   <= 2'b0;
        vflip   <= 2'b0;
        sa_base <= 8'd0;
        newdata <= 0;
    end else begin
        if( hdump[8] && hdump<9'h12B ) begin // note that tile drawing is disabled if LHBL is low
            oa      <= 9'h80;
            ch      <= 0;
            idle    <= 0;
            oatop   <= 1;
            newdata <= 0;
        end else begin
            if( !busy && oa[8:1]!=8'hE0 ) begin // the oa limit was not in the original
                { oa[8:1], ch, oa[0], idle } <= { oa[8:1], ch, oa[0], idle } + 10'd1;
            end
            if(idle) begin
                case( {ch, oa[0]} )
                    2'd0: begin
                        vsub    <= scan2_data+(vdump^{8{flip}});
                        sa_base <= scan3_data;
                    end
                    2'd1: begin
                        oatop   <= ~scan3_data[7];
                        hpos    <= {scan3_data[6], scan2_data };
                        bank    <= scan3_data[3:0]; // there was a provision to use bit 4
                                   // too on the board via a jumper but was never used
                    end
                    2'd2: begin
                        code0   <= vrmux[9:0];
                        pal0    <= vrmux[13:10];
                        hflip[0]<= vrmux[14];
                        vflip[0]<= vrmux[15];
                    end
                    2'd3: begin
                        code1   <= vrmux[9:0];
                        pal1    <= vrmux[13:10];
                        hflip[1]<= vrmux[14];
                        vflip[1]<= vrmux[15];
                    end
                endcase
            end
            newdata <= {ch, oa[0],idle}==3'b110;
        end
    end
end

// Tile drawing
// pxw = { word 1, word 0 }; byte k of word 0: 0/1 region 0 row bytes, 2/3 region 1; word 1: regions 2/3
function [7:0] get_pxl;
    input [63:0] w;
    input [ 2:0] p;     // pixel 0-7, left to right
    reg   [ 2:0] q;
    reg   [ 7:0] r0, r1, r2, r3;
    begin
        r0 = p[2] ? w[15: 8] : w[ 7: 0];
        r1 = p[2] ? w[31:24] : w[23:16];
        r2 = p[2] ? w[47:40] : w[39:32];
        r3 = p[2] ? w[63:56] : w[55:48];
        q  = { 1'b0, p[1:0] };
        get_pxl = ~{ r0[4+q], r0[q], r1[4+q], r1[q], r2[4+q], r2[q], r3[4+q], r3[q] };
    end
endfunction

reg [2:0] pcnt;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        busy    <= 0;
        rom_cs  <= 0;
        line_we <= 0;
        waitok  <= 2'b11;
    end else begin
        /*if( !LHBL ) begin
            busy    <= 0;
            line_we <= 0;
            rom_cs  <= 0;
        end else*/
        if( newdata & ~next) begin
            busy        <= 1;
            rom_cs      <= 1;
            waitok      <= 2'b11;
            if(!lden_b) line_addr <= hpos;
            line_we     <= 0;
            code_mux    <= code0;
            hf_mux      <= hflip[0];
            vf_mux      <= vflip[0];
            pal_mux     <= pal0;
            half        <= 0;
        end else if(busy) begin
            waitok[0] <= 0;
            if( waitok[1] && rom_ok && rom2_ok ) begin
                pxw       <= { rom2_data, rom_data };
                pcnt      <= hf_mux ? 3'd7 : 3'd0;
                hotpxl    <= 8'h0;
                waitok[1] <= 0;
                rom_cs    <= 0;
            end else if(!waitok[1]) begin
                if( hotpxl[0])
                    line_addr <= line_addr + 9'd1;
                line_din  <= get_pxl(pxw, pcnt);
                line_we   <= 1;
                pcnt      <= hf_mux ? pcnt-3'd1 : pcnt+3'd1;
                hotpxl    <= { hotpxl[6:0], 1'b1 };
                if( hotpxl[7] ) begin
                    line_we <= 0;
                    if( half ) begin
                        busy    <= 0; // done
                    end else begin
                        waitok <= 2'b11;
                        code_mux <= code1;
                        hf_mux   <= hflip[1];
                        vf_mux   <= vflip[1];
                        pal_mux  <= pal1;
                        half     <= 1;
                        rom_cs   <= 1;
                    end
                end
            end
        end
    end
end

jtframe_dual_ram #(.AW(11),.SIMHEXFILE("vram0.hex")) u_ram0(
    .clk0   ( clk_cpu   ),
    .clk1   ( clk       ),
    // Port 0
    .data0  ( cpu_dout  ),
    .addr0  ( vram_addr ),
    .we0    ( vram_we[0]),
    .q0     ( vram0_dout),
    // Port 1
    .data1  (           ),
    .addr1  ( cbus      ),
    .we1    ( 1'b0      ),
    .q1     ( scan0_data)
);

jtframe_dual_ram #(.AW(11),.SIMHEXFILE("vram1.hex")) u_ram1(
    .clk0   ( clk_cpu   ),
    .clk1   ( clk       ),
    // Port 0
    .data0  ( cpu_dout  ),
    .addr0  ( vram_addr ),
    .we0    ( vram_we[1]),
    .q0     ( vram1_dout),
    // Port 1
    .data1  (           ),
    .addr1  ( cbus      ),
    .we1    ( 1'b0      ),
    .q1     ( scan1_data)
);

jtframe_dual_ram #(.AW(11),.SIMHEXFILE("vram2.hex")) u_ram2(
    .clk0   ( clk_cpu     ),
    .clk1   ( clk       ),
    // Port 0
    .data0  ( cpu_dout  ),
    .addr0  ( vram_addr ),
    .we0    ( vram_we[2]),
    .q0     ( vram2_dout),
    // Port 1
    .data1  (           ),
    .addr1  ( cbus      ),
    .we1    ( 1'b0      ),
    .q1     ( scan2_data)
);

jtframe_dual_ram #(.AW(11),.SIMHEXFILE("vram3.hex")) u_ram3(
    .clk0   ( clk_cpu     ),
    .clk1   ( clk       ),
    // Port 0
    .data0  ( cpu_dout  ),
    .addr0  ( vram_addr ),
    .we0    ( vram_we[3]),
    .q0     ( vram3_dout),
    // Port 1
    .data1  (           ),
    .addr1  ( cbus      ),
    .we1    ( 1'b0      ),
    .q1     ( scan3_data)
);

jtframe_prom #(.DW(4),.AW(8), .SIMFILE("a71-25.41")) u_prom(
    .clk    ( clk       ),
    .cen    ( 1'b1      ),
    .data   ( prog_data ),
    .rd_addr( dec_addr  ),
    .wr_addr( prog_addr ),
    .we     ( prom_we   ),
    .q      ( dec_dout  )
);

jtframe_obj_buffer #(.FLIP_OFFSET(9'h100),.ALPHAW(8),.ALPHA(32'hFF)) u_line(
    .clk    ( clk           ),
    .LHBL   ( LHBL          ),
    .flip   ( flip          ),
    // New data writes
    .wr_data( line_din      ),
    .wr_addr( line_addr     ),
    .we     ( line_we       ),
    // Old data reads (and erases)
    .rd_addr( hdump         ),
    .rd     ( pxl_cen       ),  // data will be erased after the rd event
    .rd_data( col_addr      )
);

endmodule