/*  nss_rtc.sv - Seiko S-3520CF real-time clock of the NSS
 *
 *  Copyright (C) 2026 TomSVR. Written for the TomSVR NSS core.
 *  Serial protocol follows MAME src/devices/machine/s3520cf.cpp (Angelo Salese) and nocash fullsnes.
 *  GPL-3.0-or-later.
 *
 *  Z80 port 02 write: bit 3 /CLK (a bit moves on the clock going low), bit 2 data, bit 1 direction
 *  (0 = write), bit 0 /CS (1 = deselected, resets the bit counter). Port 03 read bit 0 = data out.
 *  Each 8 clocks carry {data nibble, register} LSB first; the data out is one byte behind (as MAME).
 *  The time comes from the MiSTer RTC at start and runs from a 1 Hz tick. Writes to the time digits
 *  advance them (S-3520 counter-adjust behaviour); the 15 bytes of user memory (modes 2/3) are kept.
 */
module nss_rtc (
    input             clk,           // 21.47727 MHz
    input             reset,
    input      [64:0] rtc,
    input             we,
    input       [7:0] din,
    output reg        dout
);

reg [7:0] sec, min, hour, day, mon, year;
reg [3:0] wday;
reg [1:0] mode;
reg       sysr;
reg [3:0] cntrl1, cntrl2;
reg [3:0] nv[32];

reg [7:0] bits;
reg [2:0] pos;
reg       clk_o;
reg       loaded;
reg [24:0] tick;
reg       rtc_t;

function [7:0] bcd_inc(input [7:0] v);
    bcd_inc = (v[3:0] == 4'd9) ? {v[7:4] + 1'd1, 4'd0} : v + 1'd1;
endfunction

function [3:0] rd(input [3:0] a);
    if (a == 4'hf) rd = {sysr, 1'b0, mode};
    else if (mode > 2'd1) rd = nv[{mode == 2'd3, a}];
    else case (a)
        4'h0: rd = sec[3:0];  4'h1: rd = sec[7:4];
        4'h2: rd = min[3:0];  4'h3: rd = min[7:4];
        4'h4: rd = hour[3:0]; 4'h5: rd = hour[7:4];
        4'h6: rd = wday;
        4'h7: rd = day[3:0];  4'h8: rd = day[7:4];
        4'h9: rd = mon[3:0];  4'ha: rd = mon[7:4];
        4'hb: rd = year[3:0]; 4'hc: rd = year[7:4];
        4'hd: rd = cntrl1;    4'he: rd = cntrl2;
        default: rd = 0;
    endcase
endfunction

wire [7:0] bits_n = {din[2], bits[7:1]};

always @(posedge clk) begin
    rtc_t <= rtc[64];
    // load the MiSTer time once it is valid (the RTC toggle bit changes)
    if (~loaded && rtc_t != rtc[64]) begin
        sec <= rtc[7:0]; min <= rtc[15:8]; hour <= rtc[23:16]; day <= rtc[31:24];
        mon <= rtc[39:32]; year <= rtc[47:40]; wday <= rtc[51:48]; loaded <= 1;
    end
    // 1 Hz
    if (tick == 25'd21477269) begin
        tick <= 0;
        if (sec == 8'h59) begin
            sec <= 0;
            if (min == 8'h59) begin
                min <= 0;
                if (hour == 8'h23) begin hour <= 0; wday <= (wday == 4'd6) ? 4'd0 : wday + 1'd1; day <= bcd_inc(day); end
                else hour <= bcd_inc(hour);
            end else min <= bcd_inc(min);
        end else sec <= bcd_inc(sec);
    end else tick <= tick + 1'd1;

    if (reset) begin
        pos <= 0; clk_o <= 1; mode <= 0;
    end else if (we) begin
        clk_o <= din[3];
        if (din[0]) pos <= 0;
        else if (clk_o & ~din[3]) begin
            dout <= bits[0];
            pos <= pos + 1'd1;
            if (pos == 3'd7) begin
                if (~din[1]) begin   // write
                    if (bits_n[3:0] == 4'hf) begin
                        mode <= bits_n[5:4]; sysr <= bits_n[7];
                    end else if (mode > 2'd1) nv[{mode == 2'd3, bits_n[3:0]}] <= bits_n[7:4];
                    else case (bits_n[3:0])
                        4'h0: sec  <= cntrl1[1] ? 8'd0 : bcd_inc(sec);
                        4'h1: sec  <= cntrl1[1] ? 8'd0 : sec + 8'h10;
                        4'h2: min  <= cntrl1[1] ? 8'd0 : bcd_inc(min);
                        4'h3: min  <= cntrl1[1] ? 8'd0 : min + 8'h10;
                        4'h4: hour <= cntrl1[1] ? 8'd0 : bcd_inc(hour);
                        4'h6: wday <= cntrl1[1] ? 4'd0 : wday + 1'd1;
                        4'h7: day  <= cntrl1[1] ? 8'd1 : bcd_inc(day);
                        4'h8: day  <= cntrl1[1] ? 8'd1 : day + 8'h10;
                        4'h9: mon  <= cntrl1[1] ? 8'd1 : bcd_inc(mon);
                        4'ha: mon  <= cntrl1[1] ? 8'd1 : mon + 8'h10;
                        4'hb: year <= cntrl1[1] ? {year[7:4], 4'd0} : bcd_inc(year);
                        4'hc: year <= cntrl1[1] ? {4'd0, year[3:0]} : year + 8'h10;
                        4'hd: cntrl1 <= bits_n[7:4];
                        4'he: cntrl2 <= bits_n[7:4];
                        default: ;
                    endcase
                end
                bits <= {rd(bits_n[3:0]), bits_n[3:0]};
            end else bits <= bits_n;
        end
    end
end

endmodule
