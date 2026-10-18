`timescale 1ns/1ps
module tb;
reg clk=0, rst=1;
always #5 clk=~clk;
reg [7:0] hexmem[0:11595];
reg [7:0] okimem[0:262143];
initial begin $readmemh("bt_hex.mem", hexmem); $readmemh("oki.mem", okimem); end
reg hex_we=0, hex_first=0; reg [7:0] hex_data=0;
reg [7:0] latch=0; reg snd_wr=0;
reg [3:0] okc=0; wire cen_oki = okc==5;
always @(posedge clk) okc <= okc==5 ? 4'd0 : okc+1'd1;
wire [18:0] rom_addr; reg [7:0] rom_data; 
always @(posedge clk) rom_data <= okimem[rom_addr[17:0]];
wire signed [13:0] pcm;
reg cen_pic=0;
jtplaymark_sound uut(.rst(rst),.clk(clk),.cen_pic(cen_pic),.cen_oki(cen_oki),.nbank(2'd1),.hm(1'b0),
  .hex_we(hex_we),.hex_data(hex_data),.hex_first(hex_first),.latch(latch),.snd_wr(snd_wr),
  .rom_addr(rom_addr),.rom_data(rom_data),.rom_ok(1'b1),.pcm(pcm));
integer i, fd; reg [63:0] icnt=0;
reg [63:0] TLIM; reg [63:0] T1,T2,T3;
initial begin
  if(!$value$plusargs("TLIM=%d",TLIM)) TLIM=3000000;
  T1=64'd2793110; T2=64'd2896553; T3=64'd3000000;
  fd=$fopen("rtl.tr","w");
  for(i=0;i<11596;i=i+1) begin
    @(posedge clk); hex_we<=1; hex_data<=hexmem[i]; hex_first<= i==0;
    @(posedge clk); hex_we<=0;
  end
  repeat(10) @(posedge clk); rst<=0;
end
// one instruction per clock after reset
reg cc=0; always @(posedge clk) begin cc<=cc+1; cen_pic <= !rst && cc==0; end
always @(posedge clk) if(cen_pic) begin
  icnt <= icnt+1;
  if(!uut.u_pic.skip) $fdisplay(fd,"%03X: %03X W=%02X", uut.u_pic.pc, uut.u_pic.op, uut.u_pic.w);
  snd_wr <= 0;
  if(icnt==T1) begin latch<=8'hfe; snd_wr<=1; end
  if(icnt==T2) begin latch<=8'hfe; snd_wr<=1; end
  if(icnt==T3) begin latch<=8'h82; snd_wr<=1; end
  if(icnt>=TLIM) begin $fclose(fd); $finish; end
end
reg signed [13:0] pk=0; always @(posedge clk) if(pcm>pk) pk<=pcm;
always @(posedge clk) if(uut.u_pic.pc_wr && (uut.u_pic.pc_out&8'h38)==8'h18) $display("%0d OKI write %02X", icnt, uut.cmd);
always @(posedge clk) if(snd_wr) $display("%0d latch %02X", icnt, latch);
always @(posedge clk) if(uut.u_pic.pc_rd && uut.pend) $display("%0d latch ack", icnt);
always @(posedge clk) if(cen_pic && icnt==TLIM-1) $display("PCM peak %0d", pk);
endmodule
