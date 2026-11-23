transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+D:/Hoctap/lab-thietkehethongsohdl/Doan {D:/Hoctap/lab-thietkehethongsohdl/Doan/cordic_top_fixed.v}
vlog -vlog01compat -work work +incdir+D:/Hoctap/lab-thietkehethongsohdl/Doan {D:/Hoctap/lab-thietkehethongsohdl/Doan/cordic_core_fixed.v}

vlog -vlog01compat -work work +incdir+D:/Hoctap/lab-thietkehethongsohdl/Doan {D:/Hoctap/lab-thietkehethongsohdl/Doan/cordic_tb_fixed.v}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cycloneii_ver -L rtl_work -L work -voptargs="+acc"  cordic_tb

add wave *
view structure
view signals
run -all
