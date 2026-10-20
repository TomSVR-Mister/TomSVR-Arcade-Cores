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

localparam [2:0] IDLE=0, RD0=1, RD0W=2, RD2=3, RD2W=4, RD3W=5, HAND=6;

reg  [ 2:0] st;
reg  [ 8:0] ln, idx;
reg  [15:0] w0, w2;
reg         hs_l, start, wbank;
wire [ 7:0] sy   = 8'd240 - spr_dout[7:0];
wire [ 8:0] dy   = ln - { 1'b0, sy };
wire [ 7:0] syw  = 8'd240 - w0[7:0];
wire [ 8:0] dyw  = ln - { 1'b0, syw };

// draw engine
reg  [13:0] dr_code;
reg  [ 3:0] dr_row, dr_col;
reg  [ 9:0] dr_sx;
reg         dr_eff, dr_hp, dr_xflip, dr_busy, dr_start, dr_half, dr_wait;
reg  [31:0] dr_data;
reg  [ 3:0] dr_k;
reg  [ 1:0] dr_st;

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
    end else begin
        dr_start <= 0;
        if( start ) begin
            ln    <= vdump + 9'd1;
            idx   <= 0;
            st    <= RD0;
            wbank <= ~wbank;
        end else case( st )
            RD0: begin spr_addr <= { idx, 2'd3 }; st <= RD0W; end
            RD0W: st <= RD2;   // address registered by the RAM
            RD2: begin
                spr_addr <= spr_addr + 11'd2;
                w0 <= spr_dout;
                st <= dy < 9'd16 ? RD2W : HAND;
                if( dy >= 9'd16 ) begin
                    idx <= idx + 9'd1;
                    st  <= idx == 9'd510 ? IDLE : RD0;
                end
            end
            RD2W: begin spr_addr <= spr_addr + 11'd1; st <= RD3W; end
            RD3W: begin w2 <= spr_dout; st <= HAND; end
            HAND: if( !dr_busy && !dr_start ) begin
                dr_code  <= spr_dout[13:0];
                dr_hp    <= spr_dout[13:0] >= 14'h3700;
                dr_row   <= dyw[3:0] ^ {4{w0[15]}};
                dr_xflip <= w0[14];
                dr_sx    <= w2[9:0];
                dr_col   <= w2[13:10];
                dr_eff   <= w2[14];
                dr_start <= 1;
                idx      <= idx + 9'd1;
                st       <= idx == 9'd510 ? IDLE : RD0;
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

always @(posedge clk) begin
    if( rst ) begin
        dr_busy <= 0;
        rom_cs  <= 0;
        s2_on   <= 0;
        dr_st   <= 0;
    end else begin
        s2_on <= 0;
        if( start ) begin
            dr_busy <= 0;
            rom_cs  <= 0;
            dr_st   <= 0;
        end else if( dr_start ) begin
            dr_busy  <= 1;
            dr_half  <= 0;
            rom_addr <= { dr_code, 1'b0, dr_row };
            rom_cs   <= 1;
            dr_wait  <= 1;
            dr_st    <= 1;
        end else case( dr_st )
            1: begin // wait for ROM data
                dr_wait <= 0;
                if( rom_ok && !dr_wait ) begin
                    dr_data <= rom_data;
                    rom_cs  <= 0;
                    dr_k    <= 0;
                    dr_st   <= 2;
                end
            end
            2: begin // one pixel per clock
                s2_x   <= xpos[8:0];
                s2_x9  <= xpos[9];
                s2_pen <= pen;
                s2_on  <= 1;
                dr_k   <= dr_k + 4'd1;
                if( dr_k[2:0]==7 ) begin
                    if( !dr_half ) begin
                        dr_half  <= 1;
                        rom_addr <= { dr_code, 1'b1, dr_row };
                        rom_cs   <= 1;
                        dr_wait  <= 1;
                        dr_st    <= 1;
                    end else begin
                        dr_st   <= 3;
                    end
                end
            end
            3: begin dr_busy <= 0; dr_st <= 0; end
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

endmodule
