//============================================================================
//  HAL for NukedMD-FPGA
//  Copyright (c) 2023 Alexey Melnikov
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

// MEGAPLAY (Quartus project MegaPlay.qsf): the Sega Mega Play core (rtl/mp_bios.sv) from the same source
// MDBOOT (Quartus project MDBoot.qsf): the Mega Drive arcade bootleg boards (rtl/mdb_io.sv), no BIOS
`ifndef MEGAPLAY
`ifndef MDBOOT
`define MT_SBS   // Mega-Tech side by side output (OSD), see rtl/mt_sbs.sv
`endif
`endif

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign BUTTONS   = osd_btn;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// DDRAM driven by mdp_audio for CDDA PCM streaming

assign LED_DISK  = 0;
assign LED_POWER = 0;

// MD+ debug: sticky latch — LED stays on after first MD+ command received
reg mdp_cmd_seen;
always @(posedge clk_sys) begin
	if (sys_reset)
		mdp_cmd_seen <= 0;
	else if (mdp_track_request | mdp_stop_request | mdp_resume_request)
		mdp_cmd_seen <= 1;
end

assign LED_USER  = cart_download | sav_pending | mdp_cmd_seen;

assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;

assign AUDIO_S   = 1;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire  [1:0] ar = status[49:48];
wire        sbs_vid;   // side-by-side output (see mt_sbs)

wire       vcrop_en = status[34];
wire [3:0] vcopt    = status[53:50];
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
	.ARX((!ar) ? (sbs_vid ? {arx[10:0], 1'b0} : arx) : (ar - 1'd1)),
	.ARY((!ar) ? ary : 12'd0),
	.CROP_SIZE((en216p & vcrop_en) ? 10'd216 : 10'd0),
	.CROP_OFF(voff),
	.SCALE(status[55:54])
);

`include "build_id.v"
localparam CONF_STR = {
`ifdef MDBOOT
	"MD Arcade Bootlegs;;",
	"-;",
`elsif MEGAPLAY
	"Mega Play;;",
	"-;",
`else
	"Mega-Tech;;",
	"-;",
	"O[64],Screen,Game,Menu;",
`endif
`ifdef MT_SBS
	"O[68],Side by Side,Off,On;",
`endif
`ifdef MDBOOT
`elsif MEGAPLAY
	"P3,Cartridge Slots 2-4;",
	"P3FC2,MPC,Slot 2;",
	"P3FC3,MPC,Slot 3;",
	"P3FC4,MPC,Slot 4;",
`else
	"O[69],Menu on VGA (15kHz),Off,On;",
	"O[65],Coin Sound,Off,On;",
	"O[66],Time Up Background,Black,Blue;",
	"O[67],Flash Warning,Dim,Shadow;",
	"P3,Cartridge Slots 2-8;",
	"P3FC2,MTC,Slot 2;",
	"P3FC3,MTC,Slot 3;",
	"P3FC4,MTC,Slot 4;",
	"P3FC5,MTC,Slot 5;",
	"P3FC6,MTC,Slot 6;",
	"P3FC7,MTC,Slot 7;",
	"P3FC8,MTC,Slot 8;",
`endif
	"DIP;",
	"-;",
`ifndef MDBOOT
	"O[7:6],Region,JP,US,EU;",
`endif
	
	"-;",
	"C,Cheats;",
	"H1O[24],Cheats Enabled,Yes,No;",
	"-;",
	"O[13],Autosave,Off,On;",
	"H6D0R[16],Load Backup RAM;",
	"H6D0R[17],Save Backup RAM;",
	"-;",

	"P1,Audio & Video;",
	"P1O[49:48],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[3:1],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"d5P1O[34],Vertical Crop,Disabled,216p(5x);",
	"d5P1O[53:50],Crop Offset,0,2,4,8,10,12,-12,-10,-8,-6,-4,-2;",
	"P1O[55:54],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"P1O[30],320x224 Aspect,Original,Corrected;",
	"P1O[29],Border,No,Yes;",
	"P1O[46],Composite Blend,Off,On;",
	"P1O[10],CRAM Dots,Off,On;",
	"P1-;",
	"P1O[15:14],Audio Filter,Model 1,Model 2,Minimal,No Filter;",
	"P1O[11],FM Chip,YM2612,YM3438;",
	"P1O[60],SMS FM Chip,Enabled,Disabled;",
	"P1O[58:57],Stereo Mix,None,25%,50%,100%;",

	"P2,Input;",
	"P2-;",
	"P2O[4],Swap Joysticks,No,Yes;",
	// "P2O[5],6 Buttons Mode" removed: Mega-Tech pads have 3 buttons
	"P2O[39:37],Multitap,Disabled,4-Way,TeamPlayer: Port1,TeamPlayer: Port2,J-Cart;",
	"P2-;",
	"P2O[19:18],Mouse,None,Port1,Port2;",
	"P2O[20],Mouse Flip Y,No,Yes;",
	"P2-;",
	"P2O[22:21],Keyboard,None,Port1,Port2;",
	"P2-;",
	"P2O[41:40],Gun Control,Disabled,Joy1,Joy2,Mouse;",
	"D4P2O[42],Gun Fire,Joy,Mouse;",
	"D4P2O[44:43],Cross,Small,Medium,Big,None;",
	"P2-;",
	"P2O[63:62],SNAC,Off,Port 1,Port 2,Port 3;",

	"-;",
	"O[61],Pause When OSD is Open,No,Yes;",
	"R[0],Reset;",
`ifdef MDBOOT
	// MD bootlegs: the coin sits on button 8 named "Select", so MiSTer's default map puts it on the pad's Select
	// ("Coin" would default to R). The boards have no Mode button.
	"J1,A,B,C,Start,Select,X,Y,Z;",
`else
	"J1,A,B,C,Start,Mode,X,Y,Z,Coin,Select,Enter,Test;",
`endif
	"jn,A,B,R,Start,Select,X,Y,L;", // name map to SNES layout.
	"jp,Y,B,A,Start,Select,L,X,R;", // positional map to SNES layout (3 button friendly)
	"V,v",`BUILD_DATE
};

///////////////////////////////////////////////////

wire clk_53m, clk_107m, clk_53m_v, pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_53m),
	.outclk_1(clk_107m),
	.outclk_2(clk_53m_v),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(pll_locked)
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
	reg pal_r;

	pald <= PAL;
	pald2 <= pald;

	cfg_write <= 0;
	if(pald2 == pald && pald2 != pal_r) begin
		state <= 1;
		pal_r <= pald2;
	end

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 7;
					cfg_data <= pal_r ? 2201376125 : 2537930535;
					cfg_write <= 1;
				end
			7: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

wire clk_sys     = clk_53m;
wire clk_ram     = clk_107m;
wire clk_md      = clk_107m;
assign CLK_VIDEO = clk_53m_v;

///////////////////////////////////////////////////

wire[127:0] status;
wire  [1:0] buttons;
wire [15:0] joystick_0,joystick_1;
wire [11:0] joystick_2,joystick_3,joystick_4;
wire  [7:0] joy0_x,joy0_y,joy1_x,joy1_y;
wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;
wire  [7:0] ioctl_index;
wire        ioctl_wait;
wire        ioctl_upload;
wire [15:0] mt_nv_dout;                  // Mega-Tech BIOS NVRAM save (MRA <nvram index="4">)
wire        mt_nv_chg;                   // BIOS wrote settings/bookkeeping: MiSTer saves the NVRAM when the OSD opens

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

wire        forced_scandoubler;
wire [10:0] ps2_key;
wire [2:0]  ps2_kbd_led_status;
wire [2:0]  ps2_kbd_led_use = 3'b111;
wire [24:0] ps2_mouse;

wire [21:0] gamma_bus;
wire [15:0] sdram_sz;

wire [35:0] EXT_BUS;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_3(joystick_3),
	.joystick_4(joystick_4),
	.joystick_l_analog_0({joy0_y, joy0_x}),
	.joystick_l_analog_1({joy1_y, joy1_x}),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.new_vmode(new_vmode),

	.status(status),
	.status_in({status[127:8],region_req,status[5:0]}),
	.status_set(region_set),
	.status_menumask({tmss_loaded,status[13],en216p,!gun_mode,1'b0,status[8],~gg_available,~bk_ena}),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),
	.ioctl_upload(ioctl_upload),
	.ioctl_din(mt_nv_dout),
	.ioctl_upload_req(mt_nv_chg),
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

	.gamma_bus(gamma_bus),
	.sdram_sz(sdram_sz),

	.ps2_key(ps2_key),
	.ps2_kbd_led_status(ps2_kbd_led_status),
	.ps2_kbd_led_use(ps2_kbd_led_use),
	.ps2_mouse(ps2_mouse),

	.EXT_BUS(EXT_BUS)
);

wire [1:0] gun_mode = status[41:40];
wire       gun_btn_mode = status[42];

// Mega-Tech (TomSVR): the MRA sends one image on index 0 (see docs/design.md):
// 0x000000 BIOS 32 kB, 0x008000 instruction ROM 32 kB, 0x010000 header, 0x020000 game ROM (.bin order).
// The console's own .bin/.sms loading (index 1/2) and the TMSS boot ROM (index 0) are not used.
// Slots 2-8 (OSD "FC2".."FC8", remembered by MiSTer per MRA): index n = slot n, a .mtc file with the same layout as
// the MRA image (the BIOS part is ignored). NVRAM is index 9.
wire [5:0] mt_idx     = ioctl_index[5:0];
wire mt_download   = ioctl_download & (ioctl_index == 0);
`ifdef MDBOOT
// MD bootlegs: 0x000000 header (byte 0 board family, 1 descramble scheme, 2-3 Conny protection address/value,
// 4 flags: bit 0 6-button pads, bit 1 US region), 0x001000 PIC16C57 program (2048 little-endian words),
// 0x010000 the game ROM as MAME's maincpu region (68000 order). The game goes to SDRAM at 0, descrambled on the way
// (mdb_descramble below), so the MRA assembles the zips unmodified.
wire mt_slot_dl    = 1'b0;
wire [2:0] mt_dl_slot = 3'd0;
wire mt_cart_part  = ioctl_addr >= 25'h010000;
wire mt_ins_part   = 1'b0;
localparam MT_HDR  = 25'h1ffffff;     // no Mega-Tech header
wire [24:0] cart_addr_dl = ioctl_addr - 25'h010000;
`elsif MEGAPLAY
// Mega Play: 0x000000 BIOS 128 kB, 0x020000 instruction ROM 32 kB, 0x028000 header, 0x030000 game ROM; the BIOS
// and the instruction ROM go to SDRAM at 16 MB (the BIOS side reads them through its window), the game to slot 0.
// Slots 2-4 (OSD "FC2".."FC4"): index n = slot n, a .mpc file with the MRA image layout (the BIOS part is ignored,
// header byte 2 = the game's DSW nibble); its instruction ROM goes to word 0x810000 + slot * 0x4000, the game to
// slot * 2 MB. Any loaded slot 2-4 turns the board into the 4-slot one (mp_bios four_slot).
wire mt_slot_dl    = ioctl_download & (mt_idx >= 6'd2) & (mt_idx <= 6'd4);
wire [2:0] mt_dl_slot = mt_slot_dl ? mt_idx[2:0] - 3'd1 : 3'd0;
wire mt_cart_part  = ioctl_addr >= 25'h030000;
wire mt_ins_part   = (ioctl_addr < 25'h028000) & (~mt_slot_dl | (ioctl_addr >= 25'h020000));
localparam MT_HDR  = 25'h028000;
wire [24:0] cart_addr_dl = mt_ins_part ? (25'h1000000 | {7'd0, ioctl_addr[17:0]}) : ioctl_addr - 25'h030000;
`else
wire mt_slot_dl    = ioctl_download & (mt_idx >= 6'd2) & (mt_idx <= 6'd8);
wire [2:0] mt_dl_slot = mt_slot_dl ? mt_idx[2:0] - 3'd1 : 3'd0;
wire mt_cart_part  = ioctl_addr >= 25'h020000;
wire mt_ins_part   = ioctl_addr[24:15] == 10'd1;     // 0x8000-0xffff
localparam MT_HDR  = 25'h010000;
wire [24:0] cart_addr_dl = mt_ins_part ? (25'h1000000 | {10'd0, ioctl_addr[14:0]}) : ioctl_addr - 25'h020000;
`endif
wire cart_download = mt_download | mt_slot_dl;
wire cart_wr_dl    = ioctl_wr & (mt_cart_part | mt_ins_part);
wire code_download = ioctl_download & &ioctl_index;
wire tmss_download = 1'b0;

`ifdef MDBOOT
// MD bootlegs: header, DIP switches (MRA <switches>, ioctl index 254: bytes DSWA, DSWB, DSWC), PIC program
reg  [7:0] mdb_family = 0, mdb_scheme = 0, mdb_prot_hi = 0, mdb_prot_val = 0, mdb_flags = 0;
reg [23:0] mdb_dsw = 24'hffffff;
always @(posedge clk_sys) begin
	if (mt_download & ioctl_wr) begin
		if (ioctl_addr == 25'd0) {mdb_scheme, mdb_family}   <= ioctl_data;
		if (ioctl_addr == 25'd2) {mdb_prot_val, mdb_prot_hi} <= ioctl_data;
		if (ioctl_addr == 25'd4) mdb_flags <= ioctl_data[7:0];
	end
	if (ioctl_wr && ioctl_index == 8'd254) begin
		if (ioctl_addr == 25'd0) mdb_dsw[15:0]  <= ioctl_data;
		if (ioctl_addr == 25'd2) mdb_dsw[23:16] <= ioctl_data[7:0];
	end
end
wire mdb_pic_wr = mt_download & ioctl_wr & (ioctl_addr[24:12] == 13'd1);

// Data descrambling of the Actel boards on the way to SDRAM (mdb_io.sv)
wire [15:0] mdb_dl_data;
mdb_descramble mdb_descramble(.scheme(mdb_scheme), .addr(cart_addr_dl[23:0]), .din(ioctl_data), .dout(mdb_dl_data));

wire [15:0] mdb_dout;
wire        mdb_den, mdb_dtack, mdb_nmi;
wire  [1:0] mdb_bank;
wire  [1:0] mdb_exp_coin_n;
reg   [1:0] mdb_nmi_s;
always @(posedge clk_md) mdb_nmi_s <= {mdb_nmi_s[0], mdb_nmi};
wire        mdb_nmi_md = mdb_nmi_s[1];
`else
wire  [1:0] mdb_bank = 2'd0;
wire        mdb_nmi_md = 1'b0;
`endif

// per slot: present, SMS flag (header byte 0 bit 0)
reg  [7:0] mt_present = 0, mt_ms = 0;
wire  [2:0] mt_cart_sel;
wire        mt_game_reset;
wire        mt_ins_req, mt_ins_ack;
wire [14:1] mt_ins_a;
wire [15:0] mt_ins_data;
wire  [2:0] mt_ins_slot = mt_cart_sel;
wire [23:0] mt_ins_wa;                   // SDRAM word address of the BIOS side's read
always @(posedge clk_sys) begin
	if(cart_download & ioctl_wr & (ioctl_addr == MT_HDR)) begin
		mt_ms[mt_dl_slot] <= ioctl_data[0];
		mt_present[mt_dl_slot] <= 1;
	end
end
wire cart_ms = mt_ms[cart_download ? mt_dl_slot : mt_cart_sel];
`ifdef MEGAPLAY
reg [3:0] mp_dsw_s [1:3];               // Mega Play: DSW nibble of the games in slots 2-4 (.mpc header byte 2)
always @(posedge clk_sys)
	if (mt_slot_dl & ioctl_wr & (ioctl_addr == MT_HDR + 25'd2)) mp_dsw_s[mt_dl_slot[1:0]] <= ioctl_data[3:0];
wire mp_four = |mt_present[3:1];
wire [1:0] mp_slot;
`endif

reg osd_btn = 0;
always @(posedge clk_sys) begin
	integer timeout = 0;
	reg     has_bootrom = 0;
	reg     last_rst = 0;

	if (RESET) last_rst <= 0;
	if (status[0]) last_rst <= 1;

	if (cart_download & ioctl_wr & status[0]) has_bootrom <= 1;

	if(last_rst & ~status[0]) begin
		osd_btn <= 0;
		if(timeout < 24000000) begin
			timeout <= timeout + 1;
			osd_btn <= ~has_bootrom;
		end
	end
end

///////////////////////////////////////////////////

wire reset   = status[0] | buttons[1] | region_set_rst;
wire mt_hold_68k, mt_hold_z80;         // Mega-Tech: game CPUs held in reset by the BIOS (the VDP keeps running)
wire mt_game_black;                      // Mega-Tech: game screen black + game sound muted (TIME UP restart)
wire mt_sel_rst;                         // Mega-Tech: cart select restarting the game CPUs
reg  [7:0] mt_kb = 0;                    // Mega-Tech: cabinet keys on the keyboard (ps2_key decoder)
wire [3:0] mt_porte;                     // io2 port E outputs (mt_bios)
wire [7:0] mt_portd;                     // io2 port D outputs (mt_bios)
wire [1:0] mt_r, mt_g, mt_b;           // Mega-Tech menu screen (mt_bios)
wire       mt_hs, mt_vs, mt_hbl, mt_vbl, mt_ce_pix;
wire [7:0] mp_ic36_q;                    // Mega Play (mp_bios): shared RAM IC36 read on the game Z80 bus
wire [7:3] mp_exp_hi;                    //   I/O port C bits from the BIOS
wire [1:0] mp_start_n;                   //   Start lines to the game pads
wire [1:0] mp_r, mp_g, mp_b;             //   overlay picture, y1 = overlay pixel shown
wire       mp_y1, mp_sync;

// Menu monitor on the analog port (OSD "Menu on VGA"): game on HDMI, menu screen as 15 kHz RGB on VGA.
// Untested on hardware: needs a 15 kHz-capable monitor; not with the HDMI direct-video adapter.
reg [23:0] vga2_rgb;
reg        vga2_hs, vga2_vs;
always @(posedge clk_sys) begin
	vga2_rgb <= (mt_hbl | mt_vbl) ? 24'd0 : {{4{mt_r}}, {4{mt_g}}, {4{mt_b}}};
	vga2_hs  <= mt_hs;
	vga2_vs  <= mt_vs;
end
assign VGA2_EN  = status[69];
assign VGA2_RGB = vga2_rgb;
assign VGA2_HS  = vga2_hs;
assign VGA2_VS  = vga2_vs;
assign VGA2_CS  = vga2_hs ^ vga2_vs;
wire signed [10:0] mt_snd;                // menu PSG
wire       mt_timeup;                     // TIME UP screen on the main monitor
wire       mt_test_on;                    // TEST MODE screens on the main monitor (mt_bios second Mode 4 VDP)
wire [1:0] mt_t_r, mt_t_g, mt_t_b;
wire       mt_t_hs, mt_t_vs, mt_t_hbl, mt_t_vbl;
wire loading = cart_download | bk_loading | RESET;

// Mega-Tech: a cart select that changes the running cartridge resets the whole game side (VDP, I/O, mappers, RAM),
// as MAME's switch_cart does: the next cart may be a Master System one (VDP mode 4, SMS mapper) or expect power-on
// state. Selects of the same cart (boot, start of play, TIME UP) keep the CPU-only reset (no picture glitch).
reg  [2:0] mt_run_sel = 0;
reg  [1:0] mt_grst_d = 0;
reg  [7:0] mt_sw_cnt = 0;
reg  [1:0] mt_sw_s = 0;
wire       mt_switch = |mt_sw_cnt;
always @(posedge clk_sys) begin
	mt_grst_d <= {mt_grst_d[0], mt_game_reset};
	if (mt_sw_cnt) mt_sw_cnt <= mt_sw_cnt - 1'd1;
	if (mt_grst_d[1] && mt_cart_sel != mt_run_sel) begin
		mt_run_sel <= mt_cart_sel;
		mt_sw_cnt  <= 8'hff;
	end
end

reg        btn_reset;
reg        md_reset;
reg        s_reset;
reg [15:1] ram_rst_a;
always @(posedge clk_md) begin
	reg [4:0] cnt = 0;
	reg old_reset = 0;
	
	ram_rst_a <= ram_rst_a + 1'd1;
	if(&ram_rst_a & ~&cnt) cnt <= cnt + 1'd1;

	old_reset <= reset;
	mt_sw_s <= {mt_sw_s[0], mt_switch};
	if(loading | mt_sw_s[1] | (~old_reset & reset)) cnt <= 0;

	s_reset <= (cnt < 3);
	
	if(loading | mt_sw_s[1]) md_reset <= 1;
	else if(cnt == 3) md_reset <= 0;

	if(~old_reset & reset) btn_reset <= 1;
	else if(&cnt)          btn_reset <= 0;
end

reg sys_reset;
always @(posedge clk_sys) begin
	reg [1:0] sreset;
	
	sreset <= {sreset[0], s_reset};
	if(!sreset) sys_reset <= 0;
	if(&sreset) sys_reset <= 1;
end

reg vclk_en, zclk_en, clk_en;
reg vclk_r = 0, zclk_r = 0;
always @(posedge clk_md) begin
	clk_en <= ~cart_download;

	// enables kept one clock ahead: the next clock value is then a 2-input AND of registers
	if(VCLK & ~VCLK_next) vclk_en <= ~cart_download;
	if(ZCLK & ~ZCLK_next) zclk_en <= ~cart_download;

	vclk_r <= VCLK_next & vclk_en;
	zclk_r <= ZCLK_next & zclk_en;
end

always @(posedge clk_md) begin
	reg pause_req;

	pause_req <= OSD_STATUS & status[61];

	if(pause_req & ~md_reset & ~btn_reset & ~cart_download) begin
		dma_z80_req <= 1;
		if((dma_z80_ack | res_z80) & ~cart_dma) dma_68k_req <= 1;
	end
	else begin
		dma_68k_req <= 0;
		dma_z80_req <= 0;
	end
end

///////////////////////////////////////////////////

`ifdef MDBOOT
wire        PAL = 1'b0;                   // MD bootlegs: NTSC, Japan or US console as MAME's init (header flag)
wire        JAP = ~mdb_flags[1];
`else
wire        PAL = status[7];
wire        JAP = !status[7:6];
`endif

wire [23:1] cart_addr;
wire        cart_cs, cart_oe, cart_lwr, cart_uwr, cart_time, cart_dma;
wire [15:0] cart_data_wr;

// Cartridge module outputs (before MD+ overlay mux)
wire [15:0] cart_data_rom;
wire        cart_data_en_rom;
wire        cart_dtack_rom;

// MD+ overlay outputs
wire        mdp_data_en;
wire [15:0] mdp_data_out;
wire        mdp_dtack;
wire        mdp_active;
wire [15:0] mdp_last_cmd;
wire        mdp_track_request;
wire  [7:0] mdp_track_num;
wire        mdp_track_loop;
wire        mdp_stop_request;
wire  [7:0] mdp_fade_sectors;
wire        mdp_resume_request;
wire  [7:0] mdp_volume;
wire        mdp_volume_request;

// Muxed cart signals: MD+ overlay takes priority when active
`ifdef MDBOOT
// MD bootlegs: the board I/O (mdb_io) answers instead of MD+ (whose registers sit inside the bootlegs' ROM space)
wire [15:0] cart_data    = mdb_den ? mdb_dout : cart_data_rom;
wire        cart_data_en = mdb_den | cart_data_en_rom;
wire        cart_dtack   = mdb_dtack | cart_dtack_rom;
`else
wire [15:0] cart_data    = mdp_data_en ? mdp_data_out : cart_data_rom;
wire        cart_data_en = mdp_data_en | cart_data_en_rom;
wire        cart_dtack   = mdp_dtack   | cart_dtack_rom;
`endif

wire        vdp_hclk1;
wire        vdp_de_h;
wire        vdp_de_v;
wire        vdp_intfield;
wire        vdp_m2, vdp_m5, vdp_rs1;
wire        vdp_disp;
wire  [7:0] r,g,b;
wire        hs, vs;

wire  [6:0] PA_d, PA_o, PB_d, PB_o, PC_d, PC_o;
wire  [6:0] PA_i, PB_i, PC_i;

wire  [8:0] MOL, MOR;
wire  [9:0] MOL_2612, MOR_2612;
wire [15:0] PSG;
wire        fm_clk1;
wire        fm_sel23;

wire [14:0] ram_68k_address;
wire  [1:0] ram_68k_byteena;
wire [15:0] ram_68k_data;
wire        ram_68k_wren;
wire [15:0] ram_68k_o;
wire [12:0] ram_z80_address;
wire  [7:0] ram_z80_data;
wire        ram_z80_wren;
wire  [7:0] ram_z80_o;
wire        ram_z80_a13;                  // Mega Play: 2000-3fff is IC36, the RAM shared with the BIOS
wire  [7:0] ram_z80_q;
wire [15:0] tmss_data;
wire  [9:0] tmss_address;

wire [23:1] m68k_addr;
wire [15:0] m68k_bus_do;
wire [15:0] z80_addr;
wire  [7:0] z80_bus_do;

reg         dma_68k_req;
reg         dma_z80_req;
wire        dma_z80_ack;
wire        res_z80;

wire        VCLK, ZCLK;
wire        VCLK_next, ZCLK_next;

// FLASH into the MD VDP: resync to clk_md (slow-changing static signal from clk_sys)
reg [1:0] mt_ste_s;
always @(posedge clk_md) mt_ste_s <= {mt_ste_s[0], ~status[64] & ~mt_timeup & mt_porte[1] & ~cart_ms & status[67]};
wire mt_ste_md = mt_ste_s[1];

md_board md_board
(
	.MCLK2(clk_md),

	.ext_reset(md_reset),
	.ext_vres(mt_hold_68k), // Mega-Tech: 68k reset from the BIOS (PAL 315-5347), VDP/RAM untouched
	.ext_zres(mt_hold_z80), // Mega-Tech: Z80 reset from the BIOS (io2 port D5)
	.ext_ste(mt_ste_md), // Mega-Tech FLASH = forced shadow (HUD stays bright, as on the cabinet)
	.reset_button(btn_reset), // edge triggered, requires some activity time to get detected.
	.ext_nmi(mdb_nmi_md),     // MD bootlegs: Conny boards' coin NMI

	// ram
	.ram_68k_address(ram_68k_address),
	.ram_68k_byteena(ram_68k_byteena),
	.ram_68k_data(ram_68k_data),
	.ram_68k_wren(ram_68k_wren),
	.ram_68k_o(ram_68k_o),
	.ram_z80_address(ram_z80_address),
	.ram_z80_data(ram_z80_data),
	.ram_z80_wren(ram_z80_wren),
	.ram_z80_o(ram_z80_o),
	.ram_z80_a13(ram_z80_a13),

	// cheat engine
	.m68k_addr(m68k_addr),
	.m68k_bus_do(m68k_bus_do),
	.m68k_di(m68k_data),
	.z80_addr(z80_addr),
	.z80_bus_do(z80_bus_do),
	.z80_di(z80_data),

	.tmss_enable(tmss_enable & tmss_loaded),
	.tmss_data(tmss_data),
	.tmss_address(tmss_address),

	.ext_VCLK_o(VCLK),
	.ext_ZCLK_o(ZCLK),
	.ext_VCLK_next(VCLK_next),
	.ext_ZCLK_next(ZCLK_next),
	.ext_VCLK_i(vclk_r),
	.ext_VCLK_i_next(VCLK_next & vclk_en),
	.ext_ZCLK_i(zclk_r),

	// cart
	.M3(~cart_ms),
	.cart_address(cart_addr),
	.cart_data(cart_data),
	.cart_data_en(cart_data_en),
	.cart_data_wr(cart_data_wr),
	.cart_cs(cart_cs),
	//.cart_oe(cart_oe),
	.vdp_dma_oe_early(cart_oe),
	.cart_lwr(cart_lwr),
	.cart_uwr(cart_uwr),
	.cart_time(cart_time),
	.cart_m3_pause(1'b0), // Mega-Tech: no PAUSE button for SMS games (MAME has none; Start paused / opened game menus)
	//.cart_dma(cart_dma),
	.vdp_dma(cart_dma),
	.ext_dtack(cart_dtack),
	.pal(PAL),
	.jap(JAP),

	// video
	.V_R(r),
	.V_G(g),
	.V_B(b),
	.V_HS(hs),
	.vdp_vsync2(vs),
	
	// audio
	.MOL(MOL),
	.MOR(MOR),
	.MOL_2612(MOL_2612),
	.MOR_2612(MOR_2612),
	.PSG(PSG),
	.fm_clk1(fm_clk1),
	.fm_sel23(fm_sel23),

	// pads
	.PA_i(PA_i),
	.PA_o(PA_o),
	.PA_d(PA_d), // 1 - input, 0 - output
	.PB_i(PB_i),
	.PB_o(PB_o),
	.PB_d(PB_d),
	.PC_i(PC_i),
	.PC_o(PC_o),
	.PC_d(PC_d),

	// helpers
	.vdp_hclk1(vdp_hclk1),
	.vdp_intfield(vdp_intfield),
	.vdp_de_h(vdp_de_h),
	.vdp_de_v(vdp_de_v),
	.vdp_m2(vdp_m2),
	.vdp_m5(vdp_m5),
	.vdp_disp(vdp_disp),
	.vdp_rs1(vdp_rs1),
	.vdp_cramdot_dis(~status[10]),
	.ym2612_status_enable(ym2612_quirk),
	
	.dma_68k_req(dma_68k_req),
	.dma_z80_req(dma_z80_req),
	.dma_z80_ack(dma_z80_ack),
	.res_z80(res_z80)
);

dpram #(15,16) ram_68k
(
	.clock(clk_md),

	.address_a(ram_68k_address),
	.data_a(ram_68k_data),
	.wren_a(ram_68k_wren),
	.byteena_a(ram_68k_byteena),
	.q_a(ram_68k_o),

	.address_b(ram_rst_a),
	.wren_b(md_reset)
);

`ifdef MEGAPLAY
reg mp_a13_d;
always @(posedge clk_md) mp_a13_d <= ram_z80_a13;
assign ram_z80_o = mp_a13_d ? mp_ic36_q : ram_z80_q;
`else
assign ram_z80_o = ram_z80_q;
`endif
dpram #(13,8) ram_z80k
(
	.clock(clk_md),

	.address_a(ram_z80_address),
	.data_a(ram_z80_data),
`ifdef MEGAPLAY
	.wren_a(ram_z80_wren & ~ram_z80_a13),
`else
	.wren_a(ram_z80_wren),
`endif
	.q_a(ram_z80_q),

	.address_b(ram_rst_a),
	.wren_b(md_reset),
	.data_b(8'hC7) // reset instruction to fix Titan 2 bug
);

dpram_difclk #(10,16,10,16) rom_tmss
(
	.clock_a(clk_md),
	.address_a(tmss_address),
	.q_a(tmss_data),

	.clock_b(clk_sys),
	.address_b(ioctl_addr[10:1]),
	.wren_b(ioctl_wr && tmss_download && !ioctl_addr[24:11]),
	.data_b({ioctl_data[7:0],ioctl_data[15:8]})
);

reg tmss_enable = 0;
reg tmss_loaded = 0;
always @(posedge clk_sys) begin
	if(ioctl_wr & tmss_download) tmss_loaded <= 1;
	if(sys_reset) tmss_enable <= status[12];
end

wire [13:0] sms_fm_audio;
wire        gun_type;
wire  [7:0] gun_sensor_delay;
wire        ym2612_quirk;

cartridge cartridge
(
	.clk(clk_sys),
	.clk_ram(clk_ram),
	.reset(sys_reset),
	.reset_sdram(~pll_locked),

	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_A(SDRAM_A),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nWE(SDRAM_nWE),
	
	.cart_dl(cart_download),
	.cart_dl_slot(mt_dl_slot),
	.cart_dl_ins(mt_ins_part),
	.cart_dl_addr(cart_addr_dl),
`ifdef MDBOOT
	.cart_dl_data(mdb_dl_data),
`else
	.cart_dl_data(ioctl_data),
`endif
	.cart_dl_wr(cart_wr_dl),
	.cart_dl_wait(ioctl_wait),

	.cart_ms(cart_ms),
	.cart_slot(mt_cart_sel),
	.mdb_bank(mdb_bank),
	.cart_addr(cart_addr),
	.ins_wa(mt_ins_wa), .ins_req(mt_ins_req), .ins_ack(mt_ins_ack), .ins_data(mt_ins_data),
	.cart_data(cart_data_rom),
	.cart_data_en(cart_data_en_rom),
	.cart_data_wr(cart_data_wr),
	.cart_cs(cart_cs),
	.cart_oe(cart_oe),
	.cart_lwr(cart_lwr),
	.cart_uwr(cart_uwr),
	.cart_time(cart_time),
	.cart_dtack(cart_dtack_rom),
	.cart_dma(cart_dma),

	.save_addr({sd_lba[6:0],sd_buff_addr}),
	.save_di(sd_buff_dout),
	.save_do(sd_buff_din),
	.save_wr(sd_buff_wr & sd_ack),
	.save_change(bk_change),

	.jcart_en(status[39]),
	.jcart_data(jcart_data),
	.jcart_th(jcart_th),
	
	.gun_type(gun_type),
	.gun_sensor_delay(gun_sensor_delay),

	.ym2612_quirk(ym2612_quirk),

	.fm_en(~status[60]),
	.fm_audio(sms_fm_audio)
);


///////////////////////////////////////////////////
// MD+ Overlay (CDDA command intercept)
///////////////////////////////////////////////////

// HPS ↔ FPGA bridge for MD+ status + audio pointer exchange
wire mdp_hps_playing;
wire [7:0] mdp_hps_current_track;
wire [15:0] mdp_audio_rd_ptr;
wire [15:0] mdp_audio_wr_ptr;
wire        mdp_audio_active;

hps_ext hps_ext
(
	.clk_sys(clk_sys),
	.reset(sys_reset),
	.EXT_BUS(EXT_BUS),

	.mdp_track_request(mdp_track_request),
	.mdp_track_num(mdp_track_num),
	.mdp_track_loop(mdp_track_loop),
	.mdp_stop_request(mdp_stop_request),
	.mdp_fade_sectors(mdp_fade_sectors),
	.mdp_resume_request(mdp_resume_request),
	.mdp_volume(mdp_volume),
	.mdp_volume_request(mdp_volume_request),

	.mdp_playing(mdp_hps_playing),
	.mdp_current_track(mdp_hps_current_track),

	.audio_rd_ptr(mdp_audio_rd_ptr),
	.audio_wr_ptr(mdp_audio_wr_ptr),
	.audio_active(mdp_audio_active)
);

md_plus md_plus
(
	.clk(clk_sys),
	.reset(sys_reset),

	.cart_addr(cart_addr),
	.cart_data_wr(cart_data_wr),
	.cart_cs(cart_cs),
	.cart_oe(cart_oe),
	.cart_lwr(cart_lwr),
	.cart_uwr(cart_uwr),

	.mdp_data_en(mdp_data_en),
	.mdp_data_out(mdp_data_out),
	.mdp_dtack(mdp_dtack),

	.mdp_track_request(mdp_track_request),
	.mdp_track_num(mdp_track_num),
	.mdp_track_loop(mdp_track_loop),
	.mdp_stop_request(mdp_stop_request),
	.mdp_fade_sectors(mdp_fade_sectors),
	.mdp_resume_request(mdp_resume_request),
	.mdp_volume(mdp_volume),
	.mdp_volume_request(mdp_volume_request),

	.mdp_playing(mdp_hps_playing),
	.mdp_current_track(mdp_hps_current_track),

	.mdp_active(mdp_active),
	.mdp_last_cmd(mdp_last_cmd)
);

// CDDA audio output from mdp_audio
wire signed [15:0] cdda_l, cdda_r;

mdp_audio mdp_audio
(
	.clk(clk_sys),
	.reset(sys_reset),

	// DDRAM interface
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

	// Ring buffer pointers (from/to hps_ext)
	.active(mdp_audio_active),
	.buf_wr_ptr(mdp_audio_wr_ptr),
	.buf_rd_ptr(mdp_audio_rd_ptr),

	// MD+ commands (directly from md_plus)
	.track_start(mdp_track_request),
	.stop_request(mdp_stop_request),
	.fade_sectors(mdp_fade_sectors),
	.volume(mdp_volume),
	.resume_request(mdp_resume_request),
	.osd_pause(OSD_STATUS & status[61]),

	// Audio output
	.audio_l(cdda_l),
	.audio_r(cdda_r)
);


///////////////////////////////////////////////////

reg new_vmode;
always @(posedge clk_sys) begin
	reg old_pal;
	int to;

	if(~sys_reset) begin
		old_pal <= PAL;
		if(old_pal != PAL) to <= 5000000;
	end
	else to <= 5000000;

	if(to) begin
		to <= to - 1;
		if(to == 1) new_vmode <= ~new_vmode;
	end
end

wire       ce_pix;
wire       f1;
wire       interlace;
wire       vblank_c, hblank_c, hs_c, vs_c;
wire [7:0] r_c, g_c, b_c;
wire[11:0] arx,ary;

// CLK_VIDEO is clk_md/2 at a phase the PLL leaves open: hold the VDP video for two clk_md,
// loading on the clocks vdp_hclk1 changes on, so video_cond sees each value once at either phase.
reg  [7:0] vh_r, vh_g, vh_b;
reg        vh_hs, vh_vs, vh_hclk1, vh_de_h, vh_de_v, vh_intfield, vh_m2, vh_m5, vh_rs1;
reg        vh_ph, vh_h1d;
always @(posedge clk_md) begin
	vh_h1d <= vdp_hclk1;
	vh_ph <= ~vh_ph & (vh_h1d == vdp_hclk1);
	if(vh_ph) {vh_r, vh_g, vh_b, vh_hs, vh_vs, vh_hclk1, vh_de_h, vh_de_v, vh_intfield, vh_m2, vh_m5, vh_rs1}
		<= {r, g, b, hs, vs, vdp_hclk1, vdp_de_h, vdp_de_v, vdp_intfield, vdp_m2, vdp_m5, vdp_rs1};
end

video_cond video_cond
(
	.clk(CLK_VIDEO),

	.vdp_hclk1(vh_hclk1),
	.vdp_de_h(vh_de_h),
	.vdp_de_v(vh_de_v),
	.vdp_intfield(vh_intfield),
	.vdp_m2(vh_m2),
	.vdp_m5(vh_m5),
	.vdp_rs1(vh_rs1),

	.r_in(vh_r),
	.g_in(vh_g),
	.b_in(vh_b),
	.hs_in(vh_hs),
	.vs_in(vh_vs),

	.pal(PAL),
	.border_en(status[29]),
	.h40corr(status[30]),
	.blender(status[46]),

	.arx(arx),
	.ary(ary),

	.ce_pix(ce_pix),
	.interlace(interlace),
	.f1(f1),

	.r_out(r_c),
	.g_out(g_c),
	.b_out(b_c),
	.hs_out(hs_c),
	.vs_out(vs_c),
	.hbl_out(hblank_c),
	.vbl_out(vblank_c)
);

wire [2:0] scale = status[3:1];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

assign VGA_SL = {~interlace,~interlace}&sl[1:0];
assign VGA_F1 = f1;

// Mega-Tech: OSD "Screen" shows the menu monitor (BIOS VDP, 256x224, pixel = master/10) instead of the game.
// TIME UP: the BIOS draws it into the game's VDP (main monitor); we draw the same text on the game screen's own
// timing, so the output video mode never changes (no scaler re-sync). FLASH (io2 port E bit 1, last seconds):
// whole picture at half brightness (OSD "Dim", default) or the VDP's shadow mode ("Shadow", see md_board ext_ste).
// TIME UP end (Tom, 2026-10-25: "game, TIME UP 3.8 s, black, title"): when TIME UP ends, or a cart select
// restarts the game, the game screen stays black (and the game sound muted) until the restarted game has turned
// its display off and on again (VDP register 1 bit 6), at least 16 frames after the last CPU reset (the BIOS
// releases the 68k ~9 frames before its cart select restarts it again), at most 4 s.
wire menu_on = status[64];
// TEST MODE (BIOS test menu, entered with Test pressed and released): drawn by the BIOS into the game's VDP in
// Mode 4; shown here from mt_bios's second Mode 4 VDP in its own timing (the scaler re-syncs once, as for the
// OSD menu screen)
reg  [1:0] mt_test_s;
always @(posedge CLK_VIDEO) mt_test_s <= {mt_test_s[0], mt_test_on};
wire bios_vid = ~menu_on & mt_test_s[1];
reg  mt_tu_on, mt_tu_vb, mt_blk, mt_blk_on, mt_seen0;
reg  [1:0] mt_tu_s, mt_disp_s, mt_hold_s, mt_sel_s;
reg  [4:0] mt_rel_cnt;
reg  [7:0] mt_blk_cnt;
always @(posedge CLK_VIDEO) begin
	mt_tu_s   <= {mt_tu_s[0], mt_timeup};
	mt_disp_s <= {mt_disp_s[0], vdp_disp};
	mt_hold_s <= {mt_hold_s[0], mt_hold_68k | mt_hold_z80};
	mt_sel_s  <= {mt_sel_s[0], mt_sel_rst};
	mt_tu_vb  <= vblank_c;
	if (mt_tu_s[1] | mt_sel_s[1]) begin
		mt_blk <= 1; mt_seen0 <= 0; mt_blk_cnt <= 0; mt_rel_cnt <= 0;
	end else if (mt_blk) begin
		if (mt_hold_s[1]) begin mt_seen0 <= 0; mt_rel_cnt <= 0; end
		else if (!mt_disp_s[1]) mt_seen0 <= 1;
		if (vblank_c & ~mt_tu_vb) begin
			if (!mt_hold_s[1] && mt_rel_cnt != 5'd31) mt_rel_cnt <= mt_rel_cnt + 1'd1;
			mt_blk_cnt <= mt_blk_cnt + 1'd1;
			if ((mt_seen0 && mt_disp_s[1] && mt_rel_cnt >= 5'd16) || mt_blk_cnt == 8'd240) mt_blk <= 0;
		end
	end
	if (vblank_c & ~mt_tu_vb) begin
		mt_tu_on  <= ~menu_on & mt_timeup;
		mt_blk_on <= ~menu_on & mt_blk;
	end
end
assign mt_game_black = mt_tu_s[1] | mt_blk | mt_hold_s[1];
// the BIOS toggles FLASH on the menu VDP's frame, not the game's: take it only at the start of the game's vblank,
// so a game frame is never part dim / part bright (Tom, test e: a darker band at a random height)
wire mt_flash_raw = ~menu_on & ~mt_timeup & mt_porte[1] & (cart_ms | ~status[67]);
reg  [1:0] mt_flash_s;
reg  mt_flash, mt_flash_vb;
always @(posedge CLK_VIDEO) begin
	mt_flash_s <= {mt_flash_s[0], mt_flash_raw};
	mt_flash_vb <= vblank_c;
	if (vblank_c & ~mt_flash_vb) mt_flash <= mt_flash_s[1];
end

// TIME UP text position from the game video's blanking, counted in CLK_VIDEO (= MD master clock) ticks, not in
// game pixels: the active line is 2560 ticks in both H32 (256 x 10) and H40 (320 x 8), so the text keeps its size
// and place while the game side changes mode underneath (BIOS restarts it during TIME UP). Text = 108 x 13 pixels
// of 10 ticks (the BIOS draws it in 256-wide mode 4), at line 105 of a 224-line screen (BIOS: rows 98+, 192 lines
// centred in 224 -> same place).
reg  [11:0] mt_gt;        // ticks since the active line started
reg  [3:0]  mt_gp;        // 10-tick prescaler
reg  [8:0]  mt_tux, mt_gy, mt_tuy;
reg         mt_ghb, mt_gvb;
always @(posedge CLK_VIDEO) begin
	mt_ghb <= hblank_c; mt_gvb <= vblank_c;
	if (hblank_c) begin
		mt_gt <= 0; mt_gp <= 0; mt_tux <= 9'h1ff;
		if (!mt_ghb && !vblank_c) mt_gy <= mt_gy + 1'd1;
	end else begin
		mt_gt <= mt_gt + 1'd1;
		if (mt_gt == 12'd740) begin mt_tux <= 0; mt_gp <= 0; end
		else if (mt_gp == 4'd9) begin mt_gp <= 0; if (mt_tux != 9'h1ff) mt_tux <= mt_tux + 1'd1; end
		else mt_gp <= mt_gp + 1'd1;
	end
	if (vblank_c) mt_gy <= 0;
	mt_tuy <= mt_gy - 9'd105;
end
wire       mt_tu_px;
wire [7:0] mt_tu_r = mt_tu_px ? 8'hff : 8'h00;
wire [7:0] mt_tu_g = mt_tu_px ? 8'hff : status[66] ? 8'h55 : 8'h00;
wire [7:0] mt_tu_b = mt_tu_px ? 8'hff : status[66] ? 8'hff : 8'h00;

// game picture with the Mega-Tech overlays (TIME UP, black, FLASH) and the light gun target
wire [7:0] mt_gr = mt_tu_on ? mt_tu_r : mt_blk_on ? 8'h00 : mt_flash ? {1'b0,r_c[7:1]} : (lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[0]}} : r_c;
wire [7:0] mt_gg = mt_tu_on ? mt_tu_g : mt_blk_on ? 8'h00 : mt_flash ? {1'b0,g_c[7:1]} : (lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[1]}} : g_c;
wire [7:0] mt_gb = mt_tu_on ? mt_tu_b : mt_blk_on ? 8'h00 : mt_flash ? {1'b0,b_c[7:1]} : (lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[2]}} : b_c;
`ifdef MEGAPLAY
// Mega Play overlay: the BIOS VDP is phase-locked to the game picture (mp_sync toggles at the game's first active
// pixel; same line and frame length), so its 256 pixels of 10 master clocks span the game's 2560-clock active line
// (stretched 5:4 over H40, as MAME notes). Its pixel goes over the game where its colour index bits 3-0 are not 0.
reg       mp_gvb, mp_sync_r;
reg [6:0] mp_o1, mp_o2, mp_ov;
always @(posedge CLK_VIDEO) begin
	if (ce_pix) begin mp_gvb <= vblank_c; if (mp_gvb & ~vblank_c) mp_sync_r <= ~mp_sync_r; end
	mp_o1 <= {mp_y1, mp_r, mp_g, mp_b};    // other clock (same frequency): take a value only once it is stable
	mp_o2 <= mp_o1;
	if (mp_o1 == mp_o2) mp_ov <= mp_o2;
end
assign mp_sync = mp_sync_r;
wire [7:0] vo_r = mp_ov[6] ? {4{mp_ov[5:4]}} : mt_gr;
wire [7:0] vo_g = mp_ov[6] ? {4{mp_ov[3:2]}} : mt_gg;
wire [7:0] vo_b = mp_ov[6] ? {4{mp_ov[1:0]}} : mt_gb;
`else
wire [7:0] vo_r = mt_gr, vo_g = mt_gg, vo_b = mt_gb;
`endif

// Side by side (OSD): game screen left, menu screen right, as the cabinet's two monitors (TEST MODE keeps the
// full screen)
`ifdef MT_SBS
assign     sbs_vid = status[68] & ~bios_vid;
wire       sbs_sync, sbs_ce, sbs_hbl, sbs_vbl, sbs_hs, sbs_vs;
wire [7:0] sbs_r, sbs_g, sbs_b;
mt_sbs mt_sbs
(
	.clk(CLK_VIDEO),
	.g_ce(ce_pix), .g_r(mt_gr), .g_g(mt_gg), .g_b(mt_gb),
	.g_hbl(hblank_c), .g_vbl(vblank_c), .g_hs(hs_c), .g_vs(vs_c),
	.sync_tgl(sbs_sync),
	.clk_m(clk_sys), .m_ce(mt_ce_pix), .m_r(mt_r), .m_g(mt_g), .m_b(mt_b), .m_hbl(mt_hbl), .m_vbl(mt_vbl),
	.ce(sbs_ce), .r(sbs_r), .g(sbs_g), .b(sbs_b), .hbl(sbs_hbl), .vbl(sbs_vbl), .hs(sbs_hs), .vs(sbs_vs)
);
`else
assign     sbs_vid = 0;
wire       sbs_sync = 0, sbs_ce = 0, sbs_hbl = 0, sbs_vbl = 0, sbs_hs = 0, sbs_vs = 0;
wire [7:0] sbs_r = 0, sbs_g = 0, sbs_b = 0;
`endif

wire mt_menu_vid = menu_on & ~sbs_vid;
`ifdef MT_SBS
video_mixer #(.LINE_LENGTH(640), .GAMMA(1)) video_mixer
`else
video_mixer #(.LINE_LENGTH(400), .GAMMA(1)) video_mixer
`endif
(
	.*,
	.ce_pix(sbs_vid ? sbs_ce : (mt_menu_vid | bios_vid) ? mt_ce_pix : ce_pix),

	.scandoubler(~interlace && (scale || forced_scandoubler)),
	.hq2x(scale==1),
	.freeze_sync(),

	.VGA_DE(vga_de),
	.R(sbs_vid ? sbs_r : mt_menu_vid ? {4{mt_r}} : bios_vid ? {4{mt_t_r}} : vo_r),
	.G(sbs_vid ? sbs_g : mt_menu_vid ? {4{mt_g}} : bios_vid ? {4{mt_t_g}} : vo_g),
	.B(sbs_vid ? sbs_b : mt_menu_vid ? {4{mt_b}} : bios_vid ? {4{mt_t_b}} : vo_b),

	// Positive pulses.
	.HSync(sbs_vid ? sbs_hs : mt_menu_vid ? mt_hs : bios_vid ? mt_t_hs : hs_c),
	.VSync(sbs_vid ? sbs_vs : mt_menu_vid ? mt_vs : bios_vid ? mt_t_vs : vs_c),
	.HBlank(sbs_vid ? sbs_hbl : mt_menu_vid ? mt_hbl : bios_vid ? mt_t_hbl : hblank_c),
	.VBlank(sbs_vid ? sbs_vbl : mt_menu_vid ? mt_vbl : bios_vid ? mt_t_vbl : vblank_c)
);


///////////////////////////////////////////////////

// FM + PSG base audio (before CDDA mix)
wire [15:0] base_audio_l, base_audio_r;

audio_cond audio_cond
(
	.clk(clk_sys),
	.reset(sys_reset),
	.mute(~clk_en | dma_z80_req | mt_game_black),

	.lpf_mode(status[15:14]),
	.fm_mode(status[11]),

	.fm_clk1(fm_clk1),
	.fm_sel23(fm_sel23),
	.MOL(MOL),
	.MOR(MOR),
	.MOL_2612(MOL_2612),
	.MOR_2612(MOR_2612),
	.PSG(PSG),
	.sms_fm_audio(sms_fm_audio),

	.AUDIO_L(base_audio_l),
	.AUDIO_R(base_audio_r)
);

// Attenuate CDDA: 93/256 ≈ 0.363 — matched to Mega Drive hardware output via A/B recording comparisons
wire signed [24:0] cdda_scaled_l = $signed(cdda_l) * $signed(9'd93);
wire signed [24:0] cdda_scaled_r = $signed(cdda_r) * $signed(9'd93);
wire signed [15:0] cdda_att_l = cdda_scaled_l[23:8];
wire signed [15:0] cdda_att_r = cdda_scaled_r[23:8];

// Saturating mix: FM/PSG + attenuated CDDA
// Mega-Tech: optional coin beep (OSD "Coin Sound", off by default: the real board makes no coin sound)
// 1 kHz square wave for 0.1 s on each coin press (clk_sys = 53.69 MHz)
reg        mt_beep_on = 0;
reg [22:0] mt_beep_len;
reg [15:0] mt_beep_div;
reg        mt_beep_sq, mt_coin_d;
always @(posedge clk_sys) begin
	mt_coin_d <= joystick_0[12] | joystick_1[12];
	if (status[65] && (joystick_0[12] | joystick_1[12]) && !mt_coin_d) begin mt_beep_on <= 1; mt_beep_len <= 23'd5369317; end
	else if (mt_beep_len) mt_beep_len <= mt_beep_len - 1'd1;
	else mt_beep_on <= 0;
	if (mt_beep_div) mt_beep_div <= mt_beep_div - 1'd1;
	else begin mt_beep_div <= 16'd26846; mt_beep_sq <= ~mt_beep_sq; end
end
wire signed [15:0] mt_beep_s = mt_beep_on ? (mt_beep_sq ? 16'sd3000 : -16'sd3000) : 16'sd0;

// Mega-Tech: menu-board PSG added at 1/8 of full scale (level not measured on hardware)
wire signed [15:0] mt_snd_s = {mt_snd, 5'd0} >>> 2;
wire signed [16:0] mix_l = $signed(base_audio_l) + $signed(cdda_att_l) + mt_snd_s + mt_beep_s;
wire signed [16:0] mix_r = $signed(base_audio_r) + $signed(cdda_att_r) + mt_snd_s + mt_beep_s;

assign AUDIO_L = (mix_l[16] != mix_l[15]) ? {mix_l[16], {15{~mix_l[16]}}} : mix_l[15:0];
assign AUDIO_R = (mix_r[16] != mix_r[15]) ? {mix_r[16], {15{~mix_r[16]}}} : mix_r[15:0];

assign AUDIO_MIX = status[58:57];


/////////////////////////  Mega-Tech BIOS side  /////////////////////////

// DIP switches from the MRA (ioctl index 254): byte 0 = BIOS_DSW0, byte 1 = BIOS_DSW1 (MAME)
reg [7:0] mt_dsw0 = 8'h7f, mt_dsw1 = 8'ha1;
always @(posedge clk_sys) if (ioctl_wr && ioctl_index == 8'd254 && !ioctl_addr[24:1]) {mt_dsw1, mt_dsw0} <= ioctl_data;

// mt_game_reset declared with mt_cart_sel
// The BIOS side has its own reset: sys_reset also follows the game reset that the BIOS itself triggers
// (then: cart select -> game reset -> loading -> sys_reset), which made the BIOS reset itself in a loop (test 2: black).
reg mt_bios_rst = 1;
// NVRAM (MRA <nvram index="4" size="8192">): MiSTer loads it from the SD card after the ROMs (the BIOS is held in
// reset meanwhile and then boots with the saved settings) and saves it whenever the OSD is opened.
wire mt_nv_dl = ioctl_download & (ioctl_index == 8'd9);
always @(posedge clk_sys) mt_bios_rst <= RESET | status[0] | buttons[1] | mt_download | mt_slot_dl | mt_nv_dl;

// Select (= next cart, restarts the game side on the real board) only after a ~1 s hold, so an accidental
// press on a pad shoulder doesn't restart the game. Then a 0.2 s press is passed to the BIOS.
reg [25:0] mt_sel_hold = 0;
reg [23:0] mt_sel_out  = 0;
always @(posedge clk_sys) begin
	if (joystick_0[13] | joystick_1[13]) begin
		if (mt_sel_hold != 26'd53693175) mt_sel_hold <= mt_sel_hold + 1'd1;
		if (mt_sel_hold == 26'd53693174) mt_sel_out <= 24'd10738635;
	end else mt_sel_hold <= 0;
	if (mt_sel_out) mt_sel_out <= mt_sel_out - 1'd1;
end
wire mt_sel_pulse = |mt_sel_out;

`ifdef MDBOOT
// MD bootlegs: no BIOS, one game; the board I/O sits on the cartridge bus (mdb_io)
assign mt_cart_sel = 3'd0;
assign mt_game_reset = 1'b0;
assign mt_portd = 8'h30;
assign mt_porte = 4'b1000;
assign mt_timeup = 0;
assign mt_test_on = 0;
assign {mt_r, mt_g, mt_b, mt_hs, mt_vs, mt_hbl, mt_vbl, mt_ce_pix} = 0;
assign {mt_t_r, mt_t_g, mt_t_b, mt_t_hs, mt_t_vs, mt_t_hbl, mt_t_vbl} = 0;
assign mt_tu_px = 0;
assign mt_snd = 0;
assign mt_ins_req = 1'b0;
assign mt_ins_wa = 24'd0;
assign mt_nv_dout = 16'd0;
assign mt_nv_chg = 1'b0;
wire mt_pad_en = 1'b1;
assign mt_sel_rst = 1'b0;
assign mt_hold_68k = 1'b0;
assign mt_hold_z80 = 1'b0;

mdb_io mdb_io
(
	.clk(clk_sys),
	.reset(sys_reset),
	.family(mdb_family),
	.prot_hi(mdb_prot_hi),
	.prot_val(mdb_prot_val),
	.dsw(mdb_dsw),
	.coin1(joystick_0[8] | mt_kb[0]),   // pad Select
	.coin2(joystick_1[8] | mt_kb[1]),
	.pic_wr(mdb_pic_wr),
	.pic_wa(ioctl_addr[11:1]),
	.pic_wd(ioctl_data[11:0]),
	.addr(cart_addr),
	.oe(cart_oe),
	.lwr(cart_lwr),
	.uwr(cart_uwr),
	.din(cart_data_wr),
	.dout(mdb_dout),
	.den(mdb_den),
	.dtack(mdb_dtack),
	.bank(mdb_bank),
	.nmi(mdb_nmi),
	.exp_coin_n(mdb_exp_coin_n)
);
`elsif MEGAPLAY
// Mega Play: one BIOS board (mp_bios) next to the game. The game's pads stay connected; the BIOS hands the
// Start buttons to the game (io1 port D bits 4/5) and talks to the 68000 through I/O port C and the shared RAM IC36.
reg  [2:0] mp_exp_lo_s1, mp_exp_lo_s2;
always @(posedge clk_sys) begin
	mp_exp_lo_s1 <= PC_o[2:0] | PC_d[2:0];       // 68000 outputs (inputs read high)
	mp_exp_lo_s2 <= mp_exp_lo_s1;
end
mp_bios mp_bios
(
	.clk(clk_sys),
	.reset(mt_bios_rst),

	.dl(mt_download & ~|ioctl_addr[24:14]),
	.dl_addr(ioctl_addr),
	.dl_data(ioctl_data),
	.dl_wr(ioctl_wr),
	.nv_dl(mt_nv_dl),
	.nv_wr(ioctl_wr),
	.nv_addr(ioctl_addr[12:0]),
	.nv_din(ioctl_data),
	.nv_dout(mt_nv_dout),
	.nv_chg(mt_nv_chg),

	.rom_wa(mt_ins_wa), .rom_req(mt_ins_req), .rom_ack(mt_ins_ack), .rom_data(mt_ins_data),

	.coin1(joystick_0[12] | mt_kb[0]),
	.coin2(joystick_1[12] | mt_kb[1]),
	.service_coin(joystick_0[14] | joystick_1[14] | mt_kb[4]),   // pad "Service": also moves the TEST MODE cursor
	.start1(joystick_0[7] | mt_kb[2]),
	.start2(joystick_1[7] | mt_kb[3]),
	.sel_btn(mt_sel_pulse | mt_kb[5]),     // pad Select after the ~1 s hold above (as Mega-Tech), key at once
	.service(joystick_0[15] | mt_kb[7]),
	.dsw0(mt_dsw0),
	.dsw1(mt_dsw1),
	.four_slot(mp_four),
	.present(mt_present[3:0]),
	.dsw_x({mt_present[3] ? mp_dsw_s[3] : 4'hf, mt_present[2] ? mp_dsw_s[2] : 4'hf, mt_present[1] ? mp_dsw_s[1] : 4'hf}),
	.slot(mp_slot),

	.start_n(mp_start_n),
	.game_reset(mt_game_reset),
	.exp_lo(mp_exp_lo_s2),
	.exp_hi(mp_exp_hi),

	.zb_clk(clk_md), .zb_a(ram_z80_address), .zb_d(ram_z80_data), .zb_we(ram_z80_wren & ram_z80_a13), .zb_q(mp_ic36_q),

	.r(mp_r), .g(mp_g), .b(mp_b), .y1(mp_y1),
	.hs(), .vs(), .hblank(), .vblank(),
	.ce_pix(mt_ce_pix),
	.sync_tgl(mp_sync),
	.snd(mt_snd)
);
reg [1:0] mp_slot_q = 0;                 // registered: keeps the BIOS register out of the cart read path's timing
always @(posedge clk_sys) mp_slot_q <= mp_slot;
assign mt_cart_sel = {1'b0, mp_slot_q};
assign mt_portd = 8'h30;                 // Mega-Tech-only controls idle: pads on, no CPU hold, no TIME UP
assign mt_porte = 4'b1000;
assign mt_timeup = 0;
assign mt_test_on = 0;
assign {mt_r, mt_g, mt_b, mt_hs, mt_vs, mt_hbl, mt_vbl} = 0;
assign {mt_t_r, mt_t_g, mt_t_b, mt_t_hs, mt_t_vs, mt_t_hbl, mt_t_vbl} = 0;
assign mt_tu_px = 0;
wire mt_pad_en = 1'b1;
// 68000 reset from the BIOS (io2 port E bits 3-2 00 -> 11, MAME pulse_input_line): hold it ~1.2 ms
reg [15:0] mt_hold_cnt = 0;
always @(posedge clk_sys) begin
	if (mt_game_reset) mt_hold_cnt <= 16'hffff;
	else if (mt_hold_cnt) mt_hold_cnt <= mt_hold_cnt - 1'd1;
end
assign mt_sel_rst = 1'b0;
reg [1:0] mt_h68_s;
always @(posedge clk_md) mt_h68_s <= {mt_h68_s[0], |mt_hold_cnt};
assign mt_hold_68k = mt_h68_s[1];
assign mt_hold_z80 = 1'b0;
`else
mt_bios mt_bios
(
	.clk(clk_sys),
	.reset(mt_bios_rst),

	.dl(mt_download & ~|ioctl_addr[24:16]),
	.dl_addr(ioctl_addr),
	.dl_data(ioctl_data),
	.dl_wr(ioctl_wr),
	.nv_dl(mt_nv_dl),
	.nv_wr(ioctl_wr),
	.nv_addr(ioctl_addr[12:0]),
	.nv_din(ioctl_data),
	.nv_dout(mt_nv_dout),
	.nv_chg(mt_nv_chg),

	.coin1(joystick_0[12] | mt_kb[0]),
	.coin2(joystick_1[12] | mt_kb[1]),
	.service_coin(mt_kb[4]),
	.start1(joystick_0[7] | mt_kb[2]),
	.start2(joystick_1[7] | mt_kb[3]),
	.sel_btn(mt_sel_pulse | mt_kb[5] | (mt_test_on & (joystick_0[13] | joystick_1[13]))),   // TEST MODE: pad Select at once
	.enter_btn(joystick_0[14] | joystick_1[14] | mt_kb[6]),
	.service(joystick_0[15] | mt_kb[7]),
	.door1(1'b0),
	.door2(1'b0),
	.dsw0(mt_dsw0),
	.dsw1(mt_dsw1),
	.cart_present(~mt_present),    // active low: slots loaded from the MRA (1) and the OSD (2-8)
	.pad1(~{joystick_0[6], joystick_0[5], joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]}),
	.pad2(~{joystick_1[6], joystick_1[5], joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3]}),
	.pad1_a(~joystick_0[4]),
	.pad2_a(~joystick_1[4]),

	.cart_sel(mt_cart_sel),
	.ins_a(mt_ins_a), .ins_req(mt_ins_req), .ins_ack(mt_ins_ack), .ins_data(mt_ins_data),   // instruction ROMs in SDRAM
	.game_reset(mt_game_reset),
	.portd(mt_portd),
	.porte(mt_porte),

	.r(mt_r), .g(mt_g), .b(mt_b),
	.hs(mt_hs), .vs(mt_vs), .hblank(mt_hbl), .vblank(mt_vbl),
	.ce_pix(mt_ce_pix),
	.sync_tgl(sbs_sync), .sync_en(status[68]),
	.snd(mt_snd),
	.tu_x(mt_tux), .tu_y(mt_tuy), .tu_px(mt_tu_px),
	.timeup(mt_timeup),
	.test_on(mt_test_on),
	.t_r(mt_t_r), .t_g(mt_t_g), .t_b(mt_t_b),
	.t_hs(mt_t_hs), .t_vs(mt_t_vs), .t_hblank(mt_t_hbl), .t_vblank(mt_t_vbl)
);

assign mt_ins_wa = {1'b1, 6'd0, mt_ins_slot, mt_ins_a};
// RetroSix "Coin Meter": io2 port D2 (no credits) or D3 high disables the Mega Drive controller buffers
wire mt_pad_en = ~(mt_portd[2] | mt_portd[3]);

// Game CPU resets from the BIOS, as on the board: only the CPUs, never the VDP. A full reset (as before
// 2026-10-25) restarted the VDP, so the video lost sync for a moment when TIME UP began and again when the game
// restarted (Tom: a brief glitch at both). The 68k is held while
//  - a cart select restarts the game side (MAME switch_cart), ~1.2 ms,
//  - io2 port E bit 3 is low (X3 -> PAL 315-5347 -> 68k reset),
//  - io2 port D bit 4 is low (the BIOS takes the 68k's bus for the header read and for TIME UP; BIOS 0x20b2).
// The game's Z80 also while port D bit 5 is low (inverter -> OR -> Z80 reset, RetroSix), so SMS carts stop too.
reg [15:0] mt_hold_cnt = 0;
always @(posedge clk_sys) begin
	if (mt_game_reset) mt_hold_cnt <= 16'hffff;
	else if (mt_hold_cnt) mt_hold_cnt <= mt_hold_cnt - 1'd1;
end
assign mt_sel_rst = |mt_hold_cnt;
reg [1:0] mt_h68_s, mt_hz_s;
always @(posedge clk_md) begin
	mt_h68_s <= {mt_h68_s[0], mt_sel_rst | ~mt_porte[3] | ~mt_portd[4]};
	mt_hz_s  <= {mt_hz_s[0],  mt_sel_rst | ~mt_porte[3] | ~mt_portd[4] | ~mt_portd[5]};
end
assign mt_hold_68k = mt_h68_s[1];
assign mt_hold_z80 = mt_hz_s[1];
`endif

///////////////////////////////////////////////////

reg  [1:0] region_req;
reg        region_set = 0;
reg        region_set_rst = 0;

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state, old_ready = 0;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		// Mega-Tech: the console's F1-F3 region keys (they also reset the core) are replaced by MAME's cabinet
		// keys: 5/6 coin, 1/2 start, 9 service coin, 0 select, - enter, F2 test (held, as MAME's service switch)
		case(code)
			'h02E: mt_kb[0] <= pressed; // 5 coin 1
			'h036: mt_kb[1] <= pressed; // 6 coin 2
			'h016: mt_kb[2] <= pressed; // 1 start 1
			'h01E: mt_kb[3] <= pressed; // 2 start 2
			'h046: mt_kb[4] <= pressed; // 9 service coin
			'h045: mt_kb[5] <= pressed; // 0 select
			'h04E: mt_kb[6] <= pressed; // - enter
			'h006: mt_kb[7] <= pressed; // F2 test
			default: ;
		endcase
	end

	old_ready <= cart_hdr_ready;
	// Mega-Tech: MAME uses the export NTSC version register (init_megadriv, 0xa0) = US for every cart.
	if(~cart_ms & ~old_ready & cart_hdr_ready) begin
		region_set <= 1;
		region_req <= 1;
	end

	if(old_ready & ~cart_hdr_ready) region_set <= 0;
end

wire [3:0] hrgn = ioctl_data[3:0] - 4'd7;

reg cart_hdr_ready = 0;
reg hdr_j=0,hdr_u=0,hdr_e=0;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= cart_download;

	if(~old_download && cart_download) {hdr_j,hdr_u,hdr_e} <= 0;
	if(old_download && ~cart_download) cart_hdr_ready <= 0;

	if(cart_wr_dl & cart_download) begin
		if(cart_addr_dl == 'h1F0) begin
			if(ioctl_data[7:0] == "J") hdr_j <= 1;
			else if(ioctl_data[7:0] == "U") hdr_u <= 1;
			else if(ioctl_data[7:0] == "E") hdr_e <= 1;
			else if(ioctl_data[7:0] >= "0" && ioctl_data[7:0] <= "9") {hdr_e, hdr_u, hdr_j} <= {ioctl_data[3], ioctl_data[2], ioctl_data[0]};
			else if(ioctl_data[7:0] >= "A" && ioctl_data[7:0] <= "F") {hdr_e, hdr_u, hdr_j} <= {      hrgn[3],       hrgn[2],       hrgn[0]};
		end
		if(cart_addr_dl == 'h1F2) begin
			if(ioctl_data[7:0] == "J") hdr_j <= 1;
			else if(ioctl_data[7:0] == "U") hdr_u <= 1;
			else if(ioctl_data[7:0] == "E") hdr_e <= 1;
		end
		if(cart_addr_dl == 'h1F0) begin
			if(ioctl_data[15:8] == "J") hdr_j <= 1;
			else if(ioctl_data[15:8] == "U") hdr_u <= 1;
			else if(ioctl_data[15:8] == "E") hdr_e <= 1;
		end
		if(cart_addr_dl == 'h200) cart_hdr_ready <= 1;
	end
end

///////////////////////////////////////////////////

wire [11:0] joy0 = mt_pad_en ? (status[4] ? joystick_1[11:0] : joystick_0[11:0]) : 12'd0;
wire [11:0] joy1 = mt_pad_en ? (status[4] ? joystick_0[11:0] : joystick_1[11:0]) : 12'd0;

wire [6:0] md_io_port1, md_io_port2;

wire [15:0] jcart_data;
wire        jcart_th;

md_io md_io
(
	.clk(clk_sys),
	.reset(sys_reset),

`ifdef MDBOOT
	.MODE(mdb_flags[0]), // MD bootlegs: 6-button pads on the Actel 6-button boards (MAME ctrl1_6button)
`else
	.MODE(1'b0),        // Mega-Tech: integrated 3-button pads (MAME ctrl1_3button); some carts misread a 6-button pad
`endif
	.SMS(cart_ms),
	.MULTITAP(cart_ms ? {|status[39:37], 1'b0} : status[38:37]),

	.P1_UP(joy0[3]),
	.P1_DOWN(joy0[2]),
	.P1_LEFT(joy0[1]),
	.P1_RIGHT(joy0[0]),
	.P1_A(joy0[4]),
	.P1_B(joy0[5] | (cart_ms & (joy0[4] | joy0[7]))), // SMS carts: A and Start also = button 1 ("PUSH START BUTTON")
	.P1_C(joy0[6]),
`ifdef MEGAPLAY
	.P1_START(~mp_start_n[0]),           // Mega Play: Start reaches the game through the BIOS (io1 port D bit 4)
`else
	.P1_START(joy0[7]),
`endif
`ifdef MDBOOT
	.P1_MODE(1'b0),  // bit 8 is the coin here
`else
	.P1_MODE(joy0[8]),
`endif
	.P1_X(joy0[9]),
	.P1_Y(joy0[10]),
	.P1_Z(joy0[11]),

	.P2_UP(joy1[3]),
	.P2_DOWN(joy1[2]),
	.P2_LEFT(joy1[1]),
	.P2_RIGHT(joy1[0]),
	.P2_A(joy1[4]),
	.P2_B(joy1[5] | (cart_ms & (joy1[4] | joy1[7]))), // SMS carts: A and Start also = button 1
	.P2_C(joy1[6]),
`ifdef MEGAPLAY
	.P2_START(~mp_start_n[1]),
`else
	.P2_START(joy1[7]),
`endif
`ifdef MDBOOT
	.P2_MODE(1'b0),  // bit 8 is the coin here
`else
	.P2_MODE(joy1[8]),
`endif
	.P2_X(joy1[9]),
	.P2_Y(joy1[10]),
	.P2_Z(joy1[11]),

	.P3_UP(joystick_2[3]),
	.P3_DOWN(joystick_2[2]),
	.P3_LEFT(joystick_2[1]),
	.P3_RIGHT(joystick_2[0]),
	.P3_A(joystick_2[4]),
	.P3_B(joystick_2[5]),
	.P3_C(joystick_2[6]),
	.P3_START(joystick_2[7]),
	.P3_MODE(joystick_2[8]),
	.P3_X(joystick_2[9]),
	.P3_Y(joystick_2[10]),
	.P3_Z(joystick_2[11]),

	.P4_UP(joystick_3[3]),
	.P4_DOWN(joystick_3[2]),
	.P4_LEFT(joystick_3[1]),
	.P4_RIGHT(joystick_3[0]),
	.P4_A(joystick_3[4]),
	.P4_B(joystick_3[5]),
	.P4_C(joystick_3[6]),
	.P4_START(joystick_3[7]),
	.P4_MODE(joystick_3[8]),
	.P4_X(joystick_3[9]),
	.P4_Y(joystick_3[10]),
	.P4_Z(joystick_3[11]),

	.P5_UP(joystick_4[3]),
	.P5_DOWN(joystick_4[2]),
	.P5_LEFT(joystick_4[1]),
	.P5_RIGHT(joystick_4[0]),
	.P5_A(joystick_4[4]),
	.P5_B(joystick_4[5]),
	.P5_C(joystick_4[6]),
	.P5_START(joystick_4[7]),
	.P5_MODE(joystick_4[8]),
	.P5_X(joystick_4[9]),
	.P5_Y(joystick_4[10]),
	.P5_Z(joystick_4[11]),

	.GUN_OPT(|gun_mode),
	.GUN_TYPE(gun_type),
	.GUN_SENSOR(lg_sensor),
	.GUN_A(lg_a),
	.GUN_B(lg_b),
	.GUN_C(lg_c),
	.GUN_START(lg_start),

	.MOUSE(ps2_mouse),
	.MOUSE_OPT(status[20:18]),

	.jcart_data(jcart_data),
	.jcart_th(jcart_th),

	.port1_out(md_io_port1),
	.port1_in(PA_o  | {7{snac_port1}}),
	.port1_dir(PA_d | {7{snac_port1}}),

	.port2_out(md_io_port2),
	.port2_in(PB_o  | {7{snac_port2}}),
	.port2_dir(PB_d | {7{snac_port2}}),

	.PS2_KEY(ps2_key),
	.PS2_LED(ps2_kbd_led_status),
	.KEYBOARD_OPT(status[22:21])
);

wire [2:0] lg_target;
wire       lg_sensor;
wire       lg_a;
wire       lg_b;
wire       lg_c;
wire       lg_start;

lightgun lightgun
(
	.CLK(clk_sys),
	.RESET(sys_reset),

	.MOUSE(ps2_mouse),
	.MOUSE_XY(&gun_mode),

	.JOY_X(gun_mode[0] ? joy0_x : joy1_x),
	.JOY_Y(gun_mode[0] ? joy0_y : joy1_y),
	.JOY(gun_mode[0] ? joystick_0 : joystick_1),

	.RELOAD(gun_type),

	.HDE(~hblank_c),
	.VDE(~vblank_c),
	.CE_PIX(ce_pix),
	.H40(vdp_rs1),

	.BTN_MODE(gun_btn_mode),
	.SIZE(status[44:43]),
	.SENSOR_DELAY(gun_sensor_delay),

	.TARGET(lg_target),
	.SENSOR(lg_sensor),
	.BTN_A(lg_a),
	.BTN_B(lg_b),
	.BTN_C(lg_c),
	.BTN_START(lg_start)
);

wire [6:0] SNAC_IN;
wire [6:0] SNAC_OUT;
always_comb begin
	SNAC_IN[0]  = USER_IN[1]; //up
	SNAC_IN[1]  = USER_IN[0]; //down
	SNAC_IN[2]  = USER_IN[5]; //left
	SNAC_IN[3]  = USER_IN[3]; //right
	SNAC_IN[4]  = USER_IN[2]; //b TL
	SNAC_IN[5]  = USER_IN[6]; //c TR GPIO7
	SNAC_IN[6]  = USER_IN[4]; //  TH
	USER_OUT[1] = SNAC_OUT[0];
	USER_OUT[0] = SNAC_OUT[1];
	USER_OUT[5] = SNAC_OUT[2];
	USER_OUT[3] = SNAC_OUT[3];
	USER_OUT[2] = SNAC_OUT[4];
	USER_OUT[6] = SNAC_OUT[5];
	USER_OUT[4] = SNAC_OUT[6];
end

wire snac_port1 = (status[63:62] == 1);
assign PA_i = snac_port1 ? SNAC_IN : md_io_port1;

wire snac_port2 = (status[63:62] == 2);
assign PB_i = snac_port2 ? SNAC_IN : md_io_port2;

wire snac_port3 = (status[63:62] == 3);
`ifdef MDBOOT
assign PC_i = snac_port3 ? SNAC_IN : {PC_d[6:2] | PC_o[6:2], mdb_exp_coin_n & (PC_d[1:0] | PC_o[1:0])};   // coins (MAME "EXP")
`elsif MEGAPLAY
assign PC_i = snac_port3 ? SNAC_IN : {mp_exp_hi[6:3], PC_d[2:0] | PC_o[2:0]};   // Mega Play: bits 6-3 from the BIOS
`else
assign PC_i = snac_port3 ? SNAC_IN : (PC_d | PC_o);
`endif

assign SNAC_OUT = snac_port1 ? (PA_d | PA_o) : snac_port2 ? (PB_d | PB_o) : snac_port3 ? (PC_d | PC_o) : 7'h7F;

/////////////////////////  BRAM SAVE/LOAD  /////////////////////////////

wire downloading = cart_download;

reg bk_ena = 0;
reg sav_pending = 0;
wire bk_change;

always @(posedge clk_sys) begin
	reg old_downloading = 0;
	reg old_change = 0;

	old_downloading <= downloading;
	if(~old_downloading & downloading) bk_ena <= 0;

	//Save file always mounted in the end of downloading state.
	if(downloading && img_mounted && !img_readonly) bk_ena <= 1;

	old_change <= bk_change;
	if (~old_change & bk_change & ~OSD_STATUS) sav_pending <= 1;
	else if (bk_state) sav_pending <= 0;
end

wire bk_load    = status[16];
wire bk_save    = status[17] | (sav_pending & OSD_STATUS & status[13]);
reg  bk_loading = 0;
reg  bk_state   = 0;

always @(posedge clk_sys) begin
	reg old_downloading = 0;
	reg old_load = 0, old_save = 0, old_ack;

	old_downloading <= downloading;

	old_load <= bk_load;
	old_save <= bk_save;
	old_ack  <= sd_ack;

	if(~old_ack & sd_ack) {sd_rd, sd_wr} <= 0;

	if(!bk_state) begin
		if(bk_ena & ((~old_load & bk_load) | (~old_save & bk_save))) begin
			bk_state <= 1;
			bk_loading <= bk_load;
			sd_lba <= 0;
			sd_rd <=  bk_load;
			sd_wr <= ~bk_load;
		end
		if(old_downloading & ~downloading & |img_size & bk_ena) begin
			bk_state <= 1;
			bk_loading <= 1;
			sd_lba <= 0;
			sd_rd <= 1;
			sd_wr <= 0;
		end
	end else begin
		if(old_ack & ~sd_ack) begin
			if(&sd_lba[6:0]) begin
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


///////////////////////////////////////////////////
// Cheat codes loading for WIDE IO (16 bit)
reg [128:0] gg_code;
wire        gg_available;

// Code layout:
// {clock bit, code flags,     32'b address, 32'b compare, 32'b replace}
//  128        127:96          95:64         63:32         31:0
// Integer values are in BIG endian byte order, so it up to the loader
// or generator of the code to re-arrange them correctly.

always_ff @(posedge clk_sys) begin
	gg_code[128] <= 1'b0;

	if (code_download & ioctl_wr) begin
		case (ioctl_addr[3:0])
			0:  gg_code[111:96]  <= ioctl_data; // Flags Bottom Word
			2:  gg_code[127:112] <= ioctl_data; // Flags Top Word
			4:  gg_code[79:64]   <= ioctl_data; // Address Bottom Word
			6:  gg_code[95:80]   <= ioctl_data; // Address Top Word
			8:  gg_code[47:32]   <= ioctl_data; // Compare Bottom Word
			10: gg_code[63:48]   <= ioctl_data; // Compare top Word
			12: gg_code[15:0]    <= ioctl_data; // Replace Bottom Word
			14: begin
				gg_code[31:16]   <= ioctl_data; // Replace Top Word
				gg_code[128]     <=  1'b1;      // Clock it in
			end
		endcase
	end
end

reg [15:0] m68k_data;
always @(posedge clk_md) m68k_data <= m68k_genie_data;

wire [15:0] m68k_genie_data;
CODES #(.ADDR_WIDTH(24), .DATA_WIDTH(16), .BIG_ENDIAN(1)) codes_68k
(
	.clk(clk_sys),
	.reset(cart_download | (code_download && ioctl_wr && !ioctl_addr)),
	.enable(~status[24] & ~cart_ms),
	.code(gg_code),
	.available(gg_available),
	.addr_in({m68k_addr, 1'b0}),
	.data_in(m68k_bus_do),
	.data_out(m68k_genie_data)
);

reg [7:0] z80_data;
always @(posedge clk_md) z80_data <= z80_genie_data;

wire [7:0] z80_genie_data;
CODES #(.ADDR_WIDTH(16), .DATA_WIDTH(8)) codes_z80
(
	.clk(clk_sys),
	.reset(cart_download | (code_download && ioctl_wr && !ioctl_addr)),
	.enable(~status[24] & cart_ms),
	.code(gg_code),
	.addr_in(z80_addr),
	.data_in(z80_bus_do),
	.data_out(z80_genie_data)
);

endmodule
