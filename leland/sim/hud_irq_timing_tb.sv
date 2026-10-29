// Execute the real Brute Force HUD ISR without booting the board or 80186.
// Only reset bootstrap bytes are substituted; the ISR at 0038/00be is original.
`timescale 1ns/1ps
module hud_irq_timing_tb;
reg clk=0; always #10.416667 clk=~clk;
reg reset_n=0, int_n=1;
reg [2:0] div=0;
wire cen=(div==0);
always @(posedge clk) div<=div+1'b1;
wire m1_n,mreq_n,iorq_n,rd_n,wr_n,rfsh_n,halt_n,busak_n;
wire [15:0] a;
wire [7:0] dout;
reg [7:0] mem[0:65535];
wire [7:0] din=(!iorq_n && !rd_n) ? 8'hff : mem[a];
tv80s_ce #(.Mode(0),.T2Write(1),.IOWait(1)) cpu(
 .clk(clk),.cen(cen),.reset_n(reset_n),.wait_n(1'b1),.int_n(int_n),
 .nmi_n(1'b1),.busrq_n(1'b1),.m1_n(m1_n),.mreq_n(mreq_n),
 .iorq_n(iorq_n),.rd_n(rd_n),.wr_n(wr_n),.rfsh_n(rfsh_n),
 .halt_n(halt_n),.busak_n(busak_n),.A(a),.di(din),.dout(dout));
integer fd,n,i,phase=0,scycles=0,irq_cycle=0;
reg started=0,io_seen=0;
initial begin
 n=$value$plusargs("IRQ_PHASE=%d",phase);
 for(i=0;i<65536;i=i+1) mem[i]=0;
 fd=$fopen("brutforc_fixedrom.bin","rb");
 if(!fd) $fatal(1,"Missing extracted fixed ROM");
 n=$fread(mem,fd);$fclose(fd);
 if(n!=8192) $fatal(1,"Wrong fixed ROM length %0d",n);
 // DI; LD SP,F7F0; IM 1; EI; HALT; JR -3 (resume HALT after RETI).
 mem[0]=8'hf3;mem[1]=8'h31;mem[2]=8'hf0;mem[3]=8'hf7;
 mem[4]=8'hed;mem[5]=8'h56;mem[6]=8'hfb;mem[7]=8'h76;
 mem[8]=8'h18;mem[9]=8'hfd;
 mem[16'he012]=8'hce;
 if($test$plusargs("WAVES")) begin $dumpfile("hud_irq_timing.vcd");$dumpvars;end
 repeat(32) @(negedge clk);reset_n=1;
 wait(!halt_n);
 repeat(40+phase) @(negedge clk);
 irq_cycle=scycles;started=1;int_n=0;
 $display("IRQ phase=%0d sys=%0d",phase,irq_cycle);
 repeat(12000) @(negedge clk);
 $fatal(1,"ISR timeout");
end
always @(posedge clk) begin
 scycles<=scycles+1;
 if(reset_n && cen) begin
  if(!mreq_n && !wr_n && rfsh_n) mem[a]<=dout;
  if(!iorq_n && !m1_n) int_n<=1;
  if(!iorq_n && !wr_n) begin
   if(!io_seen && started) begin
    $display("WRITE phase=%0d port=%02x data=%02x sys=%0d tstates=%0.3f pixels=%0.3f pc=%04x",
      phase,a[7:0],dout,scycles-irq_cycle,(scycles-irq_cycle)/8.0,
      (scycles-irq_cycle)*7159090.5/48000000.0,cpu.i_tv80_core.PC);
    if(a[7:0]==8'hf8) $finish;
   end
   io_seen<=1;
  end else io_seen<=0;
 end
end
endmodule
