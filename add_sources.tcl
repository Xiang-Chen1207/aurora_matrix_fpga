# ============================================
# Vivado TCL脚本：添加矩阵计算器源文件
# 使用方法：在Vivado Tcl Console中运行
#   source add_sources.tcl
# ============================================

# 获取项目目录
set proj_dir [get_property DIRECTORY [current_project]]

# 添加V2版本的核心模块
add_files -norecurse [list \
    $proj_dir/src/controller_fsm_v2.v \
    $proj_dir/src/matrix_calc_top_v2.v \
    $proj_dir/src/seg_display_v2.v \
    $proj_dir/src/matrix/matrix_storage_v2.v \
    $proj_dir/src/uatr/matrix_uart_input_v2.v \
    $proj_dir/src/uatr/matrix_uart_output_v2.v \
]

# 添加矩阵计算模块（如果还没添加）
add_files -norecurse [list \
    $proj_dir/src/matrix/matrix_calc_unit.v \
    $proj_dir/src/matrix/mat_transpose.v \
    $proj_dir/src/matrix/mat_add.v \
    $proj_dir/src/matrix/mat_scalar_mult.v \
    $proj_dir/src/matrix/mat_mul.v \
    $proj_dir/src/matrix/mat_conv.v \
    $proj_dir/src/matrix/input_image_rom.v \
]

# 启用可能被禁用的文件
set disabled_files [get_files -filter {IS_ENABLED == 0}]
foreach f $disabled_files {
    set_property IS_ENABLED TRUE $f
}

# 设置顶层模块为V2版本
set_property top matrix_calc_top_v2 [current_fileset]

# 更新编译顺序
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "========================================="
puts "源文件添加完成！"
puts "顶层模块已设置为：matrix_calc_top_v2"
puts "========================================="
puts ""
puts "使用说明："
puts "1. 拨码开关SW[3:0]选择工作模式："
puts "   0001 = 输入矩阵模式"
puts "   0010 = 生成矩阵模式"
puts "   0100 = 显示矩阵模式"
puts "   1000 = 计算模式"
puts ""
puts "2. 计算模式下，SW[7:4]选择运算类型："
puts "   0001 = 转置(T)"
puts "   0010 = 加法(A)"
puts "   0100 = 标量乘法(b)"
puts "   1000 = 矩阵乘法(C)"
puts "   1001 = 卷积(J)"
puts ""
puts "3. UART输入格式："
puts "   m n e11 e12 ... emn"
puts "   例如：2 3 1 2 3 4 5 6"
puts "========================================="
