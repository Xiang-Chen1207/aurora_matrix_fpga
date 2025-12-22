`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 矩阵加法模块
// 功能：实现两个同维度矩阵的加法运算 C = A + B
// 输入矩阵按行优先展开：A[i][j] 存储在 mat_A[(i*5+j)*8 +: 8]
// 最大支持5×5矩阵，每个元素8位
//////////////////////////////////////////////////////////////////////////////////
module mat_add (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,       // 开始计算信号
    input  wire [2:0]  rows,        // 矩阵行数 m (1-5)
    input  wire [2:0]  cols,        // 矩阵列数 n (1-5)
    input  wire [199:0] mat_A,      // 输入矩阵A (5×5×8bit = 200bit)
    input  wire [199:0] mat_B,      // 输入矩阵B
    output reg  [199:0] mat_C,      // 结果矩阵C = A + B
    output reg  [2:0]  result_rows, // 结果行数 = rows
    output reg  [2:0]  result_cols, // 结果列数 = cols
    output reg         done,        // 计算完成信号
    output reg         error        // 错误标志（维度无效）
);

    // 状态定义
    localparam IDLE  = 2'd0;
    localparam CHECK = 2'd1;
    localparam CALC  = 2'd2;
    localparam DONE  = 2'd3;

    reg [1:0] state;
    reg [2:0] i, j;  // 循环计数器
    reg [4:0] idx;   // 线性索引 (0-24)

    // 临时变量用于计算
    wire [7:0] a_elem, b_elem;
    wire [7:0] sum;

    // 根据idx获取元素
    assign a_elem = mat_A[idx*8 +: 8];
    assign b_elem = mat_B[idx*8 +: 8];
    assign sum = a_elem + b_elem;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            error <= 1'b0;
            i <= 3'd0;
            j <= 3'd0;
            idx <= 5'd0;
            mat_C <= 200'd0;
            result_rows <= 3'd0;
            result_cols <= 3'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    if (start) begin
                        state <= CHECK;
                    end
                end

                CHECK: begin
                    // 检查维度有效性
                    if (rows >= 3'd1 && rows <= 3'd5 && cols >= 3'd1 && cols <= 3'd5) begin
                        state <= CALC;
                        i <= 3'd0;
                        j <= 3'd0;
                        idx <= 5'd0;
                        mat_C <= 200'd0;
                        result_rows <= rows;
                        result_cols <= cols;
                    end else begin
                        error <= 1'b1;
                        state <= DONE;
                    end
                end

                CALC: begin
                    if (i < rows) begin
                        if (j < cols) begin
                            // C[i][j] = A[i][j] + B[i][j]
                            case (idx)
                                5'd0:  mat_C[7:0]     <= mat_A[7:0]     + mat_B[7:0];
                                5'd1:  mat_C[15:8]    <= mat_A[15:8]    + mat_B[15:8];
                                5'd2:  mat_C[23:16]   <= mat_A[23:16]   + mat_B[23:16];
                                5'd3:  mat_C[31:24]   <= mat_A[31:24]   + mat_B[31:24];
                                5'd4:  mat_C[39:32]   <= mat_A[39:32]   + mat_B[39:32];
                                5'd5:  mat_C[47:40]   <= mat_A[47:40]   + mat_B[47:40];
                                5'd6:  mat_C[55:48]   <= mat_A[55:48]   + mat_B[55:48];
                                5'd7:  mat_C[63:56]   <= mat_A[63:56]   + mat_B[63:56];
                                5'd8:  mat_C[71:64]   <= mat_A[71:64]   + mat_B[71:64];
                                5'd9:  mat_C[79:72]   <= mat_A[79:72]   + mat_B[79:72];
                                5'd10: mat_C[87:80]   <= mat_A[87:80]   + mat_B[87:80];
                                5'd11: mat_C[95:88]   <= mat_A[95:88]   + mat_B[95:88];
                                5'd12: mat_C[103:96]  <= mat_A[103:96]  + mat_B[103:96];
                                5'd13: mat_C[111:104] <= mat_A[111:104] + mat_B[111:104];
                                5'd14: mat_C[119:112] <= mat_A[119:112] + mat_B[119:112];
                                5'd15: mat_C[127:120] <= mat_A[127:120] + mat_B[127:120];
                                5'd16: mat_C[135:128] <= mat_A[135:128] + mat_B[135:128];
                                5'd17: mat_C[143:136] <= mat_A[143:136] + mat_B[143:136];
                                5'd18: mat_C[151:144] <= mat_A[151:144] + mat_B[151:144];
                                5'd19: mat_C[159:152] <= mat_A[159:152] + mat_B[159:152];
                                5'd20: mat_C[167:160] <= mat_A[167:160] + mat_B[167:160];
                                5'd21: mat_C[175:168] <= mat_A[175:168] + mat_B[175:168];
                                5'd22: mat_C[183:176] <= mat_A[183:176] + mat_B[183:176];
                                5'd23: mat_C[191:184] <= mat_A[191:184] + mat_B[191:184];
                                5'd24: mat_C[199:192] <= mat_A[199:192] + mat_B[199:192];
                                default: ;
                            endcase

                            j <= j + 1'b1;
                            idx <= idx + 1'b1;
                        end else begin
                            j <= 3'd0;
                            i <= i + 1'b1;
                            // 跳过本行剩余的元素（如果列数<5）
                            idx <= (i + 1'b1) * 5;
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
