/* SPDX-License-Identifier: GPL-3.0-or-later
   Dynamite Duke sprites (MAME dynduke.cpp draw_sprites): 512 entries of 4 words, copied at V-blank.
     0: { -, flipy, flipx, colour[4:0], y[7:0] }   1: code[13:0]   2: { -, pri[1:0], -, x[8:0] signed }
     3: entry shown only when bits 15:8 are 0xF.
   16x16x4, pen 15 transparent. MAME marks every opaque sprite pixel as taken, so the lowest entry wins a pixel:
   the list is scanned 511..0 and later sprites overwrite earlier ones.
   Sprite ROM (LOAD16_BYTE pairs, 32-bit little endian rows): pixel j of a half-row takes, from bytes B0/B1
   (j<4) or B2/B3 (j>=4) at k = j%4, pen = { B1[3-k], B1[7-k], B0[3-k], B0[7-k] }. */

module jtdynduke_obj(
    input              rst,
    input              clk,
    input              pxl_cen,
    input              hs,
    input              vint,        // V-blank start: copy the sprite RAM
    input              en,
    input       [ 8:0] hdump,
    input       [ 8:0] vrender,

    output reg  [11:1] ram_addr,
    input       [15:0] ram_dout,

    output      [20:2] rom_addr,
    output             rom_cs,
    input       [31:0] rom_data,
    input              rom_ok,

    output      [10:0] pxl          // { pri, colour, pen }; pen 15 = transparent
);

parameter [8:0] DX = 9'd0;

localparam [2:0] IDLE=0, SCAN=1, RD1=2, RD2=3, RD3=4, RD4=5, DRAW=6;

reg  [ 2:0] st;
reg  [ 8:0] line;
reg  [ 8:0] hit, p1_idx, p2_idx;
reg  [ 9:0] aidx;             // next entry to address, counts down (bit 9 set = done)
reg         p1_v, p2_v;
reg         hs_l;
reg  [ 3:0] ydiff;
reg  [ 8:0] xpos;
reg  [13:0] code;
reg  [ 1:0] flip, pri;
reg  [ 4:0] color;
reg         draw;
wire        busy;
wire [31:0] sorted;
wire [15:0] buf_dout;
reg  [10:0] buf_addr;
wire [ 8:0] ydiff_nx = line - { 1'b0, buf_dout[7:0] };

// copy of the sprite RAM, made at V-blank: address, BRAM read, then write (two clocks behind)
reg  [11:0] cp_cnt;
reg  [10:0] cp_wa, cp_a1;
reg         cp_we, cp_v1, cp_on;

always @(posedge clk) begin
    if( rst ) begin
        cp_on <= 0; cp_v1 <= 0; cp_we <= 0; cp_cnt <= 0;
    end else begin
        ram_addr <= cp_cnt[10:0];
        cp_a1    <= cp_cnt[10:0];
        cp_v1    <= cp_on;
        cp_wa    <= cp_a1;
        cp_we    <= cp_v1;
        if( vint ) begin
            cp_on  <= 1;
            cp_cnt <= 0;
        end else if( cp_on ) begin
            cp_cnt <= cp_cnt + 1'd1;
            if( cp_cnt==12'h7ff ) cp_on <= 0;
        end
    end
end

jtframe_dual_ram16 #(.AW(11)) u_copy(
    .clk0   ( clk       ), .data0 ( ram_dout ), .addr0 ( cp_wa    ), .we0 ( {2{cp_we}} ), .q0 (          ),
    .clk1   ( clk       ), .data1 ( 16'd0    ), .addr1 ( buf_addr ), .we1 ( 2'b0       ), .q1 ( buf_dout )
);

function [3:0] pen( input [7:0] b0, input [7:0] b1, input [1:0] k );
    pen = { b1[3-k], b1[7-k], b0[3-k], b0[7-k] };
endfunction

// jtframe_draw wants { plane3, plane2, plane1, plane0 } with the leftmost pixel in each byte's LSB
genvar j;
generate
    for( j=0; j<8; j=j+1 ) begin : g_sort
        wire [3:0] p = j<4 ? pen( rom_data[ 7: 0], rom_data[15: 8], j%4 ) :
                             pen( rom_data[23:16], rom_data[31:24], j%4 );
        assign { sorted[24+j], sorted[16+j], sorted[8+j], sorted[j] } = p;
    end
endgenerate

always @(posedge clk) begin
    if( rst ) begin
        st   <= IDLE;
        draw <= 0;
        hs_l <= 0;
    end else begin
        hs_l <= hs;
        draw <= 0;
        case( st )
            IDLE: ;
            // Y words are requested every clock and checked two clocks later (BRAM latency)
            SCAN: begin
                buf_addr <= { aidx[8:0], 2'd0 };
                p1_idx   <= aidx[8:0];
                p1_v     <= !aidx[9];
                p2_idx   <= p1_idx;
                p2_v     <= p1_v;
                if( !aidx[9] ) aidx <= aidx - 1'd1;
                if( p2_v && ydiff_nx[8:4]==0 ) begin
                    ydiff    <= ydiff_nx[3:0];
                    flip     <= buf_dout[14:13];
                    color    <= buf_dout[12:8];
                    hit      <= p2_idx;
                    buf_addr <= { p2_idx, 2'd1 };
                    st       <= RD1;
                end else if( !p2_v && !p1_v && aidx[9] ) begin
                    st <= IDLE;
                end
            end
            RD1: begin buf_addr <= { hit, 2'd2 }; st <= RD2; end
            RD2: begin buf_addr <= { hit, 2'd3 }; code <= buf_dout[13:0]; st <= RD3; end
            RD3: begin xpos <= buf_dout[8:0]; pri <= buf_dout[14:13]; st <= RD4; end
            RD4: st <= buf_dout[15:8]==8'hf ? DRAW : SCAN;
            DRAW: if( !busy && !draw ) begin
                draw <= 1;
                st   <= SCAN;
            end
            default: st <= IDLE;
        endcase
        if( st==RD4 ) begin     // resume the scan below the hit, whether it is drawn or not
            aidx <= { 1'b0, hit } - 10'd1;
            p1_v <= 0;
            p2_v <= 0;
        end
        if( hs && !hs_l ) begin
            line <= vrender + 9'd1;   // shown after the next buffer swap (HS)
            aidx <= 10'd511;
            p1_v <= 0;
            p2_v <= 0;
            st   <= en ? SCAN : IDLE;
        end
    end
end

jtframe_objdraw #(.AW(9),.CW(14),.PW(11),.LATCH(1),.KEEP_OLD(0),.ALPHA(15),.HFIX(0)) u_draw(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .pxl_cen    ( pxl_cen       ),
    .hs         ( hs            ),
    .flip       ( 1'b0          ),
    .hdump      ( hdump         ),

    .draw       ( draw          ),
    .busy       ( busy          ),
    .code       ( code          ),
    .xpos       ( xpos + DX     ),
    .ysub       ( ydiff         ),
    .hzoom      ( 6'd0          ),
    .hz_keep    ( 1'b0          ),

    .hflip      ( flip[0]       ),
    .vflip      ( flip[1]       ),
    .pal        ( { pri, color } ),

    .rom_addr   ( rom_addr      ),
    .rom_cs     ( rom_cs        ),
    .rom_ok     ( rom_ok        ),
    .rom_data   ( sorted        ),

    .pxl        ( pxl           )
);

`ifdef SIMULATION
// lines whose sprite scan did not reach entry 0 before the next HS
integer short_lines=0;
always @(posedge clk) if( hs && !hs_l && en && st!=IDLE ) begin
    short_lines = short_lines + 1;
    if( short_lines < 50 || short_lines%500==0 )
        $display("OBJ short line %0d at entry %0d (total %0d)", line, aidx, short_lines);
end
`endif

endmodule
