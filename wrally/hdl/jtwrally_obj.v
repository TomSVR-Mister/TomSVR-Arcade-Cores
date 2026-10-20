/*  This file is part of JTWRALLY.
    SPDX-License-Identifier: GPL-3.0-or-later
    World Rally sprites (MAME gaelco_wrally_sprites.cpp), drawn line by line.
    Entry i (0-510) at words 3+4i: w0 y[7:0] flipx[14] flipy[15], w2 x[9:0] colour[13:10]
    shadow[14], w3 code[13:0]. Later sprites overwrite earlier ones. Shadow sprites only use
    pens 8-15 and OR their level into the pixel already in the line buffer, so the buffer is
    read-modified-written. Pixel format: [12:10] level, [9] shadow, [8] high priority
    (code >= 3700, as in MAME), [7:0] colour*16+pen. */

module jtwrally_obj(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             hs,
    input      [ 8:0] vdump,
    input      [ 8:0] hdump,

    output reg [10:0] spr_addr,
    input      [15:0] spr_dout,

    output reg [20:2] rom_addr,
    input      [31:0] rom_data,
    output reg        rom_cs,
    input             rom_ok,

    output reg [12:0] pxl
);

localparam [2:0] IDLE=0, SCAN=1, H1=2, H2=3, HAND=4;

// The scanner checks one entry per clock: the y word of entry aidx is requested every clock and
// tested two clocks later (RAM latency). A hit reads words 2 and 3, hands the sprite to the
// draw engine and resumes the scan after it, so scanning overlaps drawing.
reg  [ 2:0] st;
reg  [ 8:0] ln, hit, p1_idx, p2_idx;
reg  [ 9:0] aidx;               // next entry to request, bit 9 set = all requested
reg         p1_v, p2_v;
reg  [15:0] w0, w2;
reg         hs_l, start, wbank;
wire [ 7:0] sy   = 8'd240 - spr_dout[7:0];
wire [ 8:0] dy   = ln - { 1'b0, sy };
wire [ 7:0] syw  = 8'd240 - w0[7:0];
wire [ 8:0] dyw  = ln - { 1'b0, syw };
wire        offscr = w2[9:0] >= 10'h20f;   // every pixel lands at x >= 0x200: nothing to draw

// draw engine
reg  [13:0] dr_code;
reg  [ 3:0] dr_row, dr_col;
reg  [ 9:0] dr_sx;
reg         dr_eff, dr_hp, dr_xflip, dr_busy, dr_start, dr_half, dr_wait, nx_pend, nx_got;
reg  [31:0] dr_data, nx_data;
reg  [ 3:0] dr_k;
reg  [ 2:0] dr_st;

always @(posedge clk) begin
    hs_l  <= hs;
    start <= hs & ~hs_l;
end

// --- scanner
always @(posedge clk) begin
    if( rst ) begin
        st       <= IDLE;
        dr_start <= 0;
        wbank    <= 0;
        p1_v     <= 0;
        p2_v     <= 0;
    end else begin
        dr_start <= 0;
        if( start ) begin
            ln    <= vdump + 9'd1;
            aidx  <= 0;
            p1_v  <= 0;
            p2_v  <= 0;
            st    <= SCAN;
            wbank <= ~wbank;
        end else case( st )
            SCAN: begin
                spr_addr <= { aidx[8:0], 2'd3 };
                p1_idx   <= aidx[8:0];
                p1_v     <= !aidx[9];
                p2_idx   <= p1_idx;
                p2_v     <= p1_v;
                if( !aidx[9] ) aidx <= aidx==10'd510 ? 10'h200 : aidx + 10'd1;
                if( p2_v && dy < 9'd16 ) begin
                    hit      <= p2_idx;
                    w0       <= spr_dout;
                    spr_addr <= { p2_idx, 2'd3 } + 11'd2;
                    st       <= H1;
                end else if( !p1_v && !p2_v && aidx[9] ) st <= IDLE;
            end
            H1: begin spr_addr <= spr_addr + 11'd1; st <= H2; end
            H2: begin w2 <= spr_dout; st <= HAND; end
            HAND: if( offscr || (!dr_busy && !dr_start) ) begin
                if( !offscr ) begin
                    dr_code  <= spr_dout[13:0];
                    dr_hp    <= spr_dout[13:0] >= 14'h3700;
                    dr_row   <= dyw[3:0] ^ {4{w0[15]}};
                    dr_xflip <= w0[14];
                    dr_sx    <= w2[9:0];
                    dr_col   <= w2[13:10];
                    dr_eff   <= w2[14];
                    dr_start <= 1;
                end
                aidx <= hit==9'd510 ? 10'h200 : { 1'b0, hit } + 10'd1;
                p1_v <= 0;
                p2_v <= 0;
                st   <= SCAN;
            end
            default: st <= IDLE;
        endcase
    end
end

// --- line buffers: one being drawn (wbank), one being shown and cleared
reg  [12:0] mem0[0:511], mem1[0:511];
reg  [12:0] q0, q1, s2_new;
reg  [ 8:0] s2_x, disp_a;
wire [ 8:0] dr_ra;
reg         s2_on, s2_x9, cen_d, cen_dd;
reg  [ 3:0] s2_pen;
wire [12:0] dr_q   = wbank ? q1 : q0;
wire [12:0] disp_q = wbank ? q0 : q1;
reg         dr_we;
reg  [12:0] dr_wd;
wire [ 3:0] gfx_px = { dr_half, dr_k[2:0] };
wire [ 3:0] px     = gfx_px ^ {4{dr_xflip}};
wire [ 9:0] xpos   = (dr_sx + {6'd0,px}) - 10'h0f;
wire [ 2:0] bitn   = 3'd7 - dr_k[2:0];
assign dr_ra = xpos[8:0];
wire [ 3:0] pen    = { dr_data[{2'd3,bitn}], dr_data[{2'd2,bitn}], dr_data[{2'd1,bitn}], dr_data[{2'd0,bitn}] };

always @(posedge clk) begin
    q0 <= mem0[ wbank ? disp_a : dr_ra ];
    q1 <= mem1[ wbank ? dr_ra  : disp_a ];
    if( dr_we ) begin
        if( wbank ) mem1[s2_x] <= dr_wd; else mem0[s2_x] <= dr_wd;
    end
    if( cen_dd ) begin
        if( wbank ) mem0[disp_a] <= 13'd0; else mem1[disp_a] <= 13'd0;
    end
end

// pixel write, one clock after the read
always @* begin
    dr_we = 0;
    dr_wd = dr_q;
    if( s2_on && !s2_x9 ) begin
        if( !dr_eff ) begin
            dr_we = s2_pen != 0;
            dr_wd = { 3'd0, 1'b0, dr_hp, dr_col, s2_pen };
        end else if( s2_pen[3] ) begin
            dr_we = 1;
            dr_wd = dr_q != 0 ? dr_q | { s2_pen[2:0], 1'b1, 9'd0 } :
                                { s2_pen[2:0], 1'b1, dr_hp, 8'd0 };
        end
    end
end

// the right half of the sprite row is requested as soon as the left half arrives
always @(posedge clk) begin
    if( rst ) begin
        dr_busy <= 0;
        rom_cs  <= 0;
        s2_on   <= 0;
        dr_st   <= 0;
        nx_pend <= 0;
        nx_got  <= 0;
    end else begin
        s2_on   <= 0;
        dr_wait <= 0;
        if( nx_pend && rom_ok && !dr_wait ) begin
            nx_data <= rom_data;
            nx_got  <= 1;
            nx_pend <= 0;
            rom_cs  <= 0;
        end
        if( start ) begin
            dr_busy <= 0;
            rom_cs  <= 0;
            dr_st   <= 0;
            nx_pend <= 0;
            nx_got  <= 0;
        end else if( dr_start ) begin
            dr_busy  <= 1;
            dr_half  <= 0;
            rom_addr <= { dr_code, 1'b0, dr_row };
            rom_cs   <= 1;
            dr_wait  <= 1;
            dr_st    <= 1;
        end else case( dr_st )
            1: if( rom_ok && !dr_wait ) begin  // left half
                dr_data  <= rom_data;
                dr_k     <= 0;
                dr_st    <= 2;
                rom_addr <= { dr_code, 1'b1, dr_row };
                dr_wait  <= 1;
                nx_pend  <= 1;
                nx_got   <= 0;
            end
            2: begin // one pixel per clock
                s2_x   <= xpos[8:0];
                s2_x9  <= xpos[9];
                s2_pen <= pen;
                s2_on  <= 1;
                dr_k   <= dr_k + 4'd1;
                if( dr_k[2:0]==7 ) dr_st <= dr_half ? 3'd3 : 3'd4;
            end
            3: begin dr_busy <= 0; dr_st <= 0; end
            4: if( nx_got ) begin   // right half
                dr_data <= nx_data;
                dr_half <= 1;
                nx_got  <= 0;
                dr_k    <= 0;
                dr_st   <= 2;
            end
            default:;
        endcase
    end
end

// read out
always @(posedge clk) begin
    cen_d  <= pxl_cen;
    cen_dd <= cen_d;
    if( pxl_cen ) disp_a <= hdump;
    if( cen_dd  ) pxl <= disp_q;
end

`ifdef SIMULATION
// lines whose sprite scan or drawing was still going at the next HS
integer short_lines=0;
always @(posedge clk) if( start && (st!=IDLE || dr_busy) ) begin
    short_lines = short_lines + 1;
    if( short_lines < 20 || short_lines%200==0 )
        $display("OBJ short line %0d at entry %0d (total %0d)", ln, aidx, short_lines);
end
`endif

endmodule
