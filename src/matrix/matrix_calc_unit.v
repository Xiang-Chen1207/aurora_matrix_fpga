`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 矩阵计算总控模块 - Verilog-2001兼容版本
// 功能：根据操作类型调用不同的矩阵运算模块
// 操作类型定义：
//   4'b0001 = 转置 (T)
//   4'b0010 = 加法 (A)
//   4'b0100 = 标量乘法 (B)
//   4'b1000 = 矩阵乘法 (C)
//   4'b1001 = 卷积 (J) - Bonus
//////////////////////////////////////////////////////////////////////////////////
module matrix_calc_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,           // 开始计算
    input  wire [3:0]  op_type,         // 操作类型
    input  wire [2:0]  rows_A,          // 矩阵A行数
    input  wire [2:0]  cols_A,          // 矩阵A列数
    input  wire [2:0]  rows_B,          // 矩阵B行数（用于乘法和加法）
    input  wire [2:0]  cols_B,          // 矩阵B列数
    input  wire [7:0]  scalar,          // 标量值（用于标量乘法）
    input  wire [199:0] mat_A,          // 输入矩阵A (5×5×8bit)
    input  wire [199:0] mat_B,          // 输入矩阵B
    input  wire [71:0]  conv_kernel,    // 卷积核 (3×3×8bit = 72bit)
    output reg  [199:0] result,         // 计算结果（普通矩阵运算）
    output wire [639:0] conv_result,    // 卷积结果（8×10×8bit = 640bit）
    output reg  [2:0]  result_rows,     // 结果行数
    output reg  [2:0]  result_cols,     // 结果列数
    output reg  [31:0] conv_cycles,     // 卷积周期数
    output reg         done,            // 计算完成
    output reg         error            // 计算错误
);

    // ============================================
    // 各运算模块信号定义
    // ============================================

    // 转置模块
    wire        transpose_start;
    wire [199:0] transpose_result;
    wire [2:0]  transpose_result_rows;
    wire [2:0]  transpose_result_cols;
    wire        transpose_done;

    // 加法模块
    wire        add_start;
    wire [199:0] add_result;
    wire [2:0]  add_result_rows;
    wire [2:0]  add_result_cols;
    wire        add_done;
    wire        add_error;

    // 标量乘法模块
    wire        scalar_start;
    wire [199:0] scalar_result;
    wire [2:0]  scalar_result_rows;
    wire [2:0]  scalar_result_cols;
    wire        scalar_done;

    // 矩阵乘法模块
    wire        mul_start;
    wire [199:0] mul_result;
    wire [2:0]  mul_result_rows;
    wire [2:0]  mul_result_cols;
    wire        mul_done;
    wire        mul_error;

    // 卷积模块
    wire        conv_start;
    wire [639:0] conv_result_internal;
    wire [31:0] conv_cycle_count;
    wire        conv_done;

    // ============================================
    // 启动信号控制
    // ============================================
    assign transpose_start = start && (op_type == 4'b0001);
    assign add_start       = start && (op_type == 4'b0010);
    assign scalar_start    = start && (op_type == 4'b0100);
    assign mul_start       = start && (op_type == 4'b1000);
    assign conv_start      = start && (op_type == 4'b1001);

    // ============================================
    // 实例化所有运算模块
    // ============================================

    // 矩阵转置
    mat_transpose u_transpose (
        .clk(clk),
        .rst_n(rst_n),
        .start(transpose_start),
        .rows(rows_A),
        .cols(cols_A),
        .mat_A(mat_A),
        .mat_C(transpose_result),
        .result_rows(transpose_result_rows),
        .result_cols(transpose_result_cols),
        .done(transpose_done)
    );

    // 矩阵加法
    mat_add u_add (
        .clk(clk),
        .rst_n(rst_n),
        .start(add_start),
        .rows(rows_A),
        .cols(cols_A),
        .mat_A(mat_A),
        .mat_B(mat_B),
        .mat_C(add_result),
        .result_rows(add_result_rows),
        .result_cols(add_result_cols),
        .done(add_done),
        .error(add_error)
    );

    // 标量乘法
    mat_scalar_mult u_scalar_mult (
        .clk(clk),
        .rst_n(rst_n),
        .start(scalar_start),
        .rows(rows_A),
        .cols(cols_A),
        .scalar(scalar),
        .mat_A(mat_A),
        .mat_C(scalar_result),
        .result_rows(scalar_result_rows),
        .result_cols(scalar_result_cols),
        .done(scalar_done)
    );

    // 矩阵乘法
    mat_mul u_mul (
        .clk(clk),
        .rst_n(rst_n),
        .start(mul_start),
        .rows_A(rows_A),
        .cols_A(cols_A),
        .cols_B(cols_B),
        .mat_A(mat_A),
        .mat_B(mat_B),
        .mat_C(mul_result),
        .result_rows(mul_result_rows),
        .result_cols(mul_result_cols),
        .done(mul_done),
        .error(mul_error)
    );

    // 卷积运算
    mat_conv u_conv (
        .clk(clk),
        .rst_n(rst_n),
        .start(conv_start),
        .kernel(conv_kernel),
        .result(conv_result_internal),
        .cycle_count(conv_cycle_count),
        .done(conv_done)
    );

    // 卷积结果输出
    assign conv_result = conv_result_internal;

    // ============================================
    // 结果选择和状态输出
    // ============================================
    always @(*) begin
        // 默认值
        result = 200'd0;
        result_rows = 3'd0;
        result_cols = 3'd0;
        done = 1'b0;
        error = 1'b0;
        conv_cycles = 32'd0;

        case (op_type)
            4'b0001: begin // 转置
                result = transpose_result;
                result_rows = transpose_result_rows;
                result_cols = transpose_result_cols;
                done = transpose_done;
                error = 1'b0;
            end

            4'b0010: begin // 加法
                result = add_result;
                result_rows = add_result_rows;
                result_cols = add_result_cols;
                done = add_done;
                error = add_error;
            end

            4'b0100: begin // 标量乘法
                result = scalar_result;
                result_rows = scalar_result_rows;
                result_cols = scalar_result_cols;
                done = scalar_done;
                error = 1'b0;
            end

            4'b1000: begin // 矩阵乘法
                result = mul_result;
                result_rows = mul_result_rows;
                result_cols = mul_result_cols;
                done = mul_done;
                error = mul_error;
            end

            4'b1001: begin // 卷积
                // 卷积结果通过conv_result输出
                result_rows = 3'd5;  // 实际是8行
                result_cols = 3'd5;  // 实际是10列
                done = conv_done;
                error = 1'b0;
                conv_cycles = conv_cycle_count;
            end

            default: begin
                error = 1'b1;
            end
        endcase
    end

endmodule
