`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 矩阵计算模块测试平台
// 功能：验证所有矩阵运算模块的正确性
// 包括：转置、加法、标量乘法、矩阵乘法、卷积
//////////////////////////////////////////////////////////////////////////////////
module tb_matrix_calc;

    // 时钟和复位
    reg clk;
    reg rst_n;

    // 控制信号
    reg start;
    reg [3:0] op_type;
    reg [2:0] rows_A, cols_A, rows_B, cols_B;
    reg [7:0] scalar;
    reg [199:0] mat_A, mat_B;
    reg [71:0] conv_kernel;

    // 输出信号
    wire [199:0] result;
    wire [639:0] conv_result;
    wire [2:0] result_rows, result_cols;
    wire [31:0] conv_cycles;
    wire done;
    wire error;

    // 实例化待测模块
    matrix_calc_unit uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .op_type(op_type),
        .rows_A(rows_A),
        .cols_A(cols_A),
        .rows_B(rows_B),
        .cols_B(cols_B),
        .scalar(scalar),
        .mat_A(mat_A),
        .mat_B(mat_B),
        .conv_kernel(conv_kernel),
        .result(result),
        .conv_result(conv_result),
        .result_rows(result_rows),
        .result_cols(result_cols),
        .conv_cycles(conv_cycles),
        .done(done),
        .error(error)
    );

    // 时钟生成 (10ns周期 = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 辅助函数：设置矩阵元素
    // mat[i][j] = mat[(i*5+j)*8 +: 8]
    task set_matrix_element;
        input [199:0] mat;
        input [2:0] row, col;
        input [7:0] value;
        begin
            case (row * 5 + col)
                0:  mat_A[7:0]     = value;
                1:  mat_A[15:8]    = value;
                2:  mat_A[23:16]   = value;
                3:  mat_A[31:24]   = value;
                4:  mat_A[39:32]   = value;
                5:  mat_A[47:40]   = value;
                6:  mat_A[55:48]   = value;
                7:  mat_A[63:56]   = value;
                8:  mat_A[71:64]   = value;
                9:  mat_A[79:72]   = value;
                10: mat_A[87:80]   = value;
                11: mat_A[95:88]   = value;
                12: mat_A[103:96]  = value;
                13: mat_A[111:104] = value;
                14: mat_A[119:112] = value;
                15: mat_A[127:120] = value;
                16: mat_A[135:128] = value;
                17: mat_A[143:136] = value;
                18: mat_A[151:144] = value;
                19: mat_A[159:152] = value;
                20: mat_A[167:160] = value;
                21: mat_A[175:168] = value;
                22: mat_A[183:176] = value;
                23: mat_A[191:184] = value;
                24: mat_A[199:192] = value;
            endcase
        end
    endtask

    // 辅助函数：获取结果矩阵元素
    function [7:0] get_result_element;
        input [2:0] row, col;
        reg [4:0] idx;
        begin
            idx = row * 5 + col;
            case (idx)
                0:  get_result_element = result[7:0];
                1:  get_result_element = result[15:8];
                2:  get_result_element = result[23:16];
                3:  get_result_element = result[31:24];
                4:  get_result_element = result[39:32];
                5:  get_result_element = result[47:40];
                6:  get_result_element = result[55:48];
                7:  get_result_element = result[63:56];
                8:  get_result_element = result[71:64];
                9:  get_result_element = result[79:72];
                10: get_result_element = result[87:80];
                11: get_result_element = result[95:88];
                12: get_result_element = result[103:96];
                13: get_result_element = result[111:104];
                14: get_result_element = result[119:112];
                15: get_result_element = result[127:120];
                16: get_result_element = result[135:128];
                17: get_result_element = result[143:136];
                18: get_result_element = result[151:144];
                19: get_result_element = result[159:152];
                20: get_result_element = result[167:160];
                21: get_result_element = result[175:168];
                22: get_result_element = result[183:176];
                23: get_result_element = result[191:184];
                24: get_result_element = result[199:192];
                default: get_result_element = 8'd0;
            endcase
        end
    endfunction

    // 打印矩阵结果
    task print_result_matrix;
        input [2:0] rows, cols;
        integer i, j;
        begin
            $display("Result Matrix (%0dx%0d):", rows, cols);
            for (i = 0; i < rows; i = i + 1) begin
                $write("  ");
                for (j = 0; j < cols; j = j + 1) begin
                    $write("%3d ", get_result_element(i, j));
                end
                $write("\n");
            end
        end
    endtask

    // 主测试过程
    initial begin
        // 初始化
        rst_n = 0;
        start = 0;
        op_type = 4'b0000;
        rows_A = 0; cols_A = 0;
        rows_B = 0; cols_B = 0;
        scalar = 0;
        mat_A = 200'd0;
        mat_B = 200'd0;
        conv_kernel = 72'd0;

        // 复位
        #20;
        rst_n = 1;
        #20;

        // ============================================
        // 测试1：矩阵转置
        // A = [1 2 3]  -> C = [1 4]
        //     [4 5 6]        [2 5]
        //                    [3 6]
        // ============================================
        $display("\n========== Test 1: Matrix Transpose ==========");

        // 设置矩阵A (2x3)
        mat_A = 200'd0;
        mat_A[7:0]   = 8'd1;  // A[0][0]
        mat_A[15:8]  = 8'd2;  // A[0][1]
        mat_A[23:16] = 8'd3;  // A[0][2]
        mat_A[47:40] = 8'd4;  // A[1][0]
        mat_A[55:48] = 8'd5;  // A[1][1]
        mat_A[63:56] = 8'd6;  // A[1][2]

        rows_A = 3'd2;
        cols_A = 3'd3;
        op_type = 4'b0001;  // 转置

        start = 1;
        @(posedge clk);
        start = 0;

        // 等待完成
        wait(done);
        #10;

        $display("Transpose completed!");
        $display("Result rows: %0d, cols: %0d", result_rows, result_cols);
        print_result_matrix(result_rows, result_cols);

        // ============================================
        // 测试2：矩阵加法
        // A = [1 2]  B = [3 4]  -> C = [4 6]
        //     [3 4]      [1 2]        [4 6]
        // ============================================
        $display("\n========== Test 2: Matrix Addition ==========");
        #50;

        // 设置矩阵A (2x2)
        mat_A = 200'd0;
        mat_A[7:0]   = 8'd1;  // A[0][0]
        mat_A[15:8]  = 8'd2;  // A[0][1]
        mat_A[47:40] = 8'd3;  // A[1][0]
        mat_A[55:48] = 8'd4;  // A[1][1]

        // 设置矩阵B (2x2)
        mat_B = 200'd0;
        mat_B[7:0]   = 8'd3;  // B[0][0]
        mat_B[15:8]  = 8'd4;  // B[0][1]
        mat_B[47:40] = 8'd1;  // B[1][0]
        mat_B[55:48] = 8'd2;  // B[1][1]

        rows_A = 3'd2;
        cols_A = 3'd2;
        op_type = 4'b0010;  // 加法

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        #10;

        $display("Addition completed!");
        print_result_matrix(result_rows, result_cols);

        // ============================================
        // 测试3：标量乘法
        // A = [1 2 3]  scalar = 3 -> C = [3 6 9]
        //     [3 4 5]                    [9 12 15]
        // ============================================
        $display("\n========== Test 3: Scalar Multiplication ==========");
        #50;

        // 设置矩阵A (2x3)
        mat_A = 200'd0;
        mat_A[7:0]   = 8'd1;  // A[0][0]
        mat_A[15:8]  = 8'd2;  // A[0][1]
        mat_A[23:16] = 8'd3;  // A[0][2]
        mat_A[47:40] = 8'd3;  // A[1][0]
        mat_A[55:48] = 8'd4;  // A[1][1]
        mat_A[63:56] = 8'd5;  // A[1][2]

        rows_A = 3'd2;
        cols_A = 3'd3;
        scalar = 8'd3;
        op_type = 4'b0100;  // 标量乘法

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        #10;

        $display("Scalar multiplication completed! (scalar = 3)");
        print_result_matrix(result_rows, result_cols);

        // ============================================
        // 测试4：矩阵乘法
        // A = [1 2 3]    B = [1 0]    C = [14 8]
        //     [3 4 5]        [2 1]        [26 14]
        //                    [3 2]
        // ============================================
        $display("\n========== Test 4: Matrix Multiplication ==========");
        #50;

        // 设置矩阵A (2x3)
        mat_A = 200'd0;
        mat_A[7:0]   = 8'd1;  // A[0][0]
        mat_A[15:8]  = 8'd2;  // A[0][1]
        mat_A[23:16] = 8'd3;  // A[0][2]
        mat_A[47:40] = 8'd3;  // A[1][0]
        mat_A[55:48] = 8'd4;  // A[1][1]
        mat_A[63:56] = 8'd5;  // A[1][2]

        // 设置矩阵B (3x2)
        mat_B = 200'd0;
        mat_B[7:0]   = 8'd1;  // B[0][0]
        mat_B[15:8]  = 8'd0;  // B[0][1]
        mat_B[47:40] = 8'd2;  // B[1][0]
        mat_B[55:48] = 8'd1;  // B[1][1]
        mat_B[87:80] = 8'd3;  // B[2][0]
        mat_B[95:88] = 8'd2;  // B[2][1]

        rows_A = 3'd2;
        cols_A = 3'd3;
        cols_B = 3'd2;
        op_type = 4'b1000;  // 矩阵乘法

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        #10;

        $display("Matrix multiplication completed!");
        $display("Expected: C[0][0]=14, C[0][1]=8, C[1][0]=26, C[1][1]=14");
        print_result_matrix(result_rows, result_cols);

        // ============================================
        // 测试5：卷积运算
        // 使用3x3卷积核
        // ============================================
        $display("\n========== Test 5: Convolution ==========");
        #50;

        // 设置卷积核 (3x3)
        // kernel = [0 1 0]
        //          [1 2 1]
        //          [0 1 0]
        conv_kernel = 72'd0;
        conv_kernel[7:0]   = 8'd0;  // K[0][0]
        conv_kernel[15:8]  = 8'd1;  // K[0][1]
        conv_kernel[23:16] = 8'd0;  // K[0][2]
        conv_kernel[31:24] = 8'd1;  // K[1][0]
        conv_kernel[39:32] = 8'd2;  // K[1][1]
        conv_kernel[47:40] = 8'd1;  // K[1][2]
        conv_kernel[55:48] = 8'd0;  // K[2][0]
        conv_kernel[63:56] = 8'd1;  // K[2][1]
        conv_kernel[71:64] = 8'd0;  // K[2][2]

        op_type = 4'b1001;  // 卷积

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        #10;

        $display("Convolution completed!");
        $display("Total cycles: %0d", conv_cycles);
        $display("Output size: 8x10");

        // 打印卷积结果的前几个元素
        $display("First row of convolution result:");
        $write("  ");
        $write("%3d ", conv_result[7:0]);
        $write("%3d ", conv_result[15:8]);
        $write("%3d ", conv_result[23:16]);
        $write("%3d ", conv_result[31:24]);
        $write("%3d ", conv_result[39:32]);
        $write("%3d ", conv_result[47:40]);
        $write("%3d ", conv_result[55:48]);
        $write("%3d ", conv_result[63:56]);
        $write("%3d ", conv_result[71:64]);
        $write("%3d ", conv_result[79:72]);
        $write("\n");

        // ============================================
        // 测试完成
        // ============================================
        #100;
        $display("\n========== All Tests Completed ==========");
        $finish;
    end

    // 超时保护
    initial begin
        #100000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
