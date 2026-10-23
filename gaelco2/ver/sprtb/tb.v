`timescale 1ns/1ps
module tb;
reg clk=0; always #5.2 clk=~clk;   // 96 MHz
reg [15:0] vram[0:32767]; initial $readmemh("vram.hex", vram);
wire [14:0] spr_a; reg [15:0] spr_q; always @(posedge clk) spr_q <= vram[spr_a];
wire [21:0] rom_a; reg [21:0] la; reg ok=0; integer lat=0;
`ifndef LATV
`define LATV 10
`endif
localparam LAT=`LATV;   // SDRAM latency in 96 MHz clocks after an address change
always @(posedge clk) begin
    if( rom_a !== la ) begin la <= rom_a; lat <= 0; ok <= 0; end
    else if( lat < LAT ) lat <= lat+1; else ok <= 1;
end
wire okc = (rom_a===la) && (lat>=LAT);
reg start=0; reg [8:0] line=0; wire busy; integer t0, worst=0, wl=0, cyc;
aligator_gae1_sprite u(.clk(clk), .wide(1'b0), .tgw(1'b1), .dual(1'b1), .scr(1'b0), .ce(1'b1), .start(start), .line(line),
    .vreg0(16'h8c80), .vreg1(16'h8e10), .busy(busy), .spr_a(spr_a), .spr_q(spr_q), .rom_a(rom_a),
    .d_p0(8'h55), .d_p1(8'haa), .d_p2(8'h0f), .d_p3(8'hf0), .d_p4(8'h33), .gfx_ok(okc),
    .lb_x(9'd0), .lb_q(), .wbank(1'b0), .rbank(1'b1));
integer l; integer fo; initial fo=$fopen(`OUTF,"w");
initial begin
    for( l=16; l<256; l=l+1 ) begin
        @(posedge clk); line <= l; start <= 1; @(posedge clk); start <= 0; @(posedge clk);
        cyc=2; while( (busy===1'b1) && cyc<200000 ) begin @(posedge clk); cyc=cyc+1; end
        if( cyc>worst ) begin worst=cyc; wl=l; end
        begin : dump integer k; for(k=0;k<480;k=k+1) $fdisplay(fo, "%0d %0d %05x", l, k, u.lb0[k]); end
        if( l%8==0 || cyc>5600 ) $display("line %0d: %0d clocks", l, cyc);
    end
    $display("WORST line %0d: %0d clocks (budget about %0d)", wl, worst, 6160-20);
    $finish;
end
endmodule
