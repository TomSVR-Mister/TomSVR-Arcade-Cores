// TomSVR Leland sports bench: any game image (mra_to_image.py output) through the HPS loader path,
// frames to frame_<n>.ppm. Plusargs: +IMG=file +INPUTS=file (lines "<frame> <p1> <p2> <p3> <p4>" hex
// joystick bytes [0]=R [1]=L [2]=D [3]=U [4]=b1 [5]=b2 [6]=start [7]=coin, applied from that frame).
//   build (add -DMICROCODE_ROM_PATH=\"<abs path>/rtl/s80x86/microcode\" when sound is on): verilator --binary --timing -Wno-fatal -DSIM_NO_SOUND -DRUN_LEN_MS=2000 --top-module sports_board_tb \
//     -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -f flist_ax_verilator.txt sports_board_tb.sv \
//     --Mdir verilator/obj_sports -j 8

`timescale 1ns / 1ps

`ifndef FRAME_EVERY
  `define FRAME_EVERY 60
`endif
`ifndef RUN_LEN_MS
  `define RUN_LEN_MS 20
`endif

module sports_board_tb;


localparam CLK_PERIOD = 20.83;
localparam IMG_MAX = 7340304;

reg clk_sys = 0;
always #(CLK_PERIOD/2) clk_sys = ~clk_sys;

reg clk_sdram = 0;
initial begin
	#(3.472);
	forever #(CLK_PERIOD/2) clk_sdram = ~clk_sdram;
end

reg [7:0] p1_joy_r = 8'h00;
reg [7:0] p1_wx = 8'h00, p1_wy = 8'h00;
reg reset          = 1;
reg sdram_init     = 1;
reg ioctl_download = 0;
reg [15:0] ioctl_index = 0;
reg        ioctl_wr = 0;
reg [26:0] ioctl_addr = 0;
reg [7:0]  ioctl_data = 0;
wire       ioctl_wait;

wire [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire  [1:0] SDRAM_BA;
wire        SDRAM_CLK, SDRAM_CKE, SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_DQML, SDRAM_DQMH;

wire        ce_pix, HBlank, HSync, VBlank, VSync;
wire [23:0] rgb;
wire signed [15:0] audio_out;

leland_board #(.USE_ALTDDIO(1'b0), .DL_SETTLE_CYCLES(24'd10000)) dut
(
	.clk_sys(clk_sys),
	.clk_sdram(clk_sdram),
	.reset(reset),
	.sdram_init(sdram_init),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.nvl_download(1'b0), .nvl_index(16'd0), .nvl_wr(1'b0), .nvl_addr(27'd0), .nvl_data(8'd0),
	.nv_rd_addr(8'd0), .nv_rd_data(), .nv_dirty(), .nv_dirty_clr(1'b0),

	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),

	.ce_pix(ce_pix),
	.HBlank(HBlank), .HSync(HSync), .VBlank(VBlank), .VSync(VSync),
	.rgb(rgb),

	.p1_btn(4'h0), .p2_btn(4'h0), .p3_btn(4'h0),
	.p1_wheel(8'h00), .p2_wheel(8'h00), .p3_wheel(8'h00),
	.p1_tb_x(p1_wx), .p1_tb_y(p1_wy), .p2_tb_x(8'h00), .p2_tb_y(8'h00),
	.p1_ad_x(j1[1] ? 8'h00 : j1[0] ? 8'hFF : 8'h80), .p1_ad_y(j1[3] ? 8'h00 : j1[2] ? 8'hFF : 8'h80),
	.p2_ad_x(j2[1] ? 8'h00 : j2[0] ? 8'hFF : 8'h80), .p2_ad_y(j2[3] ? 8'h00 : j2[2] ? 8'hFF : 8'h80),
	.p3_ad_x(j3[1] ? 8'h00 : j3[0] ? 8'hFF : 8'h80), .p3_ad_y(j3[3] ? 8'h00 : j3[2] ? 8'hFF : 8'h80),
	.p1_pedal(8'h00), .p2_pedal(8'h00), .p3_pedal(8'h00),
	.p1_joy(j1), .p2_joy(j2), .p3_joy(j3), .p4_joy(j4),

	.service(1'b0),
	.audio_out(audio_out)
);

mt48lc16m16a2 chip
(
	.Dq(SDRAM_DQ), .Addr(SDRAM_A), .Ba(SDRAM_BA), .Clk(SDRAM_CLK), .Cke(SDRAM_CKE),
	.Cs_n(SDRAM_nCS), .Ras_n(SDRAM_nRAS), .Cas_n(SDRAM_nCAS), .We_n(SDRAM_nWE),
	.Dqm({SDRAM_DQMH, SDRAM_DQML})
);

reg [7:0] j1 = 0, j2 = 0, j3 = 0, j4 = 0;
reg [7:0] img [0:IMG_MAX-1];
integer IMG_LEN;
string img_name;
longint unsigned phase_ns;
integer fd, rd_count, k, kk;
reg blk_nz;

task ioctl_write_byte(input [26:0] addr, input [7:0] data);
	begin
		@(posedge clk_sys);
		while (ioctl_wait) @(posedge clk_sys);
		// the board pairs each byte with the previous cycle's ioctl_addr (ioctl_addr_d1)
		ioctl_addr <= addr;
		@(posedge clk_sys);
		ioctl_data <= data;
		ioctl_addr <= addr + 1'b1;
		ioctl_wr   <= 1'b1;
		@(posedge clk_sys);
		ioctl_wr   <= 1'b0;
	end
endtask

initial begin
	if (!$value$plusargs("IMG=%s", img_name)) img_name = "image.bin";
	if (!$value$plusargs("PHASE_NS=%d", phase_ns)) phase_ns = 0;
	fd = $fopen(img_name, "rb");
	if (fd == 0) begin
		$display("ERROR: sim/ataxx_image.bin missing (python make_ataxx_image.py ataxx.zip ataxx_image.bin)");
		$finish;
	end
	rd_count = $fread(img, fd);
	$fclose(fd);
	IMG_LEN = rd_count;

	sdram_init = 1;
	reset      = 1;
	repeat (10) @(posedge clk_sys);
	sdram_init = 0;
	repeat (5) @(posedge clk_sys);
	#(phase_ns); // start the load at a chosen raster phase

	ioctl_download = 1'b1;
	@(posedge clk_sys);
	ioctl_addr <= 27'd0;
	// The SDRAM model starts zeroed, so zero bytes past the header are skipped (much faster load).
	// Only whole zero 4 KB blocks are skipped: the board packs bytes into words, so every
	// byte of a block that is written must be sent.
	for (k = 0; k < IMG_LEN; k = k + 4096) begin
		blk_nz = (k == 0);
		for (kk = k; kk < k + 4096 && kk < IMG_LEN; kk = kk + 1) if (img[kk] != 8'h00) blk_nz = 1'b1;
		if (blk_nz)
			for (kk = k; kk < k + 4096 && kk < IMG_LEN; kk = kk + 1) ioctl_write_byte(kk, img[kk]);
	end
	repeat (20) @(posedge clk_sys);
	ioctl_download = 1'b0;

	$display("=== load done t=%0t (game_id=%0d class=%0d ataxx_sel=%0b) ===", $time,
	         dut.hdr_game_id, dut.hdr_board_class_raw, dut.ataxx_sel);
	reset = 1'b0;

	#(`RUN_LEN_MS * 64'd1_000_000);
	$display("=== run end t=%0t ===", $time);
	$finish;
end

// Joystick script
integer ifd, ifr, ifn;
reg [31:0] in_frame [0:255];
reg [7:0]  in_j1 [0:255], in_j2 [0:255], in_j3 [0:255], in_j4 [0:255];
integer in_n = 0, in_i = 0;
string in_name;
initial begin
	if ($value$plusargs("INPUTS=%s", in_name)) begin
		ifd = $fopen(in_name, "r");
		while (ifd != 0 && !$feof(ifd) && in_n < 256) begin
			ifr = $fscanf(ifd, "%d %h %h %h %h\n", in_frame[in_n], in_j1[in_n], in_j2[in_n], in_j3[in_n], in_j4[in_n]);
			if (ifr == 5) in_n = in_n + 1;
		end
		if (ifd != 0) $fclose(ifd);
		$display("inputs: %0d steps", in_n);
	end
end
always @(posedge clk_sys) if (in_i < in_n && frame_no >= in_frame[in_i]) begin
	j1 <= in_j1[in_i]; j2 <= in_j2[in_i]; j3 <= in_j3[in_i]; j4 <= in_j4[in_i];
	$display("INPUT frame=%0d %02x %02x %02x %02x", frame_no, in_j1[in_i], in_j2[in_i], in_j3[in_i], in_j4[in_i]);
	in_i <= in_i + 1;
end

// Frame dump: every 60th frame to frame_<n>.ppm (320x240 visible area)
reg [23:0] fb [0:320*240-1];
integer fx = 0, fy = 0, frame_no = 0, ffd, fi;
reg hb_d = 0, vb_d = 0;
always @(posedge clk_sys) if (ce_pix && !reset) begin
	hb_d <= HBlank;
	vb_d <= VBlank;
	if (!HBlank && !VBlank && fx < 320 && fy < 240) begin
		fb[fy*320 + fx] <= rgb;
		fx <= fx + 1;
	end
	if (HBlank && !hb_d) begin
		fx <= 0;
		if (!VBlank) fy <= fy + 1;
	end
	if (VBlank && !vb_d) begin
		if (frame_no % `FRAME_EVERY == `FRAME_EVERY - 1) begin
			ffd = $fopen($sformatf("frame_%0d.ppm", frame_no + 1), "wb");
			$fwrite(ffd, "P6\n320 240\n255\n");
			for (fi = 0; fi < 320*240; fi = fi + 1)
				$fwrite(ffd, "%c%c%c", fb[fi][23:16], fb[fi][15:8], fb[fi][7:0]);
			$fclose(ffd);
		end
		frame_no <= frame_no + 1;
		fy <= 0;
		fx <= 0;
	end
end


always begin
	#(100 * 64'd1_000_000);
	if (!reset) $display("HB t=%0t frame=%0d gpc=%04x spc=%04x apc=%04x", $time, frame_no, g_pc, gs_pc, a_pc);
end
`ifndef SIM_NO_SOUND
// Sound board seam: control writes (F0), command writes, responses, 80186 IP
integer n_sacc = 0;
always @(posedge clk_sys) if (n_sacc < 120 && dut.sound.board.audiocpu_reset_n) begin
	if (dut.sound.instr_m_access && dut.sound.instr_m_ack) begin n_sacc <= n_sacc + 1;
		$display("SI t=%0t a=%05x d=%04x", $time, {dut.sound.instr_m_addr, 1'b0}, dut.sound.instr_m_data_in); end
	if (dut.sound.data_m_access && dut.sound.data_m_ack) begin n_sacc <= n_sacc + 1;
		$display("SD t=%0t a=%05x io=%0b wr=%0b bs=%0d out=%04x in=%04x", $time, {dut.sound.data_m_addr, 1'b0}, dut.sound.data_m_d_io,
		         dut.sound.data_m_wr_en, dut.sound.data_m_bytesel, dut.sound.data_m_data_out, dut.sound.data_m_data_in); end
end
integer n_rd3 = 0;
always @(posedge clk_sys) if (dut.sdram_rd3_ack && n_rd3 < 64) begin n_rd3 <= n_rd3 + 1;
	$display("RD3 t=%0t a=%06x d=%02x", $time, dut.sdram_rd3_addr, dut.sdram_rd3_data); end
reg sreq_d2; always @(posedge clk_sys) sreq_d2 <= dut.sound_rom_req;
always @(posedge clk_sys) if (dut.sound_rom_req && !sreq_d2 && n_rd3 < 64)
	$display("SRQ t=%0t a=%05x", $time, dut.sound_rom_addr_w);
integer n_sreq = 0;
reg sreq_d;
always @(posedge clk_sys) begin
	sreq_d <= dut.sound_rom_req;
	if (dut.sound_rom_req && !sreq_d) n_sreq <= n_sreq + 1;
	if (dut.sound_ctrl_wr) $display("SCTL t=%0t data=%02x", $time, dut.sound_ctrl_data);
	if (dut.sound.board.response_wr) $display("SRSP t=%0t data=%02x", $time, dut.sound.board.cpu_data_out[7:0]);
end
always begin
	#(100 * 64'd1_000_000);
	if (!reset) $display("SND t=%0t rst_n=%0b core_rst=%0b ip=%04x resp=%02x stop=%0b iacc=%0b iack=%0b rom_req=%0b rom_addr=%05x stall=%0b nreq=%0d dacc=%0b dack=%0b daddr=%05x io=%0b", $time,
		dut.sound.board.audiocpu_reset_n, dut.sound.core_reset, dut.sound.cpu.ip_current, dut.sound_response_data,
		dut.sound.debug_stopped, dut.sound.instr_m_access, dut.sound.instr_m_ack, dut.sound_rom_req, dut.sound_rom_addr_w, dut.sound_rom_stall, n_sreq, dut.sound.data_m_access, dut.sound.data_m_ack, {dut.sound.data_m_addr,1'b0}, dut.sound.data_m_d_io);
end
`endif
reg [15:0] g_pc, a_pc, gs_pc;
always @(posedge clk_sys) if (dut.slave.CE_6M && ~dut.slave.mreq_n && ~dut.slave.m1_n) gs_pc <= dut.slave.cpu_addr;
`ifdef PC_LOG
// First time each master / slave PC is fetched (compare with MAME trace order)
reg mseen [0:65535];
reg sseen [0:65535];
reg [15:0] m_last = 16'hFFFF, s_last = 16'hFFFF;
always @(posedge clk_sys) if (!reset) begin
	if (dut.master.CE_6M && ~dut.master.mreq_n && ~dut.master.m1_n && dut.master.rfsh_n && dut.master.cpu_addr != m_last) begin
		m_last <= dut.master.cpu_addr;
		if (!mseen[dut.master.cpu_addr]) begin
			mseen[dut.master.cpu_addr] <= 1'b1;
			$display("MPC %04x f=%0d", dut.master.cpu_addr, frame_no);
		end
	end
	if (dut.slave.CE_6M && ~dut.slave.mreq_n && ~dut.slave.m1_n && dut.slave.rfsh_n && dut.slave.cpu_addr != s_last) begin
		s_last <= dut.slave.cpu_addr;
		if (!sseen[dut.slave.cpu_addr]) begin
			sseen[dut.slave.cpu_addr] <= 1'b1;
			$display("SPC %04x f=%0d", dut.slave.cpu_addr, frame_no);
		end
	end
end
integer nmf = 0;
reg rdm_d = 1'b0; reg [15:0] rdm_a; reg [7:0] rdm_din; reg rdm_m1;
always @(posedge clk_sys) begin
	rdm_d <= ~dut.master.mreq_n & ~dut.master.rd_n & dut.master.rfsh_n;
	if (~dut.master.mreq_n & ~dut.master.rd_n & dut.master.rfsh_n) begin
		rdm_a <= dut.master.cpu_addr; rdm_din <= dut.master.cpu_din; rdm_m1 <= ~dut.master.m1_n;
	end
	if (!reset && rdm_d && !(~dut.master.mreq_n & ~dut.master.rd_n & dut.master.rfsh_n) && nmf < 600) begin
		nmf <= nmf + 1;
		$display("MRD %04x m1=%0b din=%02x", rdm_a, rdm_m1, rdm_din);
	end
end
`endif
always @(posedge clk_sys) begin
	if (dut.master.CE_6M && ~dut.master.mreq_n && ~dut.master.m1_n) g_pc <= dut.master.cpu_addr;
	if (dut.master_ax.CE_6M && ~dut.master_ax.mreq_n && ~dut.master_ax.m1_n) a_pc <= dut.master_ax.cpu_addr;
end

endmodule
