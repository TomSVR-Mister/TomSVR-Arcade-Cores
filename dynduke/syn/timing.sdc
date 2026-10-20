# The two V30 cores (v30u_eu, v30u_biu) only change state on their clock enable, and jtdynduke_cpu.sv never
# issues two enables less than three clocks apart, so paths between their ce-gated registers get three clocks.
# Same reasoning as the MiSTer Irem M72 core's SDC, which uses two clocks for its own enable train.
set v30u_regs [add_to_collection \
                   [get_registers -nowarn {*|v30u_eu:*|*}] \
                   [get_registers -nowarn {*|v30u_biu:*|*}]]
set v30u_ssrd [add_to_collection \
                   [get_registers -nowarn {*|v30u_biu:*|ss_rdata[*]}] \
                   [get_registers -nowarn {*|v30u_eu:*|ss_rdata[*]}]]
set v30u_ce [remove_from_collection $v30u_regs $v30u_ssrd]
if {[get_collection_size $v30u_ce] > 0} {
    set_multicycle_path -setup 3 -from $v30u_ce -to $v30u_ce
    set_multicycle_path -hold  2 -from $v30u_ce -to $v30u_ce
}
