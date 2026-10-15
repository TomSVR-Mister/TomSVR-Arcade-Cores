/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 2-1-2025
 * Based on jtgaiden_objscan.v (jotego). Gals Pinball changes (2026 Tom Sveen):
 *  - 512-pixel wide screen: 10-bit X (MAME tecmo_spr xmask=512)
 *  - bootleg sprite chip: attribute bit 6 makes the sprite flicker (drawn every other frame)
 *    and bit 5 is the priority over the foreground tilemap (MAME galspnbl.cpp)
 *  - no sprite frame buffer, no independent vertical size */

module jtgalpin_objscan(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             flip,
    input             lvbl,
    input             hs,
    input             frame,        // toggles every frame (flicker)
    input      [ 8:0] vrender,
    input      [ 8:0] yoffset,

    // object RAM
    output     [11:1] ram_addr,
    input      [15:0] ram_dout,
    // rom address translation
    input      [19:2] raw_addr,
    output reg [19:2] rom_addr,
    // draw attributes and control
    output reg        hflip,
    output reg        vflip,
    output reg [12:0] code,
    output reg [ 3:0] pal,
    output reg        prio,
    output reg [ 9:0] hpos,
    output reg [ 3:0] ysub,
    output            dr_draw,
    input             dr_busy,
    output            obj8         // 8x8 sprite being drawn: only one 8-pixel column is valid
);

wire [12:1] scan_addr;
wire [ 8:0] vlatch;
wire [ 2:0] st, haddr, hsub;
reg  [ 2:0] hreps=0;
wire        draw_step, skip;
reg         en;
reg  [ 8:0] y;
reg  [ 9:0] x;
reg  [ 8:0] ydiff;
reg  [ 1:0] code_lsb;
wire [ 8:0] ydf;
reg  [ 7:0] attr;
reg  [ 3:0] pre_pal;
reg  [ 1:0] size, hsize, vaddr;
reg         inzone, hadj;

assign draw_step = st==5;
assign skip      = st==1 && !en;
assign ydf       = ydiff^{9{vflip}};
assign scan_addr[12] = 0;
assign ram_addr  = scan_addr[11:1];
assign obj8     = hsize==0;

always @* begin
    ydiff = vlatch - y - 9'd1;
    case( size )
        0: inzone = ydiff[8:3]==0; //   8
        1: inzone = ydiff[8:4]==0; //  16
        2: inzone = ydiff[8:5]==0; //  32
        3: inzone = ydiff[8:6]==0; //  64
    endcase
    case( haddr[1:0] )
        0: hadj = 0;
        1: hadj = 1;
        2: hadj = 1;
        3: hadj = 0;
    endcase
    hadj = hadj ^ hflip;
end

always @* begin
    rom_addr = {raw_addr[19:7],raw_addr[5],~raw_addr[6],raw_addr[4:2]};
    // 8x8 sprites are drawn as 16-pixel wide objects whose second column is blanked (jtgalpin_obj),
    // so the tile goes 8 pixels to the left when mirrored
    hpos     = x + {3'd0,hsub,4'd0} - ((size==0 && attr[0]) ? 10'd8 : 10'd0);
    case( hsize )
        0: rom_addr[6:5]  = code_lsb;   // full 8x8 tile number (MAME tecmo_spr)
        2: rom_addr[ 8:7] = {vaddr[0],haddr[0]};     //32
        3: rom_addr[10:7] = {vaddr[1],hadj,vaddr[0],haddr[0]};   //64
        default:;
    endcase
end

always @(posedge clk) begin
    case(st)
        0: begin
            en   <= scan_dout_en(ram_dout);
            attr <= ram_dout[7:0];
        end
        1: {code,code_lsb} <= ram_dout[14:0];
        2: {pre_pal,size} <= {ram_dout[7:4],ram_dout[1:0]};
        3: begin
            y <= ram_dout[8:0]+yoffset;
            case(size)
                0,1: hreps <=0; // single tile
                2:   hreps <=1; // 16x2=32
                3:   hreps <=3; // 16x4=64
            endcase
        end
        4: x <= ram_dout[9:0];
        5: if(!dr_busy && inzone) begin
            pal   <=  pre_pal;
            hsize <=  size;
            ysub  <=  ydf[3:0]^{4{attr[1]}};
            vaddr <=  ydf[5:4];
            prio  <=  attr[5];
            vflip <=  attr[1];
            hflip <= ~attr[0];
        end
    endcase
end

function scan_dout_en( input [15:0] a );
    scan_dout_en = a[2] && !(a[6] && frame);
endfunction

jtframe_objscan #(.OBJW(8),.STW(3))u_scan(
    .clk        ( clk       ),
    .cen        (           ),
    .hs         ( hs        ),
    .blankn     ( 1'b1      ),
    .vrender    ( vrender   ),
    .vlatch     ( vlatch    ),

    .draw_step  ( draw_step ),
    .skip       ( skip      ),
    .inzone     ( inzone    ),

    .hsize      ( hreps     ),
    .hsub       ( hsub      ),
    .haddr      ( haddr     ),
    .hflip      ( hflip     ),
    .hcnt_nx    (           ),

    .dr_busy    ( dr_busy   ),
    .dr_draw    ( dr_draw   ),

    .addr       ( scan_addr[11:1] ),
    .step       ( st        )
);

endmodule
