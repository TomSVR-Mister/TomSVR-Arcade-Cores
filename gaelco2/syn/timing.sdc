set CLK48  {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set CLK96A {emu|pll|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}
set CLK96B {emu|pll|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}

foreach C96 [list $CLK96A $CLK96B] {
    set_multicycle_path -from [get_clocks $CLK48] -to [get_clocks $C96] -setup -end 2
    set_multicycle_path -from [get_clocks $CLK48] -to [get_clocks $C96] -hold  -end 1
    set_multicycle_path -from [get_clocks $C96] -to [get_clocks $CLK48] -setup -end 2
    set_multicycle_path -from [get_clocks $C96] -to [get_clocks $CLK48] -hold  -end 1
}

# DS5002FP: the jt8051 outputs only change on its clock enable and jtgaelco2_mcu.v registers them two clocks
# after it, so those paths get two clocks (as in JTWRALLY).
set g2_mcu_out [get_registers -nowarn {*|jtgaelco2_mcu:*|xa[*] *|jtgaelco2_mcu:*|xd[*] *|jtgaelco2_mcu:*|xw *|jtgaelco2_mcu:*|rom_addr[*]}]
if {[get_collection_size $g2_mcu_out] > 0} {
    set_multicycle_path -from {*|jt8051:u_mcu|*} -to $g2_mcu_out -setup -end 2
    set_multicycle_path -from {*|jt8051:u_mcu|*} -to $g2_mcu_out -hold  -end 2
}

# The DS5002FP internal RAM is a jtframe_ram (it is preloaded with the Touch and Go scratch image), not the
# jtframe_ram_rst that jt8051's own timing.sdc names: give it the same two-clock paths. Outside the preload it is
# only written and read on the MCU clock enable (every 3rd or 4th clock), like jtframe_ram_rst.
set_multicycle_path -from {*|jt8051:u_mcu|*} -to {*|jtgaelco2_mcu:*|jtframe_ram:u_ramu|*} -setup -end 2
set_multicycle_path -from {*|jt8051:u_mcu|*} -to {*|jtgaelco2_mcu:*|jtframe_ram:u_ramu|*} -hold  -end 2
set_multicycle_path -from {*|jtgaelco2_mcu:*|jtframe_ram:u_ramu|*} -to {*|jt8051:u_mcu|*} -setup -end 2
set_multicycle_path -from {*|jtgaelco2_mcu:*|jtframe_ram:u_ramu|*} -to {*|jt8051:u_mcu|*} -hold  -end 2
