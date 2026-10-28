//============================================================================
//  SNES for MiSTer
//  Copyright (C) 2017-2019 Srg320
//  Copyright (C) 2018-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================ 

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;

assign AUDIO_S   = 1;
assign AUDIO_MIX = status[20:19];

assign LED_USER  = cart_download | ssbin_download | spc_download | (status[23] & bk_pending);
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = osd_btn;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

wire [1:0] ar       = status[33:32];
wire       vcrop_en = status[39];
wire [3:0] vcopt    = status[38:35];
reg        en216p;
reg  [4:0] voff;
always @(posedge CLK_VIDEO) begin
	en216p <= ((HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !forced_scandoubler && !scale);
	voff <= (vcopt < 6) ? {vcopt,1'b0} : ({vcopt,1'b0} - 5'd24);
end

wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? (V224_MODE ? 12'd64 : 12'd2048) : (ar - 1'd1)),
	.ARY((!ar) ? (V224_MODE ? 12'd49 : 12'd1673) : 12'd0),
	.CROP_SIZE((en216p & vcrop_en) ? 10'd216 : 10'd0),
	.CROP_OFF(voff),
	.SCALE(status[41:40])
);

///////////////////////  CLOCK/RESET  ///////////////////////////////////

wire clock_locked;
wire clk_mem;
wire clk_sys;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_mem),
	.outclk_1(CLK_VIDEO),
	.outclk_2(clk_sys),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(clock_locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

always @(posedge CLK_50M) begin
	reg pald = 0, pald2 = 0;
	reg [2:0] state = 0;

	pald  <= PAL;
	pald2 <= pald;

	cfg_write <= 0;
	if(pald2 != pald) state <= 1;

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			3: begin
					cfg_address <= 7;
					cfg_data <= pald2 ? 2201376898 : 2537930535;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

wire reset = RESET | buttons[1] | status[0] | cart_download | spc_download | bk_loading | clearing_ram | msu_data_download | nss_download | nss_nv_dl;
// NSS: the BIOS holds the SNES in reset (port 01 bit 0) and pauses its CPU (bit 1)
wire snes_reset = reset | ~nss_p01[0];

////////////////////////////  HPS I/O  //////////////////////////////////

// Status Bit Map:
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX XXXXXXXXXXXXXXXXX XXXXXXXX

`include "build_id.v"
parameter CONF_STR = {
	"NSS;;",
	"-;",
	"DIP;",
	"-;",
	"P1,Audio & Video;",
	"P1-;",
	"P1o01,Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O9B,Scandoubler Fx,None,HQ2x(off),CRT 25%,CRT 50%,CRT 75%;",
	"P1-;",
	"P1o89,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"P1OG,Pseudo Transparency,Blend,Off;",
	"P1OJK,Stereo Mix,None,25%,50%,100%;",
	"P1-;",
	"P1O[58],Timer/Menu Overlay,On,Off;",
	"P2,Hardware;",
	"P2-;",
	"P2OU,Audio Clock,Real,Typical;",
	"P2OLM,Initial WRAM,9966(SNES2),00FF(SNES1),55(SD2SNES),FF;",
	"P2oCD,Initial ARAM,9966(SNES2),00FF(SNES1),55(SD2SNES),FF;",
	"-;",
	"R0,Reset;",
	"J1,A,B,X,Y,L,R,Select,Start,Coin,Instructions,Page Up,Page Down,Game 1,Game 2,Game 3,Service,Restart;",
	"V,v",`BUILD_DATE
};

wire  [1:0] buttons;
wire [63:0] status;
wire [15:0] status_menumask = {ss_allow ,en216p, !GUN_MODE, ~turbo_allow, ~gg_available, ~GSU_ACTIVE, ~bk_ena};
wire        forced_scandoubler;
reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire        ioctl_download;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wr;
wire  [7:0] ioctl_index;

wire [31:0] joy0,joy1;
wire [12:0] joy2,joy3,joy4;
wire [24:0] ps2_mouse;
wire [10:0] ps2_key;
wire [15:0] joystick1_rumble;

wire  [7:0] joy0_x,joy0_y,joy1_x,joy1_y;

reg  [7:0] uart_mode;

wire [64:0] RTC;

wire [21:0] gamma_bus;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.new_vmode(new_vmode),

	.joystick_l_analog_0({joy0_y, joy0_x}),
	.joystick_l_analog_1({joy1_y, joy1_x}),
	.joystick_0(joy0),
	.joystick_1(joy1),
	.joystick_2(joy2),
	.joystick_3(joy3),
	.joystick_4(joy4),
	.joystick_0_rumble(status[8] ? 16'h0000 : joystick1_rumble), 
	.ps2_mouse(ps2_mouse),
	.ps2_key(ps2_key),

	.status(status),
	.status_menumask(status_menumask),
	.status_in(cart_download ? {status[63:53], ss_slot, status[50:5],1'b0,status[3:0]} : {status[63:53], ss_slot, status[50:32],1'b0,status[30:0]}),
	.status_set(cart_download | status0_fall | ss_status),

	.info_req(ss_info_req),
	.info(ss_info),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_upload(),
	.ioctl_din(nss_nv_dout),
	.ioctl_upload_req(nss_nv_chg),
	.ioctl_upload_index(8'd9),
	.ioctl_rd(),

	.sd_lba('{sd_lba}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din('{sd_buff_din}),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.uart_mode(uart_mode),

	.RTC(RTC),

	.gamma_bus(gamma_bus),
	.EXT_BUS(EXT_BUS)
);

wire       GUN_BTN = status[27];
wire [1:0] GUN_MODE = status[26:25];
wire       GUN_TYPE = status[34];
wire       GSU_TURBO = status[18];
wire       GSU_FASTROM = ~status[46];
wire       SUFAMI_SWAP = status[31];
wire [3:0] CC_TIME = status[57:54];
wire       BLEND = ~status[16];
wire [1:0] mouse_mode = status[6:5];
wire       joy_swap = status[7] | piano;
wire [2:0] LHRom_type = status[3:1];

wire code_index = &ioctl_index;
wire code_download = ioctl_download & code_index;
wire cart_download = ioctl_download & ((ioctl_index[5:0] == 6'h01) | (ioctl_index[7:0] == 0));
wire spc_download = ioctl_download & ioctl_index[5:0] == 6'h04;
wire msu_audio_download = ioctl_download & ioctl_index[5:0] == 6'h02;
wire msu_data_download  = ioctl_download & ioctl_index[5:0] == 6'h03;
wire ssbin_download = ioctl_download & ((ioctl_index[5:0] == 6'h00) & (ioctl_index[7:6] == 2'd1));


reg new_vmode;
always @(posedge clk_sys) begin
	reg old_pal;
	int to;

	if(~reset) begin
		old_pal <= PAL;
		if(old_pal != PAL) to <= 2000000;
	end

	if(to) begin
		to <= to - 1;
		if(to == 1) new_vmode <= ~new_vmode;
	end
end

//////////////////////////  ROM DETECT  /////////////////////////////////

reg        PAL;
reg  [7:0] rom_type;
reg [23:0] rom_mask, ram_mask;
reg  [3:0] ram_size;
always @(posedge clk_sys) begin
	reg [3:0] rom_size;
	reg       rom_region = 0;

	if (cart_download) begin
		if(ioctl_wr) begin
			if (ioctl_addr == 0) begin
				rom_size <= 4'hC;
				ram_size <= 4'h0;
				if(!LHRom_type && ioctl_dout[7:0]) {ram_size,rom_size} <= ioctl_dout[7:0];

				case(LHRom_type)
					1: rom_type <= 0;
					2: rom_type <= 0;
					3: rom_type <= 1;
					4: rom_type <= 2;
					default: rom_type <= ioctl_dout[15:8];
				endcase
			end

			if (ioctl_addr == 2) begin
				rom_region <= ioctl_dout[8];
			end

			if(LHRom_type == 2) begin
				if(ioctl_addr == ('h7FD6+'h200)) rom_size <= ioctl_dout[11:8];
				if(ioctl_addr == ('h7FD8+'h200)) ram_size <= ioctl_dout[3:0];
			end
			else if(LHRom_type == 3) begin
				if(ioctl_addr == ('hFFD6+'h200)) rom_size <= ioctl_dout[11:8];
				if(ioctl_addr == ('hFFD8+'h200)) ram_size <= ioctl_dout[3:0];
			end
			else if(LHRom_type == 4) begin
				if(ioctl_addr == ('h40FFD6+'h200)) rom_size <= ioctl_dout[11:8];
				if(ioctl_addr == ('h40FFD8+'h200)) ram_size <= ioctl_dout[3:0];
			end

			rom_mask <= (24'd1024 << rom_size) - 1'd1;
			ram_mask <= ram_size ? (24'd1024 << ram_size) - 1'd1 : 24'd0;
		end
	end
	else begin
		PAL <= (!status[15:14]) ? rom_region : status[15];
	end
end

reg spc_mode = 0;
always @(posedge clk_sys) begin
	if(ioctl_wr) begin
		spc_mode <= spc_download;
	end
end

reg osd_btn = 0;
reg status0_fall = 0;
always @(posedge clk_sys) begin
	integer timeout = 0;
	reg     has_bootrom = 0;
	reg     last_rst = 0;
	reg     old_status0;

	if (RESET) last_rst <= 0;
	if (status[0]) last_rst <= 1;

	if (cart_download) has_bootrom <= 1;

	if(last_rst & ~status[0]) begin
		osd_btn <= 0;
		if(timeout < 24000000) begin
			timeout <= timeout + 1;
			osd_btn <= ~has_bootrom;
		end
	end

	old_status0 <= status[0];
	status0_fall <= old_status0 & ~status[0];
end

////////////////////////////  SYSTEM  ///////////////////////////////////

wire GSU_ACTIVE;
wire turbo_allow;
wire SNES_SYSCLKR_CE,SNES_SYSCLKF_CE;
wire SNES_REFRESH;

wire ss_avail;
wire ss_ddr_ack, ss_ddr_req, ss_ddr_we;
wire [63:0] ss_ddr_dout, ss_ddr_din;
wire [21:3] ss_ddr_addr;
wire [ 7:0] ss_ddr_be;

reg [15:0] main_audio_l;
reg [15:0] main_audio_r;

main #(
	// NSS (TomSVR): no NSS game uses a cartridge coprocessor; keep the LoROM/HiROM map (DLH) only
	.USE_DSPn(1'b0), .USE_CX4(1'b0), .USE_SDD1(1'b0), .USE_GSU(1'b0), .USE_SA1(1'b0),
	.USE_SPC7110(1'b0), .USE_BSX(1'b0), .USE_SUFAMI(1'b0), .USE_MSU(1'b0), .USE_SS(1'b0)
) main
(
	.RESET_N(RESET_N),

	.MCLK(clk_sys), // 21.47727 / 21.28137
	.ACLK(clk_sys),

	.GSU_ACTIVE(GSU_ACTIVE),
	.GSU_TURBO(GSU_TURBO),
	.GSU_FASTROM(GSU_FASTROM),
	.SUFAMI_SWAP(SUFAMI_SWAP),
	.CC_DIP({4'b0001,CC_TIME}),
	
	.SYSCLKR_CE(SNES_SYSCLKR_CE),
	.SYSCLKF_CE(SNES_SYSCLKF_CE),
	.REFRESH(SNES_REFRESH),

	.ROM_TYPE(rom_type),
	.ROM_MASK(rom_mask),
	.RAM_MASK(ram_mask),
	.RAM_SIZE(ram_size),
	.PAL(PAL),
	.BLEND(BLEND),

	.ROM_ADDR(ROM_ADDR),
	.ROM_D(ROM_D),
	.ROM_Q(ROM_Q),
	.ROM_OE_N(ROM_OE_N),
	.ROM_WE_N(ROM_WE_N),
	.ROM_WORD(ROM_WORD),

	.BSRAM_ADDR(BSRAM_ADDR),
	.BSRAM_D(BSRAM_D),			
	.BSRAM_Q(BSRAM_Q),			
	.BSRAM_CE_N(BSRAM_CE_N),
	.BSRAM_OE_N(BSRAM_OE_N),
	.BSRAM_WE_N(BSRAM_WE_N),

	.WRAM_ADDR(WRAM_ADDR),
	.WRAM_D(WRAM_D),
	.WRAM_Q(WRAM_Q),
	.WRAM_CE_N(WRAM_CE_N),
	.WRAM_OE_N(WRAM_OE_N),
	.WRAM_WE_N(WRAM_WE_N),

	.VRAM1_ADDR(VRAM1_ADDR),
	.VRAM1_DI(VRAM1_Q),
	.VRAM1_DO(VRAM1_D),
	.VRAM1_WE_N(VRAM1_WE_N),

	.VRAM2_ADDR(VRAM2_ADDR),
	.VRAM2_DI(VRAM2_Q),
	.VRAM2_DO(VRAM2_D),
	.VRAM2_WE_N(VRAM2_WE_N),
	.VRAM_OE_N(VRAM_OE_N),

	.ARAM_ADDR(ARAM_ADDR),
	.ARAM_D(ARAM_D),
	.ARAM_Q(ARAM_Q),
	.ARAM_CE_N(ARAM_CE_N),
	.ARAM_WE_N(ARAM_WE_N),

	.R(R_out),
	.G(G_out),
	.B(B_out),

	.FIELD(FIELD),
	.INTERLACE(INTERLACE),
	.HIGH_RES(HIGH_RES),
	.V224_MODE(V224_MODE),
	.DOTCLK(DOTCLK_out),
	
	.HBLANKn(HBlank_out),
	.VBLANKn(VBlank_out),
	.HSYNC(HSYNC_out),
	.VSYNC(VSYNC_out),
	.HVCNT_ATZERO(HVCNT_ATZERO),

	.JOY1_DI(JOY1_DI),
	.JOY2_DI(GUN_MODE ? LG_DO : JOY2_DI),
	.JOY_STRB(JOY_STRB),
	.JOY1_CLK(JOY1_CLK),
	.JOY2_CLK(JOY2_CLK),
	.JOY1_P6(JOY1_P6),
	.JOY2_P6(JOY2_P6),
	.JOY2_P6_in(JOY2_P6_DI),
	.SNI_JOY(SNI_JOY),

	.EXT_RTC(RTC),

	.GG_EN(status[24]),
	.GG_CODE(gg_code),
	.GG_RESET((code_download && ioctl_wr && !ioctl_addr) || cart_download),
	.GG_AVAILABLE(gg_available),
	
	.SPC_MODE(spc_mode),

	.IO_ADDR(ioctl_addr[16:0]),
	.IO_DAT(ioctl_dout),
	.IO_WR(spc_download & ioctl_wr),
	
	.TURBO(status[4] & turbo_allow),
	.TURBO_ALLOW(turbo_allow),
	
	.DSP_FREQ(status[30]),
	
`ifdef DEBUG
	.DBG_BG_EN(DBG_BG_EN),
	.DBG_CPU_EN(DBG_CPU_EN),
`else
	.DBG_BG_EN(5'b11111),
	.DBG_CPU_EN(nss_p01[1]),
`endif

	// MSU register handling
	.MSU_TRACK_NUM(msu_track_num),
	.MSU_TRACK_REQUEST(msu_track_request),
	.MSU_TRACK_MOUNTING(msu_track_mounting),
	.MSU_TRACK_MISSING(msu_track_missing),
	.MSU_VOLUME(msu_volume),
	.MSU_AUDIO_REPEAT(msu_audio_repeat),
	.MSU_AUDIO_RESUME(msu_audio_resume),
	.MSU_AUDIO_STOP(msu_audio_stop),
	.MSU_AUDIO_PLAYING(msu_audio_playing),
	.MSU_AUDIO_SECTOR(msu_audio_sector),
	.MSU_RESUME_SECTOR(msu_resume_sector),
	.MSU_AUDIO_LOOP_INDEX(msu_audio_loop_index),
	.MSU_RESUME_LOOP_INDEX(msu_resume_loop_index),
	.MSU_DATA_ADDR(msu_data_addr),
	.MSU_DATA(msu_data),
	.MSU_DATA_ACK(msu_data_ack),
	.MSU_DATA_SEEK(msu_data_seek),
	.MSU_DATA_REQ(msu_data_req),
	.MSU_ENABLE(msu_enable),

	.NSS_DSW(nss_dsw),
	.NSS_OUT2(nss_out2),

	.SS_SAVE(ss_save),
	.SS_TOSD(~status[50]),
	.SS_LOAD(ss_load),
	.SS_SLOT(ss_slot),
	.SS_AVAIL(ss_avail),

	.SS_DDR_DI(ss_ddr_dout),
	.SS_DDR_ACK(ss_ddr_ack),
	.SS_DDR_DO(ss_ddr_din),
	.SS_DDR_ADDR(ss_ddr_addr),
	.SS_DDR_WE(ss_ddr_we),
	.SS_DDR_BE(ss_ddr_be),
	.SS_DDR_REQ(ss_ddr_req),

	.AUDIO_L(main_audio_l),
	.AUDIO_R(main_audio_r)
);

assign AUDIO_L = audio_l;
assign AUDIO_R = audio_r;

wire HVCNT_ATZERO;

reg RESET_N = 0;
reg RESET_REFRESH = 0;
always @(posedge clk_sys) begin
	reg [1:0] div;

	div <= div + 1'd1;
	RESET_REFRESH <= !div;

	// HV counters keep running during reset for stable video with vsync_adjust=2
	// Release the reset when HV counters are at zero

	if (snes_reset) begin
		if (div == 2) RESET_N <= 0;
	end
	else if (HVCNT_ATZERO) RESET_N <= 1;
end

////////////////////////////  CODES  ///////////////////////////////////

reg [128:0] gg_code;
wire gg_available;

// Code layout:
// {clock bit, code flags,     32'b address, 32'b compare, 32'b replace}
//  128        127:96          95:64         63:32         31:0
// Integer values are in BIG endian byte order, so it up to the loader
// or generator of the code to re-arrange them correctly.

always_ff @(posedge clk_sys) begin
	gg_code[128] <= 0;

	if (code_download & ioctl_wr) begin
		case (ioctl_addr[3:0])
			0:  gg_code[111:96]  <= ioctl_dout; // Flags Bottom Word
			2:  gg_code[127:112] <= ioctl_dout; // Flags Top Word
			4:  gg_code[79:64]   <= ioctl_dout; // Address Bottom Word
			6:  gg_code[95:80]   <= ioctl_dout; // Address Top Word
			8:  gg_code[47:32]   <= ioctl_dout; // Compare Bottom Word
			10: gg_code[63:48]   <= ioctl_dout; // Compare top Word
			12: gg_code[15:0]    <= ioctl_dout; // Replace Bottom Word
			14: begin
				gg_code[31:16]    <= ioctl_dout; // Replace Top Word
				gg_code[128]      <= 1;          // Clock it in
			end
		endcase
	end
end

////////////////////////////  MEMORY  ///////////////////////////////////

reg [17:0] mem_fill_addr;
reg clearing_ram = 0;
reg mem_fill_wait;
always @(posedge clk_sys) begin
	if(~old_downloading & cart_download)
		clearing_ram <= 1'b1;

	if (&mem_fill_addr) clearing_ram <= 0;

	if (clearing_ram) begin
		mem_fill_wait <= ~mem_fill_wait;
		if (mem_fill_wait) 
			mem_fill_addr <= mem_fill_addr + 1'b1;
	end else begin
		mem_fill_addr <= 0;
		mem_fill_wait <= 0;
	end
end
wire mem_fill_we = clearing_ram & ~mem_fill_wait;

reg [7:0] wram_fill_data;
always @* begin
    case(status[22:21])
        0: wram_fill_data = (mem_fill_addr[8] ^ mem_fill_addr[2]) ? 8'h66 : 8'h99;
        1: wram_fill_data = (mem_fill_addr[9] ^ mem_fill_addr[0]) ? 8'hFF : 8'h00;
        2: wram_fill_data = 8'h55;
        3: wram_fill_data = 8'hFF;
    endcase
end

reg [7:0] aram_fill_data;
always @* begin
    case(status[45:44])
        0: aram_fill_data = (mem_fill_addr[8] ^ mem_fill_addr[2]) ? 8'h66 : 8'h99;
        1: aram_fill_data = (mem_fill_addr[9] ^ mem_fill_addr[0]) ? 8'hFF : 8'h00;
        2: aram_fill_data = 8'h55;
        3: aram_fill_data = 8'hFF;
    endcase
end

wire[23:0] ROM_ADDR;
wire       ROM_OE_N;
wire       ROM_WE_N;
wire       ROM_WORD;
wire[15:0] ROM_D;
wire[15:0] ROM_Q;

wire[16:0] WRAM_ADDR;
wire       WRAM_CE_N;
wire       WRAM_OE_N;
wire       WRAM_WE_N;
wire [7:0] WRAM_Q, WRAM_D;

wire[24:0]  SDRAM_SNI_ADDR;
wire[7:0]   SDRAM_SNI_DATA;
wire[7:0]   SDRAM_SNI_Q;
wire        SDRAM_SNI_RD;
wire        SDRAM_SNI_WR;
wire        SDRAM_SNI_READY;

wire[24:0] cart_addr_download = ioctl_addr-10'd512;
wire[23:0] ssbin_addr_download = { 8'hFF, ioctl_addr[15:0] };
wire[23:0] addr_download = ssbin_download ? ssbin_addr_download : cart_addr_download[23:0];

wire       sdram_download = cart_download | ssbin_download;

reg [23:0] sdram_download_addr;
reg [15:0] sdram_download_data;
reg        sdram_download_wr;
reg        sdram_download_en;
always @(posedge clk_mem) begin
	sdram_download_addr <= addr_download;
	sdram_download_data <= ioctl_dout;
	sdram_download_wr <= ioctl_wr;
	sdram_download_en <= sdram_download;
end

reg READ_PULSE;
always @(posedge clk_sys)
	READ_PULSE <= SNES_SYSCLKR_CE;

wire [15:0] sdr_dout1, sdr_sni_dout;
sdram sdram
(
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_A(SDRAM_A),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE),

	.init(0), //~clock_locked),
	.clk(clk_mem),
	
	.addr0(sdram_download_en ? sdram_download_addr : ROM_ADDR),
	.din0(sdram_download_en ? sdram_download_data : ROM_D),
	.dout0(ROM_Q),

	.rd0(sdram_download_en ? 1'b0 : !RESET_N ? RESET_REFRESH : ~ROM_OE_N),
	.wr0(sdram_download_en ? sdram_download_wr : ~ROM_WE_N),
	.word0(sdram_download_en | ROM_WORD),

	.addr1(clearing_ram ? {7'b0000000,mem_fill_addr} : {7'b0000000,WRAM_ADDR}),
	.din1(clearing_ram ? {8'h00,wram_fill_data} : {8'h00,WRAM_D}),

	.dout1(sdr_dout1),

	.rd1(clearing_ram ? 1'b0 : ~WRAM_CE_N & ~WRAM_OE_N & READ_PULSE),
	.wr1(clearing_ram ? mem_fill_we : ~WRAM_CE_N & ~WRAM_WE_N & SNES_SYSCLKF_CE),
	.rfs1(clearing_ram ? 1'b0 : !RESET_N ? RESET_REFRESH : SNES_REFRESH),
	.word1(0),

	.sni_addr(SDRAM_SNI_ADDR),
	.sni_din({8'h00,SDRAM_SNI_DATA}),
	.sni_dout(sdr_sni_dout),
	.sni_rd_req(SDRAM_SNI_RD),
	.sni_wr_req(SDRAM_SNI_WR),
	.sni_ready(SDRAM_SNI_READY),
	.sni_word(0)
);

assign WRAM_Q = sdr_dout1[7:0];
assign SDRAM_SNI_Q = sdr_sni_dout[7:0];

wire        VRAM_OE_N;
reg         VRAM_OE_N_DELAYED;
always @(posedge clk_sys)
	VRAM_OE_N_DELAYED <= VRAM_OE_N;
	
wire [15:0] VRAM1_ADDR;
wire        VRAM1_WE_N;
wire  [7:0] VRAM1_D;
wire  [7:0] vram1_q;
dpram #(15)	vram1
(
	.clock(clk_sys),
	.address_a(VRAM1_ADDR[14:0]),
	.data_a(VRAM1_D),
	.wren_a(~VRAM1_WE_N),
	.q_a(vram1_q),

	// clear the RAM on loading
	.address_b(mem_fill_addr[14:0]),
	.wren_b(mem_fill_we)
);
wire  [7:0] VRAM1_Q = !VRAM_OE_N && !VRAM_OE_N_DELAYED ? vram1_q : '1;

wire [15:0] VRAM2_ADDR;
wire        VRAM2_WE_N;
wire  [7:0] VRAM2_D;
wire  [7:0] vram2_q;
dpram #(15) vram2
(
	.clock(clk_sys),
	.address_a(VRAM2_ADDR[14:0]),
	.data_a(VRAM2_D),
	.wren_a(~VRAM2_WE_N),
	.q_a(vram2_q),

	// clear the RAM on loading
	.address_b(mem_fill_addr[14:0]),
	.wren_b(mem_fill_we)
);
wire  [7:0] VRAM2_Q = !VRAM_OE_N && !VRAM_OE_N_DELAYED ? vram2_q : '1; 

wire [15:0] ARAM_ADDR;
wire        ARAM_CE_N;
wire        ARAM_WE_N;
wire  [7:0] ARAM_Q, ARAM_D;
dpram_dif #(16,8,15,16) aram
(
	.clock(clk_sys),
	.address_a(ARAM_ADDR),
	.data_a(ARAM_D),
	.wren_a(~ARAM_CE_N & ~ARAM_WE_N),
	.q_A(ARAM_Q),

	// clear the RAM on loading
	.address_b(spc_download ? addr_download[15:1] : mem_fill_addr[15:1]),
	.data_b(spc_download ? ioctl_dout : {2{aram_fill_data}}),
	.wren_b(spc_download ? ioctl_wr : mem_fill_we)
);

localparam  BSRAM_BITS = 13; // NSS (TomSVR): 8 Kbyte, the largest NSS cart SRAM (Super Mario All-Stars); was 256 Kbyte
wire [19:0] BSRAM_ADDR;
wire        BSRAM_CE_N;
wire        BSRAM_OE_N, BSRAM_WE_N;
wire  [7:0] BSRAM_Q, BSRAM_D;
wire [19:0] BSRAM_SNI_ADDR;
wire        BSRAM_SNI_RD, BSRAM_SNI_WR;
wire [7:0]  BSRAM_SNI_D;
wire        BSRAM_SNI_READY = (BSRAM_SNI_RD | BSRAM_SNI_WR) & (BSRAM_CE_N | (BSRAM_OE_N & BSRAM_WE_N));

dpram_dif #(BSRAM_BITS,8,BSRAM_BITS-1,16) bsram 
(
	.clock(clk_sys),

	//Thrash the BSRAM upon ROM loading
	.address_a(clearing_ram ? mem_fill_addr[BSRAM_BITS-1:0] : BSRAM_SNI_READY ? BSRAM_SNI_ADDR : BSRAM_ADDR[BSRAM_BITS-1:0]),
	.data_a(clearing_ram ? 8'hFF : BSRAM_SNI_READY ? BSRAM_SNI_D : BSRAM_D),
	.wren_a(clearing_ram ? mem_fill_we : BSRAM_SNI_READY ? BSRAM_SNI_WR : ~BSRAM_CE_N & ~BSRAM_WE_N),
	.q_a(BSRAM_Q),

	.address_b({sd_lba[BSRAM_BITS-10:0],sd_buff_addr}),
	.data_b(sd_buff_dout),
	.wren_b(sd_buff_wr & sd_ack),
	.q_b(sd_buff_din)
);

////////////////////////////  VIDEO  ////////////////////////////////////

wire [7:0] R_out,G_out,B_out;
wire HSYNC_out;
wire VSYNC_out;
wire HBlank_out;
wire VBlank_out;
wire DOTCLK_out;

always @(posedge clk_sys) begin
	DOTCLK <= DOTCLK_out;
	if(DOTCLK ^ DOTCLK_out) begin
		R <= R_out;
		G <= G_out;
		B <= B_out;
		HSYNC  <= HSYNC_out;
		VSYNC  <= VSYNC_out;
		HBlank <= ~HBlank_out;
		VBlank <= ~VBlank_out;
	end
end

reg  [7:0] R,G,B;
wire FIELD,INTERLACE;
reg  HSync, HSYNC;
reg  VSync, VSYNC;
reg  HBlank;
reg  VBlank;
wire HIGH_RES,V224_MODE;
reg  DOTCLK;

reg interlace;
reg ce_pix;
// NSS: the picture goes out at one pixel per SNES master clock (1024 active pixels per line in both SNES
// resolutions) so the OSD dots (12 OSD dots = 8 SNES dots) land on whole pixels
always @(posedge CLK_VIDEO) begin
	reg old_vsync;
	old_vsync <= VSync;
	if(~old_vsync & VSync) interlace <= INTERLACE;
	ce_pix <= ~ce_pix;
	if(ce_pix) {HSync, VSync} <= {HSYNC, VSYNC};
end

assign VGA_F1 = interlace & FIELD;
assign VGA_SL = {~interlace,~interlace}&sl[1:0];

wire [2:0] scale = status[11:9];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;
wire       scandoubler = ~interlace && (scale || forced_scandoubler);

video_mixer #(.LINE_LENGTH(1040), .GAMMA(1)) video_mixer
(
	.*,
	.hq2x(1'b0),
	.freeze_sync(),
	.VGA_DE(vga_de),
	.R(nss_r),
	.G(nss_g),
	.B(nss_b)
);

////////////////////////////  NSS  ////////////////////////////////////
// Nintendo Super System board side (nss/): Z80 BIOS, INST ROM, security PROM, EEPROM, RTC, M50458 OSD.
// ioctl index 5 = board ROMs (00000 BIOS, 08000 INST ROM upper 8K, 0a000 PROM, 0c000 OSD font),
// index 9 = EEPROM (NVRAM), index 254 = cartridge DIP switches (4100h).

wire nss_download = ioctl_download & (ioctl_index == 8'd5);
wire nss_nv_dl    = ioctl_download & (ioctl_index == 8'd9);
reg  [7:0] nss_dsw;
always @(posedge clk_sys) if (ioctl_wr && ioctl_index == 8'd254 && !ioctl_addr[24:1]) nss_dsw <= ioctl_dout[7:0];

// WIDE ioctl -> bytes
reg        nss_dl_wr, nss_dl_hi;
reg [16:0] nss_dl_addr;
reg  [7:0] nss_dl_data, nss_dl_next;
always @(posedge clk_sys) begin
	nss_dl_wr <= 0;
	if (nss_download & ioctl_wr) begin
		nss_dl_wr <= 1; nss_dl_addr <= ioctl_addr[16:0]; nss_dl_data <= ioctl_dout[7:0];
		nss_dl_next <= ioctl_dout[15:8]; nss_dl_hi <= 1;
	end else if (nss_dl_hi) begin
		nss_dl_hi <= 0; nss_dl_wr <= 1; nss_dl_addr <= nss_dl_addr + 1'd1; nss_dl_data <= nss_dl_next;
	end
end

wire [15:0] nss_nv_dout;
wire        nss_nv_chg;
wire  [7:0] nss_p01, nss_p03;
wire  [2:0] nss_osd_rgb;
wire        nss_osd_fg, nss_osd_raster;
wire [15:0] nss_osd_r0, nss_osd_r7;
wire        nss_out2;

// SNES timing for the board: NMI on vblank, port 00 bit 6 = vsync.
// Watchdog (port 00 bit 7): the real board wants the SNES to read its joypads every N frames, but what exactly
// clears the flag is unknown. Clearing it on the joypad latch made Lethal Weapon and NCAA Basketball trip it
// during their intros on real MiSTer hardware (cart dropped: NON SLOT, credits returned), so it is cleared every
// frame like MAME does (MAME snes_m.cpp clears m_joy_flag on every auto-read pass).
reg  joy_strb_d;
always @(posedge clk_sys) joy_strb_d <= JOY_STRB;

// OSD timing: line start 128 master clocks (48 OSD dots) before the SNES active line, frame start 6 lines after
// the SNES vblank begins (32 lines before line 1); one OSD dot every 8/3 master clocks
reg [10:0] nss_hc;
reg  [2:0] nss_vc;
reg  [3:0] nss_acc;
reg        nss_hs, nss_vs, nss_ce, nss_vpend;
reg        hb_d, vb_d;
always @(posedge clk_sys) begin
	hb_d <= HBlank; vb_d <= VBlank;
	nss_hs <= 0; nss_vs <= 0; nss_ce <= 0;
	if (HBlank & ~hb_d) nss_hc <= 0; else if (nss_hc != 11'h7ff) nss_hc <= nss_hc + 1'd1;
	if (VBlank & ~vb_d) begin nss_vc <= 0; nss_vpend <= 1; end
	if (nss_hc == 11'd211) begin
		nss_hs <= 1; nss_acc <= 0;
		if (nss_vpend) begin
			nss_vc <= nss_vc + 1'd1;
			if (nss_vc == 3'd6) begin nss_vs <= 1; nss_vpend <= 0; end
		end
	end else begin
		if (nss_acc >= 4'd5) begin nss_acc <= nss_acc - 4'd5; nss_ce <= 1; end
		else nss_acc <= nss_acc + 4'd3;
	end
end

// keep the board (and so the SNES) in reset until its ROMs (index 5) have arrived: the cart (index 0) loads
// first, and in between the Z80 would run an empty BIOS (and could scribble on the EEPROM)
reg nss_loaded = 0;
always @(posedge clk_sys) if (nss_download) nss_loaded <= 1;

nss_board nss_board
(
	.clk(clk_sys),
	.reset(reset | ~nss_loaded | nss_download),

	.dl_wr(nss_dl_wr),
	.dl_addr(nss_dl_addr),
	.dl_data(nss_dl_data),

	.nv_wr(nss_nv_dl & ioctl_wr),
	.nv_addr(ioctl_addr[7:1]),
	.nv_din(ioctl_dout),
	.nv_dout(nss_nv_dout),
	.nv_chg(nss_nv_chg),

	.rtc(RTC),

	.snes_vblank(VBlank),
	.snes_vsync(VSYNC),
	.snes_joy_read(VBlank & ~vb_d),   // watchdog acknowledged every frame, as MAME (see below)
	.snes_out2(nss_out2),
	.p01(nss_p01),
	.p03(nss_p03),
	.coin_cnt(),

	.pad({joy0[5], joy0[4], joy0[2], joy0[3], joy0[1], joy0[0]}),
	.panel({joy0[20] | joy1[20], joy0[14] | joy1[14], joy0[15] | joy1[15], joy0[13] | joy1[13],
	        joy0[18] | joy1[18], joy0[17] | joy1[17], joy0[16] | joy1[16]}),
	.coin({joy0[19] | joy1[19], joy1[12], joy0[12]}),

	.osd_ce(nss_ce),
	.osd_hs(nss_hs),
	.osd_vs(nss_vs),
	.osd_rgb(nss_osd_rgb),
	.osd_fg(nss_osd_fg),
	.osd_raster(nss_osd_raster),
	.osd_reg0(nss_osd_r0),
	.osd_reg7(nss_osd_r7),
	.dbg_pc()
);

// Video mix. M50458 pins: P1 = blanking (reg 0 bit 1: automatic = OSD dots; else manual level bit 7),
// P4/P3/P2 = R/G/B (automatic = OSD colour, else manual level bits 10/9/8). Where blanking is high the OSD
// replaces the SNES picture (game menu: blanking forced high, raster colour as background; in game: only the
// OSD dots, superimposed). Port 03 bit 6 enables the OSD layer, bit 7 the SNES layer.
wire       osd_blnk = nss_osd_r0[1] ? nss_osd_fg : nss_osd_r0[7];
wire [2:0] osd_pin  = {nss_osd_r0[2] ? nss_osd_rgb[2] : nss_osd_r0[8],
                       nss_osd_r0[3] ? nss_osd_rgb[1] : nss_osd_r0[9],
                       nss_osd_r0[4] ? nss_osd_rgb[0] : nss_osd_r0[10]};   // {B,G,R}
wire       osd_show = nss_p03[6] & osd_blnk & ~(status[58] & nss_osd_r0[1]);
reg  [7:0] nss_r, nss_g, nss_b;
always @(posedge clk_sys) begin
	if (osd_show) begin
		nss_r <= {8{osd_pin[0]}}; nss_g <= {8{osd_pin[1]}}; nss_b <= {8{osd_pin[2]}};
	end else if (nss_p03[7]) begin
		nss_r <= R; nss_g <= G; nss_b <= B;
	end else begin
		nss_r <= 0; nss_g <= 0; nss_b <= 0;
	end
end

////////////////////////////  I/O PORTS  ////////////////////////////////

assign {UART_RTS, UART_DTR} = 1;

wire piano = status[43] & (uart_mode == 3);
reg last_piano = 1'b0;
always @(posedge clk_sys) last_piano <= piano;
reg piano_tdata_i;
reg sni_tdata_i;
wire [15:0] piano_data_i;
wire [15:0] sni_data_i;
wire [15:0] data_o;
wire rbf;
wire txint;
wire rxint;

uart uart(
	.clk(clk_sys),
	.reset(reset || (piano ^ last_piano)),
	.midi_speed_sel(piano),
	.tdata_i(piano ? piano_tdata_i : sni_tdata_i),
	.data_i(piano ? piano_data_i : sni_data_i),
	.data_o(data_o),
	.uartbrk(1'b0),//reset),
	.rbfmirror(rbf),
	.txint(txint),
	.rxint(rxint),
	.txd(UART_TXD),
	.rxd(UART_RXD)
);

wire piano_joypad_do;
miraclepiano miracle(
	.clk(clk_sys),
	.reset(reset || !piano),
	.strobe(JOY_STRB),
	.joypad_o(piano_joypad_do),
	.joypad_clock(JOY1_CLK),
	.txint(txint),
	.rxint(rxint),
	.tdata_i(piano_tdata_i),
	.tdata_m(piano_data_i),
	.rdata_m(data_o)
);

wire [63:0] SNI_JOY;
sni sni(
	.clk(clk_sys),
	.reset(reset || uart_mode != 6),
	.vblank(VBlank),

	.sdram_addr(SDRAM_SNI_ADDR),
	.sdram_data(SDRAM_SNI_DATA),
	.sdram_q(SDRAM_SNI_Q),
	.sdram_rd_req(SDRAM_SNI_RD),
	.sdram_wr_req(SDRAM_SNI_WR),
	.sdram_ready(SDRAM_SNI_READY),

	.bsram_addr(BSRAM_SNI_ADDR),
	.bsram_q(BSRAM_Q),
	.bsram_rd(BSRAM_SNI_RD),
	.bsram_wr(BSRAM_SNI_WR),
	.bsram_data(BSRAM_SNI_D),
	.bsram_ready(BSRAM_SNI_READY),

	.joypad(SNI_JOY),

	.rbf(rbf),
	.txint(txint),
	.rxint(rxint),
	.tdata_i(sni_tdata_i),
	.tdata_m(sni_data_i),
	.rdata_m(data_o)
);
wire [1:0] JOY1_DO = piano ? {1'b1,piano_joypad_do} : JOY1_DO_t;

wire       JOY_STRB;

wire [1:0] JOY1_DO_t;
wire       JOY1_CLK;
wire       JOY1_P6;
ioport port1
(
	.CLK(clk_sys),

	.PORT_LATCH(JOY_STRB),
	.PORT_CLK(JOY1_CLK),
	.PORT_P6(JOY1_P6),
	.PORT_DO(JOY1_DO_t),

	.JOYSTICK1((joy_swap ^ raw_serial) ? joy1 : joy0),
	.JOYSTICK1_RUMBLE(joystick1_rumble),

	.MOUSE(ps2_mouse),
	.MOUSE_EN(mouse_mode[0])
);

wire [1:0] JOY2_DO;
wire       JOY2_CLK;
wire       JOY2_P6;
ioport port2
(
	.CLK(clk_sys),

	.MULTITAP(status[17]),

	.PORT_LATCH(JOY_STRB),
	.PORT_CLK(JOY2_CLK),
	.PORT_P6(JOY2_P6),
	.PORT_DO(JOY2_DO),

	.JOYSTICK1((joy_swap ^ raw_serial) ? joy0 : joy1),
	.JOYSTICK2(joy2),
	.JOYSTICK3(joy3),
	.JOYSTICK4(joy4),

	.MOUSE(ps2_mouse),
	.MOUSE_EN(mouse_mode[1])
);

wire       LG_P6_out;
wire [1:0] LG_DO;
wire [2:0] LG_TARGET;
wire       LG_T = ((GUN_MODE[0]&joy0[6]) | (GUN_MODE[1]&joy1[6])); // always from joysticks

lightgun lightgun
(
	.CLK(clk_sys),
	.RESET(reset),

	.MOUSE(ps2_mouse),
	.MOUSE_XY(&GUN_MODE),

	.JOY_X(GUN_MODE[0] ? joy0_x : joy1_x),
	.JOY_Y(GUN_MODE[0] ? joy0_y : joy1_y),

	.F(GUN_BTN ? ps2_mouse[0] : ((GUN_MODE[0]&(joy0[4]|joy0[9]) | (GUN_MODE[1]&(joy1[4]|joy1[9]))))),
	.C(GUN_BTN ? ps2_mouse[1] : ((GUN_MODE[0]&(joy0[5]|joy0[8]) | (GUN_MODE[1]&(joy1[5]|joy0[8]))))),
	.T(LG_T), // always from joysticks
	.P(ps2_mouse[2] | ((GUN_MODE[0]&joy0[7]) | (GUN_MODE[1]&joy1[7]))), // always from joysticks and mouse

	.HDE(~HBlank),
	.VDE(~VBlank),
	.CLKPIX(DOTCLK),
	
	.TARGET(LG_TARGET),
	.SIZE(status[28]),
	.GUN_TYPE(GUN_TYPE),

	.PORT_LATCH(JOY_STRB),
	.PORT_CLK(JOY2_CLK),
	.PORT_P6(LG_P6_out),
	.PORT_DO(LG_DO)
);

// 1 [oooo|ooo) 7 - 1:+5V  2:Clk  3:Strobe   4:D0  5:D1  6: I/O  7:Gnd

// Indexes:
// IDXDIR   Function    USBPIN
// 0  OUT   Strobe      D+
// 1  OUT   Clk (P1)    D-
// 2  IN    D1          TX-
// 3  OUT   CLK (P2)    GND_d
// 4  BI    I/O         RX+
// 5  IN    P1D0        RX-
// 6  IN    P2D0        TX+

wire raw_serial = status[8];
reg snac_p2 = 0;

assign USER_OUT[2] = 1'b1;
assign USER_OUT[5] = 1'b1;
assign USER_OUT[6] = 1'b1;

// JOYX_DO[0] is P4, JOYX_DO[1] is P5
wire [1:0] JOY1_DI;
wire [1:0] JOY2_DI;
wire JOY2_P6_DI;

always @(posedge clk_sys) begin
	if (raw_serial) begin
		if (~USER_IN[6])
			snac_p2 <= 1;
	end else begin
		snac_p2 <= 0;
	end
end

always_comb begin
	if (raw_serial) begin
		USER_OUT[0] = JOY_STRB;
		USER_OUT[1] = joy_swap ? ~JOY2_CLK : ~JOY1_CLK;
		USER_OUT[3] = joy_swap ? ~JOY1_CLK : ~JOY2_CLK;
		if (snac_p2) begin
			USER_OUT[4] = joy_swap ? JOY1_P6 : JOY2_P6;
			JOY1_DI = joy_swap ? {1'b1, USER_IN[6]} : {1'b1, USER_IN[5]};
			JOY2_DI = joy_swap ? {USER_IN[2], USER_IN[5]} : {USER_IN[2], USER_IN[6]};
			JOY2_P6_DI = USER_IN[4];
		end else begin
			USER_OUT[4] = joy_swap ? JOY2_P6 : JOY1_P6;
			JOY1_DI = joy_swap ? JOY1_DO : {USER_IN[2], USER_IN[5]};
			JOY2_DI = joy_swap ? {USER_IN[2], USER_IN[5]} : JOY2_DO;
			JOY2_P6_DI = joy_swap ? USER_IN[4] : (LG_P6_out | !GUN_MODE);
		end
	end else begin
		USER_OUT[0] = 1'b1;
		USER_OUT[1] = 1'b1;
		USER_OUT[3] = 1'b1;
		USER_OUT[4] = 1'b1;
		JOY1_DI = nss_p01[7] ? JOY1_DO : 2'b11;   // NSS: joypads cut off until a game is paid for
		JOY2_DI = nss_p01[7] ? JOY2_DO : 2'b11;
		JOY2_P6_DI = (LG_P6_out | !GUN_MODE);
	end
end

/////////////////////////  STATE SAVE/LOAD  /////////////////////////////

wire bk_save_write = ~BSRAM_CE_N & ~BSRAM_WE_N;
reg bk_pending;

always @(posedge clk_sys) begin
	if (bk_ena && ~OSD_STATUS && bk_save_write)
		bk_pending <= 1'b1;
	else if (bk_state | ~bk_ena)
		bk_pending <= 1'b0;
end

reg bk_ena = 0;
reg old_downloading = 0;
reg cart_ready = 0;
reg ssbin_ready = 0;
always @(posedge clk_sys) begin
	old_downloading <= cart_download;
	if(~old_downloading & cart_download) bk_ena <= 0;

	if(old_downloading & ~cart_download) cart_ready <= 1;

	if (ssbin_download) ssbin_ready <= 1;

	//Save file always mounted in the end of downloading state.
	if(cart_download && img_mounted && !img_readonly) bk_ena <= |ram_mask;
end

wire bk_load    = status[12];
wire bk_save    = status[13] | (bk_pending & OSD_STATUS && status[23]);
reg  bk_loading = 0;
reg  bk_state   = 0;
wire [31:0] sd_lba_end = rom_type[7:4] == 4'h2 && rom_type[3] ? {ram_mask[23:9],1'b1} : ram_mask[23:9];//For Sufami with B cart, it's double size
always @(posedge clk_sys) begin
	reg old_load = 0, old_save = 0, old_ack;

	old_load <= bk_load & bk_ena;
	old_save <= bk_save & bk_ena;
	old_ack  <= sd_ack;

	if(~old_ack & sd_ack) {sd_rd, sd_wr} <= 0;

	if(!bk_state) begin
		if((~old_load & bk_load) | (~old_save & bk_save)) begin
			bk_state <= 1;
			bk_loading <= bk_load;
			sd_lba <= 0;
			sd_rd <=  bk_load;
			sd_wr <= ~bk_load;
		end
		if(old_downloading & ~cart_download & |img_size & bk_ena) begin
			bk_state <= 1;
			bk_loading <= 1;
			sd_lba <= 0;
			sd_rd <= 1;
			sd_wr <= 0;
		end
	end else begin
		if(old_ack & ~sd_ack) begin
			if(sd_lba >= sd_lba_end) begin
				bk_loading <= 0;
				bk_state <= 0;
			end else begin
				sd_lba <= sd_lba + 1'd1;
				sd_rd  <=  bk_loading;
				sd_wr  <= ~bk_loading;
			end
		end
	end
end

//debug
`ifdef DEBUG
reg [4:0] DBG_BG_EN = '1;
reg       DBG_CPU_EN = 1;

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];

always @(posedge clk_sys) begin
	reg old_state = 0;

	old_state <= ps2_key[10];

	if((ps2_key[10] != old_state) && pressed) begin
		casex(code)
			'h005: begin DBG_BG_EN[0] <= ~DBG_BG_EN[0]; end // F1
			'h006: begin DBG_BG_EN[1] <= ~DBG_BG_EN[1]; end // F2
			'h004: begin DBG_BG_EN[2] <= ~DBG_BG_EN[2]; end // F3
			'h00C: begin DBG_BG_EN[3] <= ~DBG_BG_EN[3]; end // F4
			'h003: begin DBG_BG_EN[4] <= ~DBG_BG_EN[4]; end // F5
			'h177: begin DBG_CPU_EN   <= ~DBG_CPU_EN;   end // Pause
		endcase
	end
end
`endif

///////////////////////////  MSU1  ///////////////////////////////////

wire msu_enable;

// EXT bus is used to communicate with the HPS for MSU functionality
wire [35:0] EXT_BUS;
hps_ext hps_ext
(
	.reset(reset),
	.clk_sys(clk_sys),
	.EXT_BUS(EXT_BUS),

	.msu_enable(msu_enable),

	.msu_track_mounting(msu_track_mounting),
	.msu_track_missing(msu_track_missing),
	.msu_track_num(msu_track_num),
	.msu_track_request(msu_track_request),

	.msu_audio_size(msu_audio_size),
	.msu_audio_ack(msu_audio_ack),
	.msu_audio_req(msu_audio_req),
	.msu_audio_seek(msu_audio_seek),
	.msu_audio_sector(msu_audio_sector),
	.msu_audio_download(msu_audio_download),

	.msu_data_base(msu_data_base)
);

wire        msu_track_mounting;
wire        msu_track_missing;
wire [15:0] msu_track_num;
wire        msu_track_request;
wire [31:0] msu_audio_size;

wire  [7:0] msu_volume;
wire        msu_audio_repeat;
wire        msu_audio_playing;
wire        msu_audio_stop;
wire        msu_audio_resume;

wire        msu_audio_ack;
wire        msu_audio_req;
wire        msu_audio_seek;
wire [21:0] msu_audio_sector;
wire [21:0] msu_resume_sector;
wire [31:0] msu_audio_loop_index;
wire [31:0] msu_resume_loop_index;

wire [15:0] msu_l;
wire [15:0] msu_r;

msu_audio msu_audio
(
	.reset(reset),

	.clk(clk_sys),
	.clk_rate(PAL ? 21281370 : 21477270),

	.ctl_volume(msu_volume),
	.ctl_stop(msu_audio_stop),
	.ctl_play(msu_audio_playing),
	.ctl_resume(msu_audio_resume),
	.ctl_repeat(msu_audio_repeat),

	.track_size(msu_audio_size),
	.track_processing(msu_track_request),

	.audio_download(msu_audio_download),
	.audio_data(ioctl_dout),
	.audio_data_wr(ioctl_wr),

	.audio_ack(msu_audio_ack),
	.audio_sector(msu_audio_sector),
	.audio_req(msu_audio_req),
	.audio_seek(msu_audio_seek),
	.resume_sector(msu_resume_sector),
	.audio_loop_index(msu_audio_loop_index),
	.resume_loop_index(msu_resume_loop_index),

	.audio_l(msu_l),
	.audio_r(msu_r)
);

reg [15:0] audio_l, audio_r;

always @(posedge clk_sys) begin
	reg [16:0] mix_l, mix_r;

	mix_l = $signed({main_audio_l[15], main_audio_l}) + $signed({msu_l[15], msu_l});
	mix_r = $signed({main_audio_r[15], main_audio_r}) + $signed({msu_r[15], msu_r});

	audio_l <= nss_p01[5] ? 16'd0 : (^mix_l[16:15]) ? {mix_l[16], {15{mix_l[15]}}} : mix_l[15:0];   // NSS mute (port 01 bit 5)
	audio_r <= nss_p01[5] ? 16'd0 : (^mix_r[16:15]) ? {mix_r[16], {15{mix_r[15]}}} : mix_r[15:0];
end

wire [31:0] msu_data_addr;
wire  [7:0] msu_data;
wire        msu_data_ack;
wire        msu_data_seek;
wire        msu_data_req;
wire [31:0] msu_data_base;

wire [31:3] msu_ram_addr;
wire        msu_ram_req;
wire        msu_ram_ack;
wire [63:0] msu_ram_dout;

assign DDRAM_CLK = clk_mem;

msu_data_store msu_data_store
(
	.clk_sys(clk_sys),

	.base_addr(msu_data_base),

	.rd_next(msu_data_req),
	.rd_seek(msu_data_seek),
	.rd_seek_done(msu_data_ack),
	.rd_addr(msu_data_addr),

	.ram_addr(msu_ram_addr),
	.ram_req(msu_ram_req),
	.ram_ack(msu_ram_ack),
	.ram_din(msu_ram_dout),

	.rd_dout(msu_data)
);

ddram ddram
(
	.DDRAM_CLK(DDRAM_CLK),

	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),

	.cache_rst(~RESET_N),

	.rdaddr({11'b0011_1111_10, ss_ddr_addr[21:3]}), // Save states at $3F80.0000
	.dout(ss_ddr_dout),
	.rom_din(ss_ddr_din),
	.rom_be(ss_ddr_be),
	.rom_we(ss_ddr_we),
	.rom_req(ss_ddr_req),
	.rom_ack(ss_ddr_ack),

	.rdaddr2(msu_ram_addr), // MSU is at $2060.0000-3F7F.FFFF
	.dout2(msu_ram_dout),
	.rd_req2(msu_ram_req),
	.rd_ack2(msu_ram_ack)
);


// saving with keyboard/OSD/gamepad
wire [1:0] ss_slot;
wire [7:0] ss_info;
wire ss_save, ss_load, ss_info_req;
wire ss_status;
wire ss_allow = ss_avail & cart_ready & ssbin_ready;
wire ss_joy_start = joy0[11] | status[53];

savestate_ui #(.INFO_TIMEOUT_BITS(25)) savestate_ui
(
	.clk            (clk_sys       ),
	.ps2_key        (ps2_key[10:0] ),
	.allow_ss       (ss_allow      ),
	.joySS          (1'b0          ),
	.joyRight       (joy0[0]       ),
	.joyLeft        (joy0[1]       ),
	.joyDown        (joy0[2]       ),
	.joyUp          (joy0[3]       ),
	.joyStart       (ss_joy_start  ),
	.joyRewind      (0             ),
	.rewindEnable   (0             ),
	.status_slot    (status[52:51] ),
	.OSD_saveload   (status[48:47] ),
	.ss_save        (ss_save       ),
	.ss_load        (ss_load       ),
	.ss_info_req    (ss_info_req   ),
	.ss_info        (ss_info       ),
	.statusUpdate   (ss_status     ),
	.selected_slot  (ss_slot       )
);

endmodule
