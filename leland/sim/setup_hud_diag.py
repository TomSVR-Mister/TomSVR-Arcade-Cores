"""Generate a diagnostic board bench from the existing loader; no RTL edits."""
from pathlib import Path

p = Path(__file__).parent
s = (p / 'leland_board_ax_tb.sv').read_text()
s = s[:s.index('// Heartbeat every 50 ms')]
s = s.replace('module leland_board_ax_tb;', 'module hud_diag_tb;')
s = s.replace('`define FRAME_EVERY 60', '`define FRAME_EVERY 10')
s = s.replace('`define RUN_LEN_MS 20', '`define RUN_LEN_MS 7000')
s += r'''
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
    sx_prev <= dut.scroll_x_m; sy_prev <= dut.scroll_y_m; gb_prev <= dut.gfxbank;
    if (dut.cpu_release && (sx_prev != dut.scroll_x_m || sy_prev != dut.scroll_y_m || gb_prev != dut.gfxbank))
        $fwrite(trace_fd,"SCROLL f=%0d y=%0d x=%0d pc=%04x sx=%04x sy=%04x gb=%02x count=%0d walk=%0d,%0d\n",
            frame_no, dut.video.vc, dut.video.hc, mpc, dut.scroll_x_m, dut.scroll_y_m, dut.gfxbank,
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
'''
# gfxbank is the board's selected master graphics bank.
s = s.replace('dut.gfxbank', 'dut.gfxbank_m')
(p / 'hud_diag_tb.sv').write_text(s)
for src, dst in [('flist_ax_verilator.txt', 'flist_hud_diag.txt'),
                 ('flist_ax_snd_verilator.txt', 'flist_hud_diag_sound.txt')]:
    (p / dst).write_text((p / src).read_text().replace('leland_board_ax_tb.sv', 'hud_diag_tb.sv'))
