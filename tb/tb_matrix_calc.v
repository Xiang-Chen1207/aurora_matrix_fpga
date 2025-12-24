`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 自检测试平台：验证矩阵计算单元的关键功能
// 覆盖：矩阵加法、矩阵乘法、向量点乘（用1xN·Nx1矩阵乘法建模）、卷积
// 判定：自动对比期望结果，输出 PASS/FAIL
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

    // 被测模块
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

    // 100 MHz 时钟
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 工具函数
    function [7:0] get_byte200;
        input [199:0] vec;
        input integer idx;
        begin
            get_byte200 = vec[idx*8 +: 8];
        end
    endfunction

    function [7:0] get_byte640;
        input [639:0] vec;
        input integer idx;
        begin
            get_byte640 = vec[idx*8 +: 8];
        end
    endfunction
    task pack_from_bufA;
        output reg [199:0] dst;
        integer i;
        begin
            dst = 200'd0;
            for (i = 0; i < 25; i = i + 1) dst[i*8 +: 8] = buf_A[i];
        end
    endtask

    task pack_from_bufB;
        output reg [199:0] dst;
        integer i;
        begin
            dst = 200'd0;
            for (i = 0; i < 25; i = i + 1) dst[i*8 +: 8] = buf_B[i];
        end
    endtask

    task pack_from_bufE;
        output reg [199:0] dst;
        integer i;
        begin
            dst = 200'd0;
            for (i = 0; i < 25; i = i + 1) dst[i*8 +: 8] = buf_E[i];
        end
    endtask

    task compare_matrix;
        input [127:0] name;
        input [199:0] expected_vec;
        input integer exp_rows;
        input integer exp_cols;
        input [199:0] actual_vec;
        input integer act_rows;
        input integer act_cols;
        integer r, c;
        integer mismatches;
        begin
            mismatches = 0;
            if (act_rows != exp_rows || act_cols != exp_cols) begin
                $display("[FAIL][%0s] dim mismatch exp=%0dx%0d got=%0dx%0d", name, exp_rows, exp_cols, act_rows, act_cols);
                disable compare_matrix;
            end
            for (r = 0; r < exp_rows; r = r + 1) begin
                for (c = 0; c < exp_cols; c = c + 1) begin
                    if (get_byte200(actual_vec, r*5 + c) !== get_byte200(expected_vec, r*5 + c)) begin
                        mismatches = mismatches + 1;
                        $display("[MISMATCH][%0s] r=%0d c=%0d exp=%0d got=%0d", name, r, c, get_byte200(expected_vec, r*5 + c), get_byte200(actual_vec, r*5 + c));
                    end
                end
            end
            if (mismatches == 0) $display("[PASS][%0s] matched %0d elements", name, exp_rows*exp_cols);
            else $display("[FAIL][%0s] %0d mismatches", name, mismatches);
        end
    endtask

    task compare_conv;
        input [127:0] name;
        input [639:0] expected_vec;
        input [639:0] actual_vec;
        integer idx;
        integer mismatches;
        begin
            mismatches = 0;
            for (idx = 0; idx < 80; idx = idx + 1) begin
                if (get_byte640(actual_vec, idx) !== get_byte640(expected_vec, idx)) begin
                    mismatches = mismatches + 1;
                    $display("[MISMATCH][%0s] idx=%0d exp=%0d got=%0d", name, idx, get_byte640(expected_vec, idx), get_byte640(actual_vec, idx));
                end
            end
            if (mismatches == 0) $display("[PASS][%0s] matched 80 elements", name);
            else $display("[FAIL][%0s] %0d mismatches", name, mismatches);
        end
    endtask

    // 共享缓冲
    reg [7:0] buf_A [0:24];
    reg [7:0] buf_B [0:24];
    reg [7:0] buf_E [0:24];
    reg [7:0] kernel_flat [0:8];
    reg [7:0] image_rom [0:9][0:11];
    reg [199:0] exp_vec;
    reg [639:0] conv_expected;

    task automatic clear_buffers;
        integer i;
        begin
            for (i = 0; i < 25; i = i + 1) begin
                buf_A[i] = 0;
                buf_B[i] = 0;
                buf_E[i] = 0;
            end
        end
    endtask

    task automatic init_image_rom;
        begin
            image_rom[0][0]=3;  image_rom[0][1]=7;  image_rom[0][2]=2;  image_rom[0][3]=9;  image_rom[0][4]=0;  image_rom[0][5]=5;  image_rom[0][6]=1;  image_rom[0][7]=8;  image_rom[0][8]=4;  image_rom[0][9]=6;  image_rom[0][10]=3; image_rom[0][11]=2;
            image_rom[1][0]=8;  image_rom[1][1]=1;  image_rom[1][2]=6;  image_rom[1][3]=4;  image_rom[1][4]=7;  image_rom[1][5]=3;  image_rom[1][6]=9;  image_rom[1][7]=0;  image_rom[1][8]=5;  image_rom[1][9]=2;  image_rom[1][10]=8; image_rom[1][11]=1;
            image_rom[2][0]=4;  image_rom[2][1]=9;  image_rom[2][2]=0;  image_rom[2][3]=2;  image_rom[2][4]=6;  image_rom[2][5]=8;  image_rom[2][6]=3;  image_rom[2][7]=5;  image_rom[2][8]=7;  image_rom[2][9]=1;  image_rom[2][10]=4; image_rom[2][11]=9;
            image_rom[3][0]=7;  image_rom[3][1]=3;  image_rom[3][2]=8;  image_rom[3][3]=5;  image_rom[3][4]=1;  image_rom[3][5]=4;  image_rom[3][6]=9;  image_rom[3][7]=2;  image_rom[3][8]=0;  image_rom[3][9]=6;  image_rom[3][10]=7; image_rom[3][11]=3;
            image_rom[4][0]=2;  image_rom[4][1]=6;  image_rom[4][2]=4;  image_rom[4][3]=0;  image_rom[4][4]=8;  image_rom[4][5]=7;  image_rom[4][6]=5;  image_rom[4][7]=3;  image_rom[4][8]=1;  image_rom[4][9]=9;  image_rom[4][10]=2; image_rom[4][11]=4;
            image_rom[5][0]=9;  image_rom[5][1]=0;  image_rom[5][2]=7;  image_rom[5][3]=3;  image_rom[5][4]=5;  image_rom[5][5]=2;  image_rom[5][6]=8;  image_rom[5][7]=6;  image_rom[5][8]=4;  image_rom[5][9]=1;  image_rom[5][10]=9; image_rom[5][11]=0;
            image_rom[6][0]=5;  image_rom[6][1]=8;  image_rom[6][2]=1;  image_rom[6][3]=6;  image_rom[6][4]=4;  image_rom[6][5]=9;  image_rom[6][6]=2;  image_rom[6][7]=7;  image_rom[6][8]=3;  image_rom[6][9]=0;  image_rom[6][10]=5; image_rom[6][11]=8;
            image_rom[7][0]=1;  image_rom[7][1]=4;  image_rom[7][2]=9;  image_rom[7][3]=2;  image_rom[7][4]=7;  image_rom[7][5]=0;  image_rom[7][6]=6;  image_rom[7][7]=8;  image_rom[7][8]=5;  image_rom[7][9]=3;  image_rom[7][10]=1; image_rom[7][11]=4;
            image_rom[8][0]=6;  image_rom[8][1]=2;  image_rom[8][2]=5;  image_rom[8][3]=8;  image_rom[8][4]=3;  image_rom[8][5]=1;  image_rom[8][6]=7;  image_rom[8][7]=4;  image_rom[8][8]=9;  image_rom[8][9]=0;  image_rom[8][10]=6; image_rom[8][11]=2;
            image_rom[9][0]=0;  image_rom[9][1]=7;  image_rom[9][2]=3;  image_rom[9][3]=9;  image_rom[9][4]=5;  image_rom[9][5]=6;  image_rom[9][6]=4;  image_rom[9][7]=1;  image_rom[9][8]=8;  image_rom[9][9]=2;  image_rom[9][10]=0; image_rom[9][11]=7;
        end
    endtask

    task automatic build_conv_expected;
        integer i, j, ki, kj;
        integer acc;
        begin
            conv_expected = 640'd0;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 10; j = j + 1) begin
                    acc = 0;
                    for (ki = 0; ki < 3; ki = ki + 1) begin
                        for (kj = 0; kj < 3; kj = kj + 1) begin
                            acc = acc + image_rom[i+ki][j+kj] * kernel_flat[ki*3+kj];
                        end
                    end
                    conv_expected[(i*10 + j)*8 +: 8] = acc[7:0];
                end
            end
        end
    endtask

    task run_matrix_test;
        input [127:0] name;
        input [3:0] op_sel;
        input integer rA;
        input integer cA;
        input integer rB;
        input integer cB;
        input [7:0] scalar_val;
        input [199:0] a_vec;
        input [199:0] b_vec;
        input [199:0] exp_vec;
        input integer exp_rows;
        input integer exp_cols;
        integer ticks;
        begin
            op_type = op_sel;
            rows_A = rA[2:0];
            cols_A = cA[2:0];
            rows_B = rB[2:0];
            cols_B = cB[2:0];
            scalar = scalar_val;
            mat_A = a_vec;
            mat_B = b_vec;

            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            ticks = 0;
            while (!done && ticks < 5000) begin
                @(posedge clk);
                ticks = ticks + 1;
            end

            if (!done) begin
                $display("[FAIL][%0s] timeout", name);
            end else if (error) begin
                $display("[FAIL][%0s] error flag set", name);
            end else begin
                compare_matrix(name, exp_vec, exp_rows, exp_cols, result, result_rows, result_cols);
            end
        end
    endtask

    task run_conv_test;
        input [127:0] name;
        input [71:0] kernel_bits;
        input [639:0] exp_vec;
        integer ticks;
        begin
            op_type = 4'b1001;
            rows_A = 3'd0;
            cols_A = 3'd0;
            rows_B = 3'd0;
            cols_B = 3'd0;
            scalar = 8'd0;
            mat_A = 200'd0;
            mat_B = 200'd0;
            conv_kernel = kernel_bits;

            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            ticks = 0;
            while (!done && ticks < 200000) begin
                @(posedge clk);
                ticks = ticks + 1;
            end

            if (!done) begin
                $display("[FAIL][%0s] timeout", name);
            end else if (error) begin
                $display("[FAIL][%0s] error flag set", name);
            end else begin
                $display("[INFO][%0s] conv_cycles=%0d", name, conv_cycles);
                compare_conv(name, exp_vec, conv_result);
            end
        end
    endtask

    // 主流程
    integer i;
    initial begin
        clear_buffers();
        init_image_rom();

        rst_n = 0;
        start = 0;
        op_type = 4'b0000;
        rows_A = 0; cols_A = 0; rows_B = 0; cols_B = 0;
        scalar = 0;
        mat_A = 0; mat_B = 0; conv_kernel = 0; exp_vec = 0;

        #20; rst_n = 1; #20;

        // 矩阵加法 2x2
        clear_buffers();
        buf_A[0]=1; buf_A[1]=2; buf_A[5]=3; buf_A[6]=4;
        buf_B[0]=3; buf_B[1]=4; buf_B[5]=1; buf_B[6]=2;
        buf_E[0]=4; buf_E[1]=6; buf_E[5]=4; buf_E[6]=6;
        pack_from_bufA(mat_A);
        pack_from_bufB(mat_B);
        pack_from_bufE(exp_vec);
        run_matrix_test("ADD 2x2", 4'b0010, 2, 2, 2, 2, 8'd0, mat_A, mat_B, exp_vec, 2, 2);
        #20;

        // 矩阵乘法 2x3 * 3x2
        clear_buffers();
        buf_A[0]=1; buf_A[1]=2; buf_A[2]=3; buf_A[5]=3; buf_A[6]=4; buf_A[7]=5;
        buf_B[0]=1; buf_B[1]=0; buf_B[5]=2; buf_B[6]=1; buf_B[10]=3; buf_B[11]=2;
        buf_E[0]=14; buf_E[1]=8; buf_E[5]=26; buf_E[6]=14;
        pack_from_bufA(mat_A);
        pack_from_bufB(mat_B);
        pack_from_bufE(exp_vec);
        run_matrix_test("MAT MUL 2x3x2", 4'b1000, 2, 3, 3, 2, 8'd0, mat_A, mat_B, exp_vec, 2, 2);
        #20;

        // 向量点乘（1x4 与 4x1，通过矩阵乘法实现）
        clear_buffers();
        buf_A[0]=1; buf_A[1]=2; buf_A[2]=3; buf_A[3]=4;
        buf_B[0]=5; buf_B[5]=6; buf_B[10]=7; buf_B[15]=8;
        buf_E[0]=70;
        pack_from_bufA(mat_A);
        pack_from_bufB(mat_B);
        pack_from_bufE(exp_vec);
        run_matrix_test("DOT 1x4·4x1", 4'b1000, 1, 4, 4, 1, 8'd0, mat_A, mat_B, exp_vec, 1, 1);
        #20;

        // 卷积（使用 ROM 输入图像 + 给定 3x3 核）
        kernel_flat[0]=0; kernel_flat[1]=1; kernel_flat[2]=0;
        kernel_flat[3]=1; kernel_flat[4]=2; kernel_flat[5]=1;
        kernel_flat[6]=0; kernel_flat[7]=1; kernel_flat[8]=0;
        conv_kernel = 72'd0;
        for (i = 0; i < 9; i = i + 1) begin
            conv_kernel[i*8 +: 8] = kernel_flat[i];
        end
        build_conv_expected();
        run_conv_test("CONV 8x10", conv_kernel, conv_expected);

        #50;
        $display("[INFO] All tests finished.");
        $finish;
    end

endmodule
