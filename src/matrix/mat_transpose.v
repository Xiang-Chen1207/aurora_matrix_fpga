`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 矩阵转置模块
// 功能：实现矩阵的转置运算 A(m×n) -> C(n×m)
// 输入矩阵按行优先展开：A[i][j] 存储在 mat_A[(i*5+j)*8 +: 8]
// 输出矩阵：C[j][i] = A[i][j]，即 mat_C[(j*5+i)*8 +: 8] = mat_A[(i*5+j)*8 +: 8]
//////////////////////////////////////////////////////////////////////////////////
module mat_transpose (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,       // 开始计算信号
    input  wire [2:0]  rows,        // 原矩阵行数 m (1-5)
    input  wire [2:0]  cols,        // 原矩阵列数 n (1-5)
    input  wire [199:0] mat_A,      // 输入矩阵A (5×5×8bit = 200bit)
    output reg  [199:0] mat_C,      // 转置结果矩阵C
    output reg  [2:0]  result_rows, // 结果行数 = cols
    output reg  [2:0]  result_cols, // 结果列数 = rows
    output reg         done         // 计算完成信号
);

    // 状态定义
    localparam IDLE = 2'd0;
    localparam CALC = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state;
    reg [2:0] i, j;  // 循环计数器

    // 获取矩阵元素的函数（按行优先存储）
    // 索引 = (row * 5 + col) * 8
    function [7:0] get_element;
        input [199:0] matrix;
        input [2:0] row;
        input [2:0] col;
        reg [7:0] idx;
        begin
            idx = (row * 5 + col) * 8;
            get_element = matrix[idx +: 8];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            i <= 3'd0;
            j <= 3'd0;
            mat_C <= 200'd0;
            result_rows <= 3'd0;
            result_cols <= 3'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= CALC;
                        i <= 3'd0;
                        j <= 3'd0;
                        mat_C <= 200'd0;
                        result_rows <= cols;  // 转置后行数 = 原列数
                        result_cols <= rows;  // 转置后列数 = 原行数
                    end
                end

                CALC: begin
                    // 转置操作：C[j][i] = A[i][j]
                    // C的索引 = (j * 5 + i) * 8
                    // A的索引 = (i * 5 + j) * 8
                    if (i < rows) begin
                        if (j < cols) begin
                            // 设置 mat_C[j][i] = mat_A[i][j]
                            case ({i, j})
                                // i=0的情况
                                6'b000_000: mat_C[7:0]     <= mat_A[7:0];      // C[0][0]=A[0][0]
                                6'b000_001: mat_C[47:40]   <= mat_A[15:8];     // C[1][0]=A[0][1]
                                6'b000_010: mat_C[87:80]   <= mat_A[23:16];    // C[2][0]=A[0][2]
                                6'b000_011: mat_C[127:120] <= mat_A[31:24];    // C[3][0]=A[0][3]
                                6'b000_100: mat_C[167:160] <= mat_A[39:32];    // C[4][0]=A[0][4]
                                // i=1的情况
                                6'b001_000: mat_C[15:8]    <= mat_A[47:40];    // C[0][1]=A[1][0]
                                6'b001_001: mat_C[55:48]   <= mat_A[55:48];    // C[1][1]=A[1][1]
                                6'b001_010: mat_C[95:88]   <= mat_A[63:56];    // C[2][1]=A[1][2]
                                6'b001_011: mat_C[135:128] <= mat_A[71:64];    // C[3][1]=A[1][3]
                                6'b001_100: mat_C[175:168] <= mat_A[79:72];    // C[4][1]=A[1][4]
                                // i=2的情况
                                6'b010_000: mat_C[23:16]   <= mat_A[87:80];    // C[0][2]=A[2][0]
                                6'b010_001: mat_C[63:56]   <= mat_A[95:88];    // C[1][2]=A[2][1]
                                6'b010_010: mat_C[103:96]  <= mat_A[103:96];   // C[2][2]=A[2][2]
                                6'b010_011: mat_C[143:136] <= mat_A[111:104];  // C[3][2]=A[2][3]
                                6'b010_100: mat_C[183:176] <= mat_A[119:112];  // C[4][2]=A[2][4]
                                // i=3的情况
                                6'b011_000: mat_C[31:24]   <= mat_A[127:120];  // C[0][3]=A[3][0]
                                6'b011_001: mat_C[71:64]   <= mat_A[135:128];  // C[1][3]=A[3][1]
                                6'b011_010: mat_C[111:104] <= mat_A[143:136];  // C[2][3]=A[3][2]
                                6'b011_011: mat_C[151:144] <= mat_A[151:144];  // C[3][3]=A[3][3]
                                6'b011_100: mat_C[191:184] <= mat_A[159:152];  // C[4][3]=A[3][4]
                                // i=4的情况
                                6'b100_000: mat_C[39:32]   <= mat_A[167:160];  // C[0][4]=A[4][0]
                                6'b100_001: mat_C[79:72]   <= mat_A[175:168];  // C[1][4]=A[4][1]
                                6'b100_010: mat_C[119:112] <= mat_A[183:176];  // C[2][4]=A[4][2]
                                6'b100_011: mat_C[159:152] <= mat_A[191:184];  // C[3][4]=A[4][3]
                                6'b100_100: mat_C[199:192] <= mat_A[199:192];  // C[4][4]=A[4][4]
                                default: ;
                            endcase

                            j <= j + 1'b1;
                        end else begin
                            j <= 3'd0;
                            i <= i + 1'b1;
                        end
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    done <= 1'b1;
                    if (!start) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
