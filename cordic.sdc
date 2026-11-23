# =============================================================================
# SDC cho CORDIC Core - Quartus Prime
# =============================================================================

set_time_format -unit ns -decimal_places 3

# ====================== CLOCK DEFINITION ======================
create_clock -name clk -period 10.000 [get_ports clk]
# 10.000 ns = 100 MHz
# Bạn có thể thử thay đổi thành:
# 8.000  → 125 MHz
# 6.667  → ~150 MHz  
# 5.000  → 200 MHz
# 4.500  → ~222 MHz

# Tự động tính toán clock uncertainty (rất quan trọng)
derive_clock_uncertainty

# ====================== I/O Constraints ======================
set_input_delay  -clock clk -max 1.5 [all_inputs]
set_input_delay  -clock clk -min 0.0  [all_inputs]

set_output_delay -clock clk -max 1.5 [all_outputs]
set_output_delay -clock clk -min 0.0 [all_outputs]

# ====================== FALSE PATH ======================
set_false_path -from [get_ports rst_n] -to [all_registers]

# =============================================================================