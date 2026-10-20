/*  This file is part of JTXEXEX.
    SPDX-License-Identifier: GPL-3.0-or-later
    Konami K054539 PCM sound chip, written from MAME's k054539.cpp (Olivier Galibert et al.).
    8 channels of 8-bit PCM, 16-bit PCM or 4-bit DPCM with reverse play and loops, per-channel
    volume, pan and reverb send into a 8k x 16 delay RAM. Channels are processed one after the
    other once per sample (clock/384 = 48 kHz).
    Not modelled: the timer output (0x227) and the analogue pan callback (0x13f). */

module jtxexex_k539(
    input                rst,
    input                clk,
    input                sample,     // 48 kHz strobe
    // CPU
    input         [ 9:0] addr,
    input         [ 7:0] din,
    output reg    [ 7:0] dout,
    input                cs,
    input                wr,         // one clock per write
    input                rd,         // one clock per read (data port side effects)
    // sample ROM
    output reg    [23:0] rom_addr,
    output reg           rom_cs,
    input         [ 7:0] rom_data,
    input                rom_ok,
    // sound
    output reg signed [15:0] left,
    output reg signed [15:0] right
);

function [14:0] voltab(input [7:0] v);
    case(v)
        8'd0: voltab = 15'd16384;
        8'd1: voltab = 15'd15357;
        8'd2: voltab = 15'd14394;
        8'd3: voltab = 15'd13491;
        8'd4: voltab = 15'd12645;
        8'd5: voltab = 15'd11852;
        8'd6: voltab = 15'd11109;
        8'd7: voltab = 15'd10412;
        8'd8: voltab = 15'd9759;
        8'd9: voltab = 15'd9147;
        8'd10: voltab = 15'd8574;
        8'd11: voltab = 15'd8036;
        8'd12: voltab = 15'd7532;
        8'd13: voltab = 15'd7060;
        8'd14: voltab = 15'd6617;
        8'd15: voltab = 15'd6202;
        8'd16: voltab = 15'd5813;
        8'd17: voltab = 15'd5449;
        8'd18: voltab = 15'd5107;
        8'd19: voltab = 15'd4787;
        8'd20: voltab = 15'd4487;
        8'd21: voltab = 15'd4205;
        8'd22: voltab = 15'd3942;
        8'd23: voltab = 15'd3694;
        8'd24: voltab = 15'd3463;
        8'd25: voltab = 15'd3246;
        8'd26: voltab = 15'd3042;
        8'd27: voltab = 15'd2851;
        8'd28: voltab = 15'd2673;
        8'd29: voltab = 15'd2505;
        8'd30: voltab = 15'd2348;
        8'd31: voltab = 15'd2201;
        8'd32: voltab = 15'd2063;
        8'd33: voltab = 15'd1933;
        8'd34: voltab = 15'd1812;
        8'd35: voltab = 15'd1698;
        8'd36: voltab = 15'd1592;
        8'd37: voltab = 15'd1492;
        8'd38: voltab = 15'd1399;
        8'd39: voltab = 15'd1311;
        8'd40: voltab = 15'd1229;
        8'd41: voltab = 15'd1152;
        8'd42: voltab = 15'd1079;
        8'd43: voltab = 15'd1012;
        8'd44: voltab = 15'd948;
        8'd45: voltab = 15'd889;
        8'd46: voltab = 15'd833;
        8'd47: voltab = 15'd781;
        8'd48: voltab = 15'd732;
        8'd49: voltab = 15'd686;
        8'd50: voltab = 15'd643;
        8'd51: voltab = 15'd603;
        8'd52: voltab = 15'd565;
        8'd53: voltab = 15'd529;
        8'd54: voltab = 15'd496;
        8'd55: voltab = 15'd465;
        8'd56: voltab = 15'd436;
        8'd57: voltab = 15'd409;
        8'd58: voltab = 15'd383;
        8'd59: voltab = 15'd359;
        8'd60: voltab = 15'd336;
        8'd61: voltab = 15'd315;
        8'd62: voltab = 15'd296;
        8'd63: voltab = 15'd277;
        8'd64: voltab = 15'd260;
        8'd65: voltab = 15'd243;
        8'd66: voltab = 15'd228;
        8'd67: voltab = 15'd214;
        8'd68: voltab = 15'd200;
        8'd69: voltab = 15'd188;
        8'd70: voltab = 15'd176;
        8'd71: voltab = 15'd165;
        8'd72: voltab = 15'd155;
        8'd73: voltab = 15'd145;
        8'd74: voltab = 15'd136;
        8'd75: voltab = 15'd127;
        8'd76: voltab = 15'd119;
        8'd77: voltab = 15'd112;
        8'd78: voltab = 15'd105;
        8'd79: voltab = 15'd98;
        8'd80: voltab = 15'd92;
        8'd81: voltab = 15'd86;
        8'd82: voltab = 15'd81;
        8'd83: voltab = 15'd76;
        8'd84: voltab = 15'd71;
        8'd85: voltab = 15'd67;
        8'd86: voltab = 15'd62;
        8'd87: voltab = 15'd59;
        8'd88: voltab = 15'd55;
        8'd89: voltab = 15'd51;
        8'd90: voltab = 15'd48;
        8'd91: voltab = 15'd45;
        8'd92: voltab = 15'd42;
        8'd93: voltab = 15'd40;
        8'd94: voltab = 15'd37;
        8'd95: voltab = 15'd35;
        8'd96: voltab = 15'd33;
        8'd97: voltab = 15'd31;
        8'd98: voltab = 15'd29;
        8'd99: voltab = 15'd27;
        8'd100: voltab = 15'd25;
        8'd101: voltab = 15'd24;
        8'd102: voltab = 15'd22;
        8'd103: voltab = 15'd21;
        8'd104: voltab = 15'd19;
        8'd105: voltab = 15'd18;
        8'd106: voltab = 15'd17;
        8'd107: voltab = 15'd16;
        8'd108: voltab = 15'd15;
        8'd109: voltab = 15'd14;
        8'd110: voltab = 15'd13;
        8'd111: voltab = 15'd12;
        8'd112: voltab = 15'd12;
        8'd113: voltab = 15'd11;
        8'd114: voltab = 15'd10;
        8'd115: voltab = 15'd10;
        8'd116: voltab = 15'd9;
        8'd117: voltab = 15'd8;
        8'd118: voltab = 15'd8;
        8'd119: voltab = 15'd7;
        8'd120: voltab = 15'd7;
        8'd121: voltab = 15'd6;
        8'd122: voltab = 15'd6;
        8'd123: voltab = 15'd6;
        8'd124: voltab = 15'd5;
        8'd125: voltab = 15'd5;
        8'd126: voltab = 15'd5;
        8'd127: voltab = 15'd4;
        8'd128: voltab = 15'd4;
        8'd129: voltab = 15'd4;
        8'd130: voltab = 15'd4;
        8'd131: voltab = 15'd3;
        8'd132: voltab = 15'd3;
        8'd133: voltab = 15'd3;
        8'd134: voltab = 15'd3;
        8'd135: voltab = 15'd3;
        8'd136: voltab = 15'd2;
        8'd137: voltab = 15'd2;
        8'd138: voltab = 15'd2;
        8'd139: voltab = 15'd2;
        8'd140: voltab = 15'd2;
        8'd141: voltab = 15'd2;
        8'd142: voltab = 15'd2;
        8'd143: voltab = 15'd2;
        8'd144: voltab = 15'd1;
        8'd145: voltab = 15'd1;
        8'd146: voltab = 15'd1;
        8'd147: voltab = 15'd1;
        8'd148: voltab = 15'd1;
        8'd149: voltab = 15'd1;
        8'd150: voltab = 15'd1;
        8'd151: voltab = 15'd1;
        8'd152: voltab = 15'd1;
        8'd153: voltab = 15'd1;
        8'd154: voltab = 15'd1;
        8'd155: voltab = 15'd1;
        8'd156: voltab = 15'd1;
        8'd157: voltab = 15'd1;
        8'd158: voltab = 15'd1;
        8'd159: voltab = 15'd1;
        8'd160: voltab = 15'd1;
        default: voltab = 15'd0;
    endcase
endfunction

function [16:0] pantab(input [3:0] p);
    case(p)
        4'd0: pantab = 17'd0;
        4'd1: pantab = 17'd17515;
        4'd2: pantab = 17'd24770;
        4'd3: pantab = 17'd30337;
        4'd4: pantab = 17'd35030;
        4'd5: pantab = 17'd39165;
        4'd6: pantab = 17'd42903;
        4'd7: pantab = 17'd46341;
        4'd8: pantab = 17'd49541;
        4'd9: pantab = 17'd52546;
        4'd10: pantab = 17'd55388;
        4'd11: pantab = 17'd58091;
        4'd12: pantab = 17'd60675;
        4'd13: pantab = 17'd63152;
        4'd14: pantab = 17'd65536;
        default: pantab = 17'd0;
    endcase
endfunction

// ---------------- registers
reg  [ 7:0] regs[0:1023];       // CPU visible registers
reg  [23:0] posreg[0:7];        // channel positions (xC-xE), also written back by the sample loop
reg  [23:0] poslatch[0:7];
reg  [ 7:0] keyon, ctrl, romsel;
reg  [16:0] cur_ptr;
wire        regupdate = ~ctrl[7];
wire [ 2:0] wch = addr[7:5];
wire [ 4:0] woff = addr[4:0];
wire        is_pos = addr[9:8]==0 && woff>=5'hc && woff<=5'he;
wire        latch = ctrl[0];   // UPDATE_AT_KEYON is MAME's default
wire        dport  = cs && addr==10'h22d;

reg  [ 7:0] keyoff_req;      // from the sample loop
reg         pos_we;
reg  [ 2:0] pos_ch;
reg  [23:0] pos_wd;

integer k;
always @(posedge clk) begin
    if( rst ) begin
        keyon   <= 0;
        ctrl    <= 0;
        romsel  <= 0;
        cur_ptr <= 0;
        for( k=0; k<8; k=k+1 ) begin posreg[k] <= 0; poslatch[k] <= 0; end
    end else begin
        if( pos_we ) posreg[pos_ch] <= pos_wd;
        if( regupdate ) keyon <= keyon & ~keyoff_req;
        if( cs && wr ) begin
            if( is_pos && latch ) begin
                case( woff[1:0] )
                    0: poslatch[wch][ 7: 0] <= din;
                    1: poslatch[wch][15: 8] <= din;
                    2: poslatch[wch][23:16] <= din;
                    default:;
                endcase
            end else begin
                if( is_pos ) case( woff[1:0] )
                    0: posreg[wch][ 7: 0] <= din;
                    1: posreg[wch][15: 8] <= din;
                    2: posreg[wch][23:16] <= din;
                    default:;
                endcase
                regs[addr] <= din;
            end
            case( addr )
                10'h214: for( k=0; k<8; k=k+1 ) if( din[k] ) begin
                    if( latch ) posreg[k] <= poslatch[k];
                    if( regupdate ) keyon[k] <= 1;
                end
                10'h215: for( k=0; k<8; k=k+1 ) if( din[k] && regupdate ) keyon[k] <= 0;
                10'h22c: keyon   <= din;
                10'h22d: cur_ptr <= cur_ptr + 1'd1;
                10'h22e: begin romsel <= din; cur_ptr <= 0; end
                10'h22f: ctrl    <= din;
                default:;
            endcase
        end
        if( dport && rd && ctrl[4] ) cur_ptr <= cur_ptr + 1'd1;
    end
end

// reverb RAM, 16k x 16. Port 0: sample loop, port 1: CPU data port (0x22d)
wire [14:0] cpu_ram_a = { cur_ptr[16], cur_ptr[13:0] };
wire [15:0] cpu_q, rv_q;
reg  [12:0] rv_a;
reg  [15:0] rv_d;
reg  [ 1:0] rv_we;

jtframe_dual_ram16 #(.AW(14)) u_rvb(
    .clk0   ( clk               ),
    .data0  ( rv_d              ),
    .addr0  ( { 1'b0, rv_a }    ),
    .we0    ( rv_we             ),
    .q0     ( rv_q              ),
    .clk1   ( clk               ),
    .data1  ( { din, din }      ),
    .addr1  ( cpu_ram_a[14:1]   ),
    .we1    ( {2{dport & wr & romsel==8'h80}} & (cpu_ram_a[0] ? 2'b10 : 2'b01) ),
    .q1     ( cpu_q             )
);

// CPU read
always @(posedge clk) begin
    if( is_pos )
        dout <= woff[1:0]==0 ? posreg[wch][7:0] : woff[1:0]==1 ? posreg[wch][15:8] : posreg[wch][23:16];
    else if( addr==10'h22c ) dout <= keyon;
    else if( addr==10'h22d ) dout <= !ctrl[4] || romsel!=8'h80 ? 8'd0 : cpu_ram_a[0] ? cpu_q[15:8] : cpu_q[7:0];
    else if( addr==10'h22f ) dout <= ctrl;
    else dout <= regs[addr];
end

// register read port for the sample loop
reg  [ 9:0] fa;
reg  [ 7:0] fq;
always @(posedge clk) fq <= regs[fa];

// ---------------- sample loop (follows k054539_device::sound_stream_update)
localparam [4:0] IDLE=0, RVB0=1, RVB1=2, CHAN=3, RD=4, RDW=5, SETUP=6, PREP=7, LOOP=8,
                 RQ=9, RQW=10, RQD=11, GOT=12, POST=13, MIX=14, RVW=15, NEXT=16, DONE=17;

reg  [23:0] ch_pos[0:7];
reg  [15:0] ch_frac[0:7];
reg  signed [15:0] ch_val[0:7], ch_pval[0:7];

reg  [ 4:0] st;
reg  [ 2:0] ch;
reg  [ 3:0] ri;
reg  [ 7:0] r[0:12];        // 0-10 channel registers 0-A, 11-12 channel mode registers
reg  [12:0] rpos;
reg  signed [35:0] accl, accr;
reg  signed [31:0] cpos, frac, sdelta, fdelta, pdelta;
reg  signed [15:0] cval, cpval;
reg         dpcm, b16, looped, hibyte, pend;
reg  [ 7:0] blo, bq;
reg  [15:0] lvol, rvol, rbvol;
reg  [12:0] rv_idx;

wire [ 3:0] mode   = r[11][3:0];
wire [23:0] delta  = { r[2], r[1], r[0] };
wire [ 8:0] bsum   = { 1'b0, r[3] } + { 1'b0, r[4] };
wire [ 3:0] pan    = (r[5]>=8'h81 && r[5]<=8'h8f) ? r[5][3:0]-4'd1 :
                     (r[5]>=8'h11 && r[5]<=8'h1f) ? r[5][3:0]-4'd1 : 4'd7;
wire [23:0] loop_pos = { r[10], r[9], r[8] };
wire [15:0] rd_raw = { r[7], r[6] } >> 3;
wire [12:0] rdelta = rd_raw[12:0] + rpos;     // ((x>>3) + pos) + pos, masked to 13 bits
wire [31:0] lv_full = voltab(r[3]) * pantab(pan);
wire [31:0] rv_full = voltab(r[3]) * pantab(4'he-pan);
wire [ 3:0] nib     = cpos[0] ? bq[7:4] : bq[3:0];
wire signed [15:0] dstep = dpcm_t(nib);
wire signed [16:0] dsum = { cpval[15], cpval } + { dstep[15], dstep };
wire signed [31:0] pl = cval * $signed({1'b0,lvol});
wire signed [31:0] pr = cval * $signed({1'b0,rvol});
wire signed [31:0] pb = cval * $signed({1'b0,rbvol});
wire signed [31:0] pbn = -pb;
wire        [15:0] pbn_hi = pbn[31:16];
wire signed [15:0] rvsend = pb[31] ? -pbn_hi : pb[31:16];  // C cast truncates toward zero

function signed [15:0] dpcm_t(input [3:0] n);
    case(n)
        4'd0, 4'd8: dpcm_t = 0;
        4'd1: dpcm_t = 16'sh100;  4'd2: dpcm_t = 16'sh200;  4'd3: dpcm_t = 16'sh400;
        4'd4: dpcm_t = 16'sh800;  4'd5: dpcm_t = 16'sh1000; 4'd6: dpcm_t = 16'sh2000;
        4'd7: dpcm_t = 16'sh4000;
        4'd9: dpcm_t = -16'sh4000; 4'd10: dpcm_t = -16'sh2000; 4'd11: dpcm_t = -16'sh1000;
        4'd12: dpcm_t = -16'sh800; 4'd13: dpcm_t = -16'sh400;  4'd14: dpcm_t = -16'sh200;
        4'd15: dpcm_t = -16'sh100;
    endcase
endfunction

function signed [15:0] clip(input signed [19:0] v);
    clip = v > 20'sd32767 ? 16'sh7fff : v < -20'sd32768 ? -16'sh8000 : v[15:0];
endfunction

wire [9:0] fa_next = ri<4'd10 ? { 2'b00, ch, 1'b0, ri+4'd1 } : { 6'b1000_00, ch, ri==4'd11 };

always @(posedge clk) begin
    if( rst ) begin
        st         <= IDLE;
        rpos       <= 0;
        rom_cs     <= 0;
        keyoff_req <= 0;
        pos_we     <= 0;
        rv_we      <= 0;
        left       <= 0;
        right      <= 0;
        pend       <= 0;
        hibyte     <= 0;
        for( k=0; k<8; k=k+1 ) begin
            ch_pos[k] <= 0; ch_frac[k] <= 0; ch_val[k] <= 0; ch_pval[k] <= 0;
        end
    end else begin
        keyoff_req <= 0;
        pos_we     <= 0;
        rv_we      <= 0;
        if( sample ) pend <= 1;
        case( st )
            IDLE: if( pend ) begin
                pend <= 0;
                if( ctrl[0] ) begin
                    rv_a <= rpos;
                    st   <= RVB0;
                end
            end
            RVB0: st <= RVB1;
            RVB1: begin
                accl  <= { {4{rv_q[15]}}, rv_q, 16'd0 };
                accr  <= { {4{rv_q[15]}}, rv_q, 16'd0 };
                rv_d  <= 0;
                rv_we <= 2'b11;
                ch    <= 0;
                st    <= CHAN;
            end
            CHAN: begin
                ri <= 0;
                fa <= { 2'b00, ch, 5'd0 };
                st <= keyon[ch] ? RD : NEXT;
            end
            RD: st <= RDW;
            RDW: begin
                r[ri] <= fq;
                fa    <= fa_next;
                ri    <= ri + 4'd1;
                st    <= ri==4'd12 ? SETUP : RD;
            end
            SETUP: begin
                dpcm   <= mode[3:2]==2'b10;
                b16    <= mode[3:2]==2'b01;
                sdelta <= r[11][5] ? -{8'd0,delta} : {8'd0,delta};
                fdelta <= r[11][5] ? 32'sh10000 : -32'sh10000;
                pdelta <= (r[11][5] ? -32'sd1 : 32'sd1) <<< (mode[3:2]==2'b01 ? 1 : 0);
                cpos   <= { 8'd0, posreg[ch] };
                if( posreg[ch] != ch_pos[ch] ) begin
                    frac <= 0; cval <= 0; cpval <= 0;
                end else begin
                    frac <= { 16'd0, ch_frac[ch] }; cval <= ch_val[ch]; cpval <= ch_pval[ch];
                end
                lvol   <= lv_full[31:16];
                rvol   <= rv_full[31:16];
                rbvol  <= { 1'b0, voltab(bsum[8] ? 8'hff : bsum[7:0]) } >> 1;
                rv_idx <= rdelta + rpos;
                st     <= mode[3] & mode[2] ? NEXT : PREP; // unknown type: channel skipped
            end
            PREP: begin
                if( dpcm ) begin
                    cpos <= { cpos[30:0], frac[15] };
                    frac <= { 16'd0, frac[14:0], 1'b0 } + sdelta;
                end else begin
                    frac <= frac + sdelta;
                end
                st <= LOOP;
            end
            LOOP: begin
                if( frac[31:16]==0 ) st <= POST;
                else begin
                    frac   <= frac + fdelta;
                    cpos   <= cpos + pdelta;
                    cpval  <= cval;
                    looped <= 0;
                    st     <= RQ;
                end
            end
            RQ: begin   // ROM request
                rom_addr <= dpcm ? cpos[24:1] : hibyte ? cpos[23:0]+24'd1 : cpos[23:0];
                rom_cs   <= 1;
                st       <= RQW;
            end
            RQW: st <= RQD;     // give the ROM interface a clock to drop ok
            RQD: if( rom_ok ) begin
                rom_cs <= 0;
                if( b16 && !hibyte ) begin
                    blo    <= rom_data;
                    hibyte <= 1;
                    st     <= RQ;
                end else begin
                    bq     <= rom_data;
                    hibyte <= 0;
                    st     <= GOT;
                end
            end
            GOT: begin
                if( dpcm ? bq==8'h88 : (b16 ? {bq,blo} : {bq,8'd0})==16'h8000 ) begin
                    if( r[12][0] && !looped ) begin
                        looped <= 1;
                        cpos   <= dpcm ? { 7'd0, loop_pos, 1'b0 } : { 8'd0, loop_pos };
                        st     <= RQ;
                    end else begin
                        keyoff_req[ch] <= 1;
                        cval <= 0;
                        st   <= POST;
                    end
                end else begin
                    cval <= dpcm ? clip( { {3{dsum[16]}}, dsum } ) : b16 ? { bq, blo } : { bq, 8'd0 };
                    st   <= LOOP;
                end
            end
            POST: begin
                if( dpcm ) begin
                    frac <= { 16'd0, cpos[0], frac[15:1] };
                    cpos <= cpos >>> 1;
                end
                rv_a <= rv_idx;
                st   <= MIX;
            end
            MIX: begin
                accl <= accl + {{4{pl[31]}}, pl};
                accr <= accr + {{4{pr[31]}}, pr};
                st   <= RVW;
            end
            RVW: begin  // rv_q is valid for rv_idx now
                rv_d  <= rv_q + rvsend;
                rv_we <= 2'b11;
                ch_pos[ch]  <= cpos[23:0];
                ch_frac[ch] <= frac[15:0];
                ch_val[ch]  <= cval;
                ch_pval[ch] <= cpval;
                pos_we <= regupdate;
                pos_ch <= ch;
                pos_wd <= cpos[23:0];
                st     <= NEXT;
            end
            NEXT: begin
                ch <= ch + 3'd1;
                st <= ch==3'd7 ? DONE : CHAN;
            end
            DONE: begin
                left  <= clip( accl[35:16] );
                right <= clip( accr[35:16] );
                rpos  <= rpos + 13'd1;
                st    <= IDLE;
            end
            default: st <= IDLE;
        endcase
    end
end

endmodule
