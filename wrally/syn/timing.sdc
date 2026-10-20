# The DS5002FP's jt8051 outputs (bus address, data, write, program address) only change on its clock enable and
# jtwrally_mcu.v registers them two clocks after it, so those paths get two clocks.
set wr_mcu_out [get_registers -nowarn {*|jtwrally_mcu:*|xa[*] *|jtwrally_mcu:*|xd[*] *|jtwrally_mcu:*|xw *|jtwrally_mcu:*|rom_addr[*]}]
if {[get_collection_size $wr_mcu_out] > 0} {
    set_multicycle_path -from {*|jt8051:u_mcu|*} -to $wr_mcu_out -setup -end 2
    set_multicycle_path -from {*|jt8051:u_mcu|*} -to $wr_mcu_out -hold  -end 2
}
