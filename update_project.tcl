# Tcl script to refresh matrix_calc project sources

# 1. Remove all existing source files (to clean up deleted/V1 files)
# Note: This removes them from the PROJECT, not the disk.
set project_files [get_files -filter {IS_AUTO_DISABLED == 0 || IS_AUTO_DISABLED == 1}]
if {[llength $project_files] > 0} {
    remove_files $project_files
}

# 2. Add all current source files
# Core Files
add_files -norecurse {
    E:/desk/matrix_calc/src/controller_fsm_v2.v
    E:/desk/matrix_calc/src/debounce.v
    E:/desk/matrix_calc/src/defs.vh
    E:/desk/matrix_calc/src/matrix_calc_top_v2.v
    E:/desk/matrix_calc/src/seg_display_v2.v
}

# Matrix Calculation Unit & Submodules
add_files -norecurse {
    E:/desk/matrix_calc/src/matrix/input_image_rom.v
    E:/desk/matrix_calc/src/matrix/mat_add.v
    E:/desk/matrix_calc/src/matrix/mat_conv.v
    E:/desk/matrix_calc/src/matrix/mat_mul.v
    E:/desk/matrix_calc/src/matrix/mat_scalar_mult.v
    E:/desk/matrix_calc/src/matrix/mat_transpose.v
    E:/desk/matrix_calc/src/matrix/matrix_calc_unit.v
    E:/desk/matrix_calc/src/matrix/matrix_gen.v
    E:/desk/matrix_calc/src/matrix/matrix_storage_v2.v
}

# UART Modules
add_files -norecurse {
    E:/desk/matrix_calc/src/uatr/matrix_uart_input_v2.v
    E:/desk/matrix_calc/src/uatr/matrix_uart_output_v2.v
    E:/desk/matrix_calc/src/uatr/uart_rx.v
    E:/desk/matrix_calc/src/uatr/uart_tx.v
}

# Add Constraints (if not already there, but remove_files might have kept it if in different set)
# Usually constraints are in constrs_1
add_files -fileset constrs_1 -norecurse E:/desk/matrix_calc/constraints/board_constraints.xdc

# 3. Update Compile Order
update_compile_order -fileset sources_1

# 4. Set Top Module
set_property top matrix_calc_top_v2 [current_fileset]
update_compile_order -fileset sources_1

puts "Project sources updated successfully."
