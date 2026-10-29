## Leland - Timing Constraints
## clk_sys = 48 MHz from PLL

derive_pll_clocks
derive_clock_uncertainty

## SDRAM I/O: blanket false paths, as in Arcade-IGSPGM_MiSTer and other Sorgelig cores.
## A partial real SDC (generated clock, I/O delays, multicycle paths) gave worse placement
## than exempting SDRAM timing entirely.
set_false_path -to   [get_ports {SDRAM_CLK SDRAM_A[*] SDRAM_BA[*] SDRAM_nCS SDRAM_nRAS SDRAM_nCAS SDRAM_nWE SDRAM_DQML SDRAM_DQMH SDRAM_DQ[*]}]
set_false_path -from [get_ports {SDRAM_DQ[*]}]
