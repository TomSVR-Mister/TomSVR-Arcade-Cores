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
