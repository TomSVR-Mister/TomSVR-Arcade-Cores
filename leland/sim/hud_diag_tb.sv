// Ataxx board bring-up bench: streams sim/ataxx_image.bin (make_ataxx_image.py) through the
// HPS loader path and logs the master/slave I/O for comparison with a MAME trace.
//   vlib work && vlog -mfcu -sv -suppress 2244 +define+SIM_NO_SOUND -f flist_board_nosnd.txt leland_board_ax_tb.sv
//   vsim -c -GUSE_ALTDDIO=0 work.leland_board_ax_tb -do "run -all; quit"
// +define+RUN_LEN_MS=N sets the run length after loading (default 20).

`timescale 1ns / 1ps

`ifndef FRAME_EVERY
  `define FRAME_EVERY 10
`endif
`ifndef FETCH_LOG
  `define FETCH_LOG 0
`endif
`ifndef RUN_LEN_MS
  `define RUN_LEN_MS 7000
`endif

module hud_diag_tb;

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


initial begin
    wait(dut.cpu_release);
    #(2200 * 64'd1_000_000) p1_joy_r[7] = 1;
    #(170 * 64'd1_000_000) p1_joy_r[7] = 0;
    #(2130 * 64'd1_000_000) p1_joy_r[7] = 1;
    #(170 * 64'd1_000_000) p1_joy_r[7] = 0;
end
initial begin
    wait(dut.cpu_release);
    #(3000 * 64'd1_000_000) p1_joy_r[6] = 1;
    #(170 * 64'd1_000_000) p1_joy_r[6] = 0;
    #(1830 * 64'd1_000_000) p1_joy_r[6] = 1;
    #(170 * 64'd1_000_000) p1_joy_r[6] = 0;
end
initial begin
    wait(dut.cpu_release);
    #(3400 * 64'd1_000_000) p1_joy_r[4] = 1;
    #(170 * 64'd1_000_000) p1_joy_r[4] = 0;
    #(1830 * 64'd1_000_000) p1_joy_r[4] = 1;
    #(170 * 64'd1_000_000) p1_joy_r[4] = 0;
end
integer trace_fd, frame_bad = 0, frame_under = 0, total_bad = 0;
integer tag_x[0:7], tag_y[0:7], tag_col[0:7], tag_row[0:7], tag_riy[0:7];
integer arm_x, arm_y, arm_col, arm_row, arm_riy;
integer tag_sx[0:7], tag_sy[0:7], arm_sx, arm_sy;
reg [15:0] sx_prev, sy_prev;
reg [7:0] gb_prev;
integer mpc = 0, spc = 0;
initial trace_fd = $fopen("hud_trace.log", "w");
always @(posedge clk_sys) begin
    if (dut.ataxx_sel ? dut.master_ax.CE_6M : dut.master.CE_6M) begin
        if (dut.ataxx_sel ? (!dut.master_ax.mreq_n && !dut.master_ax.m1_n) : (!dut.master.mreq_n && !dut.master.m1_n))
            mpc <= dut.ataxx_sel ? dut.master_ax.cpu_addr : dut.master.cpu_addr;
        if (dut.ataxx_sel ? (!dut.slave_ax.mreq_n && !dut.slave_ax.m1_n) : (!dut.slave.mreq_n && !dut.slave.m1_n))
            spc <= dut.ataxx_sel ? dut.slave_ax.cpu_addr : dut.slave.cpu_addr;
    end
    sx_prev <= dut.scroll_x_m; sy_prev <= dut.scroll_y_m; gb_prev <= dut.gfxbank_m;
    if (dut.cpu_release && (sx_prev != dut.scroll_x_m || sy_prev != dut.scroll_y_m || gb_prev != dut.gfxbank_m))
        $fwrite(trace_fd,"SCROLL f=%0d y=%0d x=%0d pc=%04x sx=%04x sy=%04x gb=%02x count=%0d walk=%0d,%0d\n",
            frame_no, dut.video.vc, dut.video.hc, mpc, dut.scroll_x_m, dut.scroll_y_m, dut.gfxbank_m,
            dut.video.rbuf_count, dut.video.walk_hc, dut.video.walk_vc);
    if (dut.video.fetch_ph == 0 && dut.video.rbuf_has_room && !dut.video.reset) begin
        arm_x = dut.video.hc_tgt; arm_y = dut.video.vc_tgt;
        arm_col = dut.video.tile_col_tgt;
        arm_row = dut.ataxx_sel ? (dut.video.tile_row_tgt & 127) : dut.video.tile_row_tgt;
        arm_riy = dut.video.eff_y_tgt & 7;
        arm_sx = dut.scroll_x_m; arm_sy = dut.scroll_y_m;
    end
    if (dut.video.fifo_push && !dut.video.reset) begin
        tag_x[dut.video.rbuf_wr] = arm_x; tag_y[dut.video.rbuf_wr] = arm_y;
        tag_col[dut.video.rbuf_wr] = arm_col; tag_row[dut.video.rbuf_wr] = arm_row;
        tag_riy[dut.video.rbuf_wr] = arm_riy;
        tag_sx[dut.video.rbuf_wr] = arm_sx; tag_sy[dut.video.rbuf_wr] = arm_sy;
    end
    if (dut.video.fifo_pop && !dut.video.reset && dut.video.vc < 240) begin
        if (tag_col[dut.video.rbuf_rd] != (dut.video.eff_x >> 3) ||
            tag_row[dut.video.rbuf_rd] != ((dut.video.eff_y >> 3) & (dut.ataxx_sel ? 127 : 255)) ||
            tag_riy[dut.video.rbuf_rd] != (dut.video.eff_y & 7)) begin
            frame_bad = frame_bad + 1; total_bad = total_bad + 1;
            if (dut.video.vc >= 195 && dut.video.vc <= 225)
                $fwrite(trace_fd,"BAD f=%0d y=%0d x=%0d target=%0d,%0d tile=%0d,%0d,%0d expected=%0d,%0d,%0d oldscroll=%04x,%04x live=%04x,%04x count=%0d\n",
                    frame_no, dut.video.vc, dut.video.hc, tag_x[dut.video.rbuf_rd], tag_y[dut.video.rbuf_rd],
                    tag_col[dut.video.rbuf_rd], tag_row[dut.video.rbuf_rd], tag_riy[dut.video.rbuf_rd],
                    dut.video.eff_x >> 3, (dut.video.eff_y >> 3) & (dut.ataxx_sel ? 127 : 255), dut.video.eff_y & 7,
                    tag_sx[dut.video.rbuf_rd], tag_sy[dut.video.rbuf_rd], dut.scroll_x_m, dut.scroll_y_m, dut.video.rbuf_count);
        end
    end
    if (dut.video.fifo_pop_req && !dut.video.rbuf_has_data && !dut.video.reset && dut.video.vc < 240) frame_under = frame_under + 1;
    if (ce_pix && VBlank && !vb_d && !reset) begin
        $fwrite(trace_fd,"FRAME f=%0d bad=%0d under=%0d pc=%04x spc=%04x sx=%04x sy=%04x\n", frame_no, frame_bad, frame_under, mpc, spc, dut.scroll_x_m, dut.scroll_y_m);
        frame_bad = 0; frame_under = 0;
        $fflush(trace_fd);
    end
end
always begin
    #(500 * 64'd1_000_000);
    if (!reset) $display("HB f=%0d pc=%04x spc=%04x total_bad=%0d", frame_no, mpc, spc, total_bad);
end
endmodule
