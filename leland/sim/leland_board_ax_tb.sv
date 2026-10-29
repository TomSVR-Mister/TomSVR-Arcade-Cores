// Ataxx board bring-up bench: streams sim/ataxx_image.bin (make_ataxx_image.py) through the
// HPS loader path and logs the master/slave I/O for comparison with a MAME trace.
//   vlib work && vlog -mfcu -sv -suppress 2244 +define+SIM_NO_SOUND -f flist_board_nosnd.txt leland_board_ax_tb.sv
//   vsim -c -GUSE_ALTDDIO=0 work.leland_board_ax_tb -do "run -all; quit"
// +define+RUN_LEN_MS=N sets the run length after loading (default 20).

`timescale 1ns / 1ps

`ifndef FRAME_EVERY
  `define FRAME_EVERY 60
`endif
`ifndef FETCH_LOG
  `define FETCH_LOG 0
`endif
`ifndef RUN_LEN_MS
  `define RUN_LEN_MS 20
`endif

module leland_board_ax_tb;

localparam CLK_PERIOD = 20.83;
localparam IMG_MAX = 7340304; // the largest image (Ataxx family); others are 128 bytes shorter

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
	.p1_pedal(8'h00), .p2_pedal(8'h00), .p3_pedal(8'h00),
	.p1_joy(p1_joy_r), .p2_joy(8'h00), .p3_joy(8'h00), .p4_joy(8'h00),

	.service(1'b0),
	.audio_out(audio_out)
);

mt48lc16m16a2 chip
(
	.Dq(SDRAM_DQ), .Addr(SDRAM_A), .Ba(SDRAM_BA), .Clk(SDRAM_CLK), .Cke(SDRAM_CKE),
	.Cs_n(SDRAM_nCS), .Ras_n(SDRAM_nRAS), .Cas_n(SDRAM_nCAS), .We_n(SDRAM_nWE),
	.Dqm({SDRAM_DQMH, SDRAM_DQML})
);

// Input stimulus (times in ms after the CPUs start; 0 disables): coin pulse, start pulse,
// then trackball movement of +4 counts per frame on X and Y for 40 frames.
`ifndef COIN_AT_MS
  `define COIN_AT_MS 0
`endif
`ifndef START_AT_MS
  `define START_AT_MS 0
`endif
`ifndef MOVE_AT_MS
  `define MOVE_AT_MS 0
`endif
integer mv;
initial begin
	wait (reset == 1'b0);
	if (`COIN_AT_MS != 0) begin
		#(`COIN_AT_MS * 64'd1_000_000) p1_joy_r[7] = 1'b1;
		#(170 * 64'd1_000_000)         p1_joy_r[7] = 1'b0;
	end
end
initial begin
	wait (reset == 1'b0);
	if (`START_AT_MS != 0) begin
		#(`START_AT_MS * 64'd1_000_000) p1_joy_r[6] = 1'b1;
		#(170 * 64'd1_000_000)          p1_joy_r[6] = 1'b0;
	end
end
initial begin
	wait (reset == 1'b0);
	if (`MOVE_AT_MS != 0) begin
		#(`MOVE_AT_MS * 64'd1_000_000);
		for (mv = 0; mv < 40; mv = mv + 1) begin
			p1_wx = p1_wx + 8'd4;
			p1_wy = p1_wy + 8'd4;
			#(15_170_000);
		end
	end
end

always @(p1_joy_r) $display("JOY t=%0t p1_joy_r=%02x in0=%02x", $time, p1_joy_r, dut.master_ax.in0);

reg [7:0] img [0:IMG_MAX-1];
integer IMG_LEN;
string img_name;
longint unsigned phase_ns;
integer fd, rd_count, k;

task ioctl_write_byte(input [26:0] addr, input [7:0] data);
	begin
		@(posedge clk_sys);
		while (ioctl_wait) @(posedge clk_sys);
		ioctl_data <= data;
		ioctl_addr <= addr + 1'b1;
		ioctl_wr   <= 1'b1;
		@(posedge clk_sys);
		ioctl_wr   <= 1'b0;
	end
endtask

initial begin
	if (!$value$plusargs("IMG=%s", img_name)) img_name = "ataxx_image.bin";
	if (!$value$plusargs("PHASE_NS=%d", phase_ns)) phase_ns = 0;
	fd = $fopen(img_name, "rb");
	if (fd == 0) begin
		$display("ERROR: sim/ataxx_image.bin missing (python make_ataxx_image.py ataxx.zip ataxx_image.bin)");
		$finish;
	end
	rd_count = $fread(img, fd);
	$fclose(fd);
	IMG_LEN = rd_count;
	if (rd_count != IMG_MAX && rd_count != IMG_MAX - 128) begin
		$display("ERROR: image is %0d bytes, expected %0d or %0d", rd_count, IMG_MAX, IMG_MAX - 128);
		$finish;
	end

	sdram_init = 1;
	reset      = 1;
	repeat (10) @(posedge clk_sys);
	sdram_init = 0;
	repeat (5) @(posedge clk_sys);
	#(phase_ns); // start the load at a chosen raster phase

	ioctl_download = 1'b1;
	@(posedge clk_sys);
	ioctl_addr <= 27'd0;
	for (k = 0; k < IMG_LEN; k = k + 1)
		ioctl_write_byte(k, img[k]);
	repeat (20) @(posedge clk_sys);
	ioctl_download = 1'b0;

	$display("=== load done t=%0t (game_id=%0d class=%0d ataxx_sel=%0b) ===", $time,
	         dut.hdr_game_id, dut.hdr_board_class_raw, dut.ataxx_sel);
	reset = 1'b0;

	#(`RUN_LEN_MS * 64'd1_000_000);
	$display("=== run end t=%0t ===", $time);
	ffd = $fopen("vram_ax.bin", "wb");
	for (k = 0; k < 131072; k = k + 1)
		$fwrite(ffd, "%c", dut.vram.mem[k]);
	$fclose(ffd);
	ffd = $fopen("qram_ax.bin", "wb");
	for (k = 0; k < 65536; k = k + 1)
		$fwrite(ffd, "%c", dut.qram.mem[k]);
	$fclose(ffd);
	for (k = 0; k < 64; k = k + 1)
		$display("PAL[%0d]=%02x%02x  PAL[%0d]=%02x%02x", k, dut.palram.mem[2*k+1], dut.palram.mem[2*k],
		         k + 64, dut.palram.mem[2*(k+64)+1], dut.palram.mem[2*(k+64)]);
	$finish;
end

// Repack check: raw plane bytes versus the packed rows, once the repack finishes
reg repack_done_d = 1'b0;
integer rt, rr, rp, rtile, rstride;
reg [15:0] rw;
function automatic [7:0] bank3_byte(input [22:0] rel);
	reg [15:0] w;
	begin
		w = chip.Bank3[rel[22:1]];
		bank3_byte = rel[0] ? w[15:8] : w[7:0];
	end
endfunction
always @(posedge clk_sys) begin
	repack_done_d <= dut.repack_done;
	if (dut.repack_done && !repack_done_d) begin
		$display("=== gfx rows ready t=%0t ===", $time);
		rstride = dut.gfx_wide_r ? 23'h40000 : 23'h20000;
		for (rt = 0; rt < 4; rt = rt + 1)
			for (rr = 0; rr < 8; rr = rr + 1) begin
				rtile = (rt == 0) ? 100 : (rt == 1) ? 2000 : (rt == 2) ? 12345 : 30000;
				if (rt < 3 || dut.gfx_wide_r) begin
					$write("RPK tile=%0d row=%0d packed:", rtile, rr);
					for (rp = 0; rp < 6; rp = rp + 1)
						$write(" %02x", bank3_byte((rtile * 8 + rr) * 8 + rp));
					$write("\n");
				end
			end
	end
end

// Frame dump: every 60th frame to frame_ax_<n>.ppm (320x240 visible area)
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
			ffd = $fopen($sformatf("frame_ax_%0d.ppm", frame_no + 1), "wb");
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

// Heartbeat every 50 ms: master PC, sound command writes and response reads so far
integer n_cmd = 0, n_resp = 0;
always @(posedge clk_sys) begin
	if (dut.master_ax.CE_6M && dut.master_ax.io_wr &&
	    (dut.master_ax.cpu_addr[7:0] == 8'h05 || dut.master_ax.cpu_addr[7:0] == 8'h06)) n_cmd <= n_cmd + 1;
	if (dut.master_ax.CE_6M && dut.master_ax.io_rd && dut.master_ax.cpu_addr[7:0] == 8'h04) n_resp <= n_resp + 1;
end
always begin
	#(50 * 64'd1_000_000);
	if (!reset) $display("HB t=%0t pc=%04x spc=%04x cmd_wr=%0d resp_rd=%0d frame=%0d", $time, m_pc, s_pc, n_cmd, n_resp, frame_no);
end

`ifndef SIM_NO_SOUND
// Sound board activity (80186 side)
integer n_pcs0 = 0, n_rspw = 0, n_dacw = 0, n_pit = 0, n_ioother = 0, n_memacc = 0;
reg acc_d = 0;
always @(posedge clk_sys) begin
	acc_d <= dut.sound.board.cpu_access;
	if (dut.sound.board.cpu_access && !acc_d) begin
		if (dut.sound.board.pcs0_hit && !dut.sound.board.cpu_wr_en) n_pcs0 <= n_pcs0 + 1;
		if (dut.sound.board.pcs2_hit) n_pit <= n_pit + 1;
		if (dut.sound.board.cpu_d_io && !dut.sound.board.win_hit) n_ioother <= n_ioother + 1;
		if (!dut.sound.board.cpu_d_io && !dut.sound.board.win_hit) n_memacc <= n_memacc + 1;
	end
	if (dut.sound.board.response_wr) n_rspw <= n_rspw + 1;
	if (dut.sound.board.dac_wr[0] || dut.sound.board.dac_wr[1] || dut.sound.board.dac_wr[2]) n_dacw <= n_dacw + 1;
end
// First sound-CPU bus accesses after reset release
integer n_sacc = 0;
reg sacc_d = 0;
always @(posedge clk_sys) begin
	sacc_d <= dut.sound.board.cpu_access;
	if (dut.sound.board.cpu_access && dut.sound.board.cpu_ack && n_sacc < 80 && dut.sound.board.audiocpu_reset_n) begin
		n_sacc <= n_sacc + 1;
		$display("SACC #%0d t=%0t addr=%05x io=%0b wr=%0b bytesel=%b dout=%04x din=%04x", n_sacc, $time,
		         {dut.sound.board.cpu_addr, 1'b0}, dut.sound.board.cpu_d_io, dut.sound.board.cpu_wr_en,
		         dut.sound.board.cpu_bytesel, dut.sound.board.cpu_data_out, dut.sound.board.cpu_data_in);
	end
end
// Sound core pin state every 5 ms after its reset release
always begin
	#(5 * 64'd1_000_000);
	if (!reset && dut.sound.board.audiocpu_reset_n)
		$display("SCORE t=%0t stopped=%0b instr_acc=%0b instr_ack=%0b data_acc=%0b data_ack=%0b lock=%0b intr=%0b inta=%0b irq=%02x ip=%04x",
		         $time, dut.sound.debug_stopped, dut.sound.instr_m_access, dut.sound.instr_m_ack, dut.sound.data_m_access,
		         dut.sound.data_m_ack, dut.sound.lock, dut.sound.intr, dut.sound.inta, dut.sound.irq, dut.sound.cpu.ip_current);
end
always begin
	#(50 * 64'd1_000_000);
	if (!reset) $display("SND t=%0t win(valid=%0b mem=%0b base=%05x) rst_n=%0b pcs0_rd=%0d pit=%0d resp_wr=%0d dac_wr=%0d io_other=%0d mem_acc=%0d",
		$time, dut.sound.board.ext_window_valid, dut.sound.board.ext_window_is_mem, dut.sound.board.ext_window_base,
		dut.sound.board.audiocpu_reset_n, n_pcs0, n_pit, n_rspw, n_dacw, n_ioother, n_memacc);
end
`endif

// Video fetch starvation watchdog: rd2 request outstanding for > 5000 cycles
integer rd2_wait = 0;
always @(posedge clk_sys) begin
	if (dut.sdram_rd2_req_v && !dut.sdram_rd2_ack) rd2_wait <= rd2_wait + 1;
	else                                           rd2_wait <= 0;
	if (rd2_wait == 5000) $display("RD2_STALL t=%0t fetch_ph=%0d", $time, dut.video.fetch_ph);
end

reg [15:0] m_pc, s_pc;
always @(posedge clk_sys) begin
	if (dut.master_ax.CE_6M && ~dut.master_ax.mreq_n && ~dut.master_ax.m1_n) m_pc <= dut.master_ax.cpu_addr;
	if (dut.slave_ax.CE_6M && ~dut.slave_ax.mreq_n && ~dut.slave_ax.m1_n) s_pc <= dut.slave_ax.cpu_addr;
end

integer nfetch = 0;
always @(posedge clk_sys)
	if (!reset && dut.master_ax.CE_6M && ~dut.master_ax.mreq_n && ~dut.master_ax.m1_n &&
	    dut.master_ax.rfsh_n && nfetch < `FETCH_LOG) begin
		nfetch = nfetch + 1;
		$display("MFETCH #%0d pc=%04x op=%02x", nfetch, dut.master_ax.cpu_addr, dut.master_ax.cpu_din);
	end

integer mwr = 0, mrd = 0;
reg [7:0] last_rd_port = 8'hzz;
reg [15:0] last_rd_pc = 16'hzzzz;
reg [7:0] last_rd_data = 8'hzz;
reg wr_logged = 1'b0;
always @(posedge clk_sys) begin
	if (!dut.master_ax.io_wr) wr_logged <= 1'b0;
	if (dut.master_ax.CE_6M && dut.master_ax.io_wr && !wr_logged) begin
		wr_logged <= 1'b1;
		mwr = mwr + 1;
		$display("MIOWR #%0d port=%02x data=%02x pc=%04x", mwr, dut.master_ax.cpu_addr[7:0],
		         dut.master_ax.cpu_dout, m_pc);
	end
	if (!reset && dut.master_ax.CE_6M && dut.master_ax.io_rd &&
	    (dut.master_ax.cpu_addr[7:0] != last_rd_port || m_pc != last_rd_pc || dut.master_ax.cpu_din != last_rd_data)) begin
		mrd = mrd + 1;
		$display("MIORD #%0d port=%02x data=%02x pc=%04x", mrd, dut.master_ax.cpu_addr[7:0],
		         dut.master_ax.cpu_din, m_pc);
		last_rd_port = dut.master_ax.cpu_addr[7:0];
		last_rd_pc   = m_pc;
		last_rd_data = dut.master_ax.cpu_din;
	end
end

always @(posedge clk_sys)
	if (dut.slave_ax.CE_6M && dut.slave_ax.bank_wr)
		$display("SBANK data=%02x pc=%04x", dut.slave_ax.cpu_dout, s_pc);

endmodule
