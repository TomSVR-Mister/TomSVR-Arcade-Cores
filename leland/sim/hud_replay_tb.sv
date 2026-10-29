// Replay a Brute Force video snapshot and its HUD scroll writes. RTL is unmodified.
`timescale 1ns/1ps
import leland_board_pkg::*;
module hud_replay_tb;
reg clk=0; always #10.416 clk=~clk;
reg reset=1;
reg [26:0] pix_acc=0;
reg ce=0;
always @(posedge clk) begin
    if(pix_acc+27'd14318181>=27'd96000000) begin
        pix_acc<=pix_acc+27'd14318181-27'd96000000;ce<=1;
    end else begin pix_acc<=pix_acc+27'd14318181;ce<=0;end
end
wire hb,hs,vb,vs;
wire [23:0] rgb;
wire [16:0] va;
wire [15:0] qa;
wire [10:0] pa;
reg [7:0] vd,qd,pd;
reg [7:0] fg[0:131071],q[0:65535],pal[0:2047],gfx[0:1572863];
reg [7:0] prom[0:131071],byte_data=0,cd;
wire [9:0] ca;
integer game=1,bank=0;
wire req; reg ack=0;
wire [24:0] addr;
reg [15:0] d0=0,d1=0,d2=0;
reg [15:0] sx=16'h0530,sy=16'h0268;
reg req_d=0;
integer delay_count=0,idx=0,fd,n,k,frame=0;
reg busy=0;
reg [24:0] saved_addr;
integer mode=0,phase=0,latency=12;
function automatic bit at_pixel(input integer y,input integer x);
    at_pixel=(dut.vc*424+dut.hc)==(y*424+x+phase);
endfunction
initial begin
    n=$value$plusargs("MODE=%d",mode);
    n=$value$plusargs("GAME=%d",game);
    n=$value$plusargs("BANK=%d",bank);
    n=$value$plusargs("PHASE=%d",phase);
    n=$value$plusargs("LATENCY=%d",latency);
    if(game==0) begin sx=0; sy=0; end
    fd=$fopen("mame_fg.bin","rb"); n=$fread(fg,fd); $fclose(fd);
    if(game) begin fd=$fopen("mame_qram.bin","rb"); n=$fread(q,fd); $fclose(fd); end
    fd=$fopen("mame_palette.bin","rb"); n=$fread(pal,fd); $fclose(fd);
    fd=$fopen("gfx.bin","rb"); n=$fread(gfx,fd); $fclose(fd);
    if(n!=(game ? 1572864 : 98304)) $fatal(1,"missing gfx");
    if(game==0) begin fd=$fopen("prom.bin","rb"); n=$fread(prom,fd); $fclose(fd); end
    repeat(1500) @(posedge clk); reset=0;
end
always @(posedge clk) begin
    vd<=fg[va]; qd<=q[qa]; pd<=pal[pa]; cd<=pal[ca];
    req_d<=req; ack<=0;
    if(req && !req_d && !busy) begin saved_addr<=addr; busy<=1; delay_count<=latency; end
    else if(busy) begin
        if(delay_count==0) begin
            if(game) begin
                idx=(saved_addr-ADDR_GFX_BASE)>>3;
                d0<={gfx[262144+idx],gfx[idx]};
                d1<={gfx[786432+idx],gfx[524288+idx]};
                d2<={gfx[1310720+idx],gfx[1048576+idx]};
            end else if(saved_addr>=ADDR_PROM_BASE) byte_data<=prom[saved_addr-ADDR_PROM_BASE];
            else begin
                idx=(saved_addr-ADDR_GFXROW_BASE)>>2;
                d0<={gfx[32768+idx],gfx[idx]};
                d1<={8'd0,gfx[65536+idx]};
            end
            ack<=1; busy<=0;
        end else delay_count<=delay_count-1;
    end
end
leland_video dut(.clk_sys(clk),.reset(reset),.reset_cnt(reset),.ce_pix(ce),
    .HBlank(hb),.HSync(hs),.VBlank(vb),.VSync(vs),.rgb(rgb),
    .vram_addr(va),.vram_data(vd),.cram_addr(ca),.cram_data(cd),
    .ataxx_mode(game!=0),.gfx_wide(game!=0),.qram_addr(qa),.qram_data(qd),.pal_addr(pa),.pal_data(pd),
    .scroll_x(sx),.scroll_y(sy),.gfxbank(bank[7:0]),
    .sdram_rd2_req(req),.sdram_rd2_ack(ack),.sdram_rd2_addr(addr),.sdram_rd2_data(byte_data),
    .sdram_rd2_data16(d0),.sdram_rd2_data16_hi(d1),.sdram_rd2_data16_w2(d2),
    .fetch_busy(),.rbuf_count_out(),.raster_line());
always @(negedge clk) if(ce && !reset) begin
    // MODE=0: recorded writes; MODE=1: same final values at end of line 206.
    if(!game) begin
        if(mode==1) begin if(dut.vc==215 && dut.hc==320) begin sx=0;sy=16'h0600; end end
        else begin
            if(at_pixel(216,303)) sy[15:8]=6;
            if(at_pixel(216,321)) sy[7:0]=0;
        end
        if(dut.vc==248 && dut.hc==320) begin sx=0;sy=0;end
    end else if(mode==1) begin
        if(dut.vc==206 && dut.hc==320) begin sx=0; sy=16'h0310; end
    end else begin
        if(at_pixel(207,395)) sy[15:8]=3;
        if(at_pixel(207,417)) sy[7:0]=16;
        if(at_pixel(208,11)) sx[7:0]=0;
        if(at_pixel(208,24)) sx[15:8]=0;
    end
    if(game && dut.vc==240 && dut.hc==320) begin sx=16'h0530; sy=16'h0268; end
end
// Counterfactual: only the queued prefetched tiles are replaced with the desired
// tile/row at consumption. Keeps the original timing, palette and foreground.
// This is a simulation intervention to isolate queue provenance, not an RTL fix.
integer x,y,ex,ey,tile,gi,plane,slot;
always @(negedge clk) if((mode==3 || mode==4) && !reset && dut.fifo_pop) begin
    x=dut.hc; y=dut.vc;
    ex=(x+(game && y<208 ? 16'h0530 : 0))&2047;
    ey=(y+(game ? (y>=208 ? 16'h0310 : 16'h0268) : (y>=216 ? 16'h0600 : 0)))&2047;
    if(mode==4) begin ex=(x+sx)&2047;ey=(y+sy)&2047;end
    if(game) begin
        tile=((ey>>3)&127); tile=((tile&64)<<9)|((tile&63)<<8)|(ex>>3);
        gi=(q[tile]|((q[tile|16384]&127)<<8))*8+(ey&7);
    end else begin
        tile=((ey>>3)&255); tile=((tile&224)<<9)|((tile&31)<<8)|(ex>>3);
        plane=prom[tile|((bank&8)<<10)];
        gi=(plane|(((ey>>3)&192)<<2)|((bank&48)<<6))*8+(ey&7);
    end
    slot=dut.rbuf_rd;
    if(game) begin
        dut.rbuf_third0[slot]=gfx[gi]; dut.rbuf_third1[slot]=gfx[262144+gi];
        dut.rbuf_third2[slot]=gfx[524288+gi]; dut.rbuf_third3[slot]=gfx[786432+gi];
        dut.rbuf_third4[slot]=gfx[1048576+gi]; dut.rbuf_third5[slot]=gfx[1310720+gi];
    end else begin
        dut.rbuf_color[slot]=plane;
        dut.rbuf_third0[slot]=gfx[gi];dut.rbuf_third1[slot]=gfx[32768+gi];dut.rbuf_third2[slot]=gfx[65536+gi];
    end
end
reg [23:0] fb[0:76799];
reg hb_d=0,vb_d=0;
integer fx=0,fy=0,fi,ofd;
always @(posedge clk) if(ce && !reset) begin
    hb_d<=hb; vb_d<=vb;
    if(!hb && !vb && fx<320 && fy<240) begin fb[fy*320+fx]<=rgb; fx<=fx+1; end
    if(hb && !hb_d) begin fx<=0; if(!vb) fy<=fy+1; end
    if(vb && !vb_d) begin
        frame<=frame+1; fx<=0; fy<=0;
        if(frame==2) begin
            ofd=$fopen($sformatf("replay_mode%0d_phase%0d_lat%0d.ppm",mode,phase,latency),"wb");
            $fwrite(ofd,"P6\n320 240\n255\n");
            for(fi=0;fi<76800;fi=fi+1) $fwrite(ofd,"%c%c%c",fb[fi][23:16],fb[fi][15:8],fb[fi][7:0]);
            $fclose(ofd); $finish;
        end
    end
end
endmodule
