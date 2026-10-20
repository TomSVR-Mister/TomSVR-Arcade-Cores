/* SPDX-License-Identifier: GPL-3.0-or-later
   Taito TC0100SCN tilemap generator (standard 64x64 layout), from the MAME tc0100scn.cpp description.
   Two 4 bpp ROM layers with row scroll (layer 1 also with column scroll) and a 2 bpp text layer whose
   characters live in the chip RAM. Each layer is drawn one line ahead into its own line buffer.

   RAM (64 kB, in four 16 kB blocks so each layer has its own read port):
   0000-3fff BG0 map, 4000-5fff text map, 6000-6fff text characters, 8000-bfff BG1 map,
   c000-c3ff BG0 row scroll, c400-c7ff BG1 row scroll, e000-e0ff BG1 column scroll.
   Control: 0 BG0 X, 1 BG1 X, 2 text X, 3 BG0 Y, 4 BG1 Y, 5 text Y, 6 layer disable and order, 7 flip */

module jtothunder_scn(
    input             rst,
    input             clk,

    input      [ 8:0] vrender,
    input      [ 8:0] vdump,
    input      [ 8:0] rd_x,          // screen X being displayed

    input      [15:1] cpu_addr,
    input      [15:0] cpu_dout,
    input      [ 1:0] cpu_dsn,
    input             cpu_rnw,
    input             ram_cs,
    input             ctl_cs,
    output     [15:0] cpu_din,

    output     [18:2] bg0_addr,
    output            bg0_cs,
    input             bg0_ok,
    input      [31:0] bg0_data,

    output     [18:2] bg1_addr,
    output            bg1_cs,
    input             bg1_ok,
    input      [31:0] bg1_data,

    output     [11:0] bg0_pxl, bg1_pxl, txt_pxl,
    output     [ 3:0] layer_ctl      // 3 BG1 at the bottom, 2-0 text/BG1/BG0 disabled
);

reg  [15:0] ctrl[0:7];
reg  [15:0] ctl_dout, rs0, rs1;
reg  [ 8:0] vr_l;
reg  [ 3:0] fst;
reg  [12:0] sc_addr;
reg         start;
reg  [ 8:0] bg0_x0, bg0_y, bg1_x0, bg1_y, txt_x0, txt_y;
wire [ 8:0] rsidx = vrender - 9'd8;
wire [15:0] q0, q1, q2, q3, v0, v1, v2, v3, col_data;
wire [12:0] a0, a1, a2;
wire [ 5:0] col_addr;
wire [ 1:0] we = {2{ram_cs & ~cpu_rnw}} & ~cpu_dsn;
wire        col_we = cpu_addr[15:14]==3 && cpu_addr[13:8]==6'h20;   // e000-e0ff
integer     k;

assign layer_ctl = ctrl[6][3:0];
assign cpu_din   = ctl_cs ? ctl_dout :
                   cpu_addr[15:14]==0 ? q0 :
                   cpu_addr[15:14]==1 ? q1 :
                   cpu_addr[15:14]==2 ? q2 : q3;

always @(posedge clk) ctl_dout <= ctrl[cpu_addr[3:1]];

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        for( k=0; k<8; k=k+1 ) ctrl[k] <= 0;
    end else if( ctl_cs && !cpu_rnw ) begin
        if( !cpu_dsn[1] ) ctrl[cpu_addr[3:1]][15:8] <= cpu_dout[15:8];
        if( !cpu_dsn[0] ) ctrl[cpu_addr[3:1]][ 7:0] <= cpu_dout[ 7:0];
    end
end

// per line: read both row scroll values, then start the three layers
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        fst <= 0; start <= 0; vr_l <= 0;
    end else begin
        vr_l  <= vrender;
        start <= 0;
        case( fst )
            0: if( vr_l != vrender ) begin
                sc_addr <= { 4'b0000, rsidx };
                fst <= 1;
            end
            1: fst <= 2;
            2: begin
                rs0     <= v3;
                sc_addr <= { 4'b0001, rsidx };
                fst <= 3;
            end
            3: fst <= 4;
            4: begin
                rs1 <= v3;
                fst <= 5;
            end
            5: begin
                // MAME: src_x = x + 20 - scroll - rowscroll, src_y = y - 8 - scroll
                bg0_x0 <= 9'd20 - ctrl[0][8:0] - rs0[8:0];
                bg1_x0 <= 9'd20 - ctrl[1][8:0] - rs1[8:0];
                txt_x0 <= 9'd20 - ctrl[2][8:0];
                bg0_y  <= rsidx - ctrl[3][8:0];
                bg1_y  <= rsidx - ctrl[4][8:0];
                txt_y  <= rsidx - ctrl[5][8:0];
                fst    <= 6;
            end
            6: begin
                start <= 1;
                fst   <= 0;
            end
            default: fst <= 0;
        endcase
    end
end

jtframe_dual_ram16 #(.AW(13)) u_ram0(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( cpu_addr[13:1] ),
    .we0    ( cpu_addr[15:14]==0 ? we : 2'b0 ), .q0 ( q0 ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( a0 ), .we1 ( 2'b0 ), .q1 ( v0 )
);

jtframe_dual_ram16 #(.AW(13)) u_ram1(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( cpu_addr[13:1] ),
    .we0    ( cpu_addr[15:14]==1 ? we : 2'b0 ), .q0 ( q1 ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( a1 ), .we1 ( 2'b0 ), .q1 ( v1 )
);

jtframe_dual_ram16 #(.AW(13)) u_ram2(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( cpu_addr[13:1] ),
    .we0    ( cpu_addr[15:14]==2 ? we : 2'b0 ), .q0 ( q2 ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( a2 ), .we1 ( 2'b0 ), .q1 ( v2 )
);

jtframe_dual_ram16 #(.AW(13)) u_ram3(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( cpu_addr[13:1] ),
    .we0    ( cpu_addr[15:14]==3 ? we : 2'b0 ), .q0 ( q3 ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( sc_addr ), .we1 ( 2'b0 ), .q1 ( v3 )
);

// copy of the column scroll words, read by the BG1 layer
jtframe_dual_ram16 #(.AW(7)) u_col(
    .clk0   ( clk       ), .data0 ( cpu_dout ), .addr0 ( cpu_addr[7:1] ),
    .we0    ( col_we ? we : 2'b0 ), .q0 (  ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( {1'b0,col_addr} ), .we1 ( 2'b0 ), .q1 ( col_data )
);

jtothunder_scn_layer u_bg0(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .start      ( start     ),
    .wr_bank    ( vrender[0]),
    .rd_bank    ( vdump[0]  ),
    .map_x0     ( bg0_x0    ),
    .map_y      ( bg0_y     ),
    .rd_addr    ( rd_x      ),
    .vram_addr  ( a0        ),
    .vram_data  ( v0        ),
    .col_addr   (           ),
    .col_data   ( 16'd0     ),
    .rom_addr   ( bg0_addr  ),
    .rom_cs     ( bg0_cs    ),
    .rom_ok     ( bg0_ok    ),
    .rom_data   ( bg0_data  ),
    .pxl        ( bg0_pxl   )
);

jtothunder_scn_layer u_bg1(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .start      ( start     ),
    .wr_bank    ( vrender[0]),
    .rd_bank    ( vdump[0]  ),
    .map_x0     ( bg1_x0    ),
    .map_y      ( bg1_y     ),
    .rd_addr    ( rd_x      ),
    .vram_addr  ( a2        ),
    .vram_data  ( v2        ),
    .col_addr   ( col_addr  ),
    .col_data   ( col_data  ),
    .rom_addr   ( bg1_addr  ),
    .rom_cs     ( bg1_cs    ),
    .rom_ok     ( bg1_ok    ),
    .rom_data   ( bg1_data  ),
    .pxl        ( bg1_pxl   )
);

jtothunder_scn_layer #(.TXT(1)) u_txt(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .start      ( start     ),
    .wr_bank    ( vrender[0]),
    .rd_bank    ( vdump[0]  ),
    .map_x0     ( txt_x0    ),
    .map_y      ( txt_y     ),
    .rd_addr    ( rd_x      ),
    .vram_addr  ( a1        ),
    .vram_data  ( v1        ),
    .col_addr   (           ),
    .col_data   ( 16'd0     ),
    .rom_addr   (           ),
    .rom_cs     (           ),
    .rom_ok     ( 1'b0      ),
    .rom_data   ( 32'd0     ),
    .pxl        ( txt_pxl   )
);

endmodule
