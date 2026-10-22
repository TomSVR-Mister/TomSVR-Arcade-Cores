# The SemiCom MCU's jt8051 outputs (ports, program address) only change on its clock enable and
# jtsemicom_mcu.v takes them two clocks after it, so those paths get two clocks.
set sc_mcu_out [get_registers -nowarn {*|jtsemicom_mcu:*|rom_addr[*] *|jtsemicom_mcu:*|int0_l *|jtsemicom_mcu:*|wr_offset[*] *|jtsemicom_mcu:*|wr_data[*] *|jtsemicom_mcu:*|wr_req}]
if {[get_collection_size $sc_mcu_out] > 0} {
    set_multicycle_path -from {*|jt8051:u_mcu|*} -to $sc_mcu_out -setup -end 2
    set_multicycle_path -from {*|jt8051:u_mcu|*} -to $sc_mcu_out -hold  -end 2
}
