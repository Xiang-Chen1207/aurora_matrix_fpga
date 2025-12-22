`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 标量乘法模块
// 功能：实现标量与矩阵的乘法运算 C = scalar × A
// 输入矩阵按行优先展开：A[i][j] 存储在 mat_A[(i*5+j)*8 +: 8]
// 最大支持5×5矩阵，每个元素8位
//////////////////////////////////////////////////////////////////////////////////
module mat_scalar_mult (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,       // 开始计算信号
    input  wire [2:0]  rows,        // 矩阵行数 m (1-5)
    input  wire [2:0]  cols,        // 矩阵列数 n (1-5)
    input  wire [7:0]  scalar,      // 标量值 (0-9扩展到8位)
    input  wire [199:0] mat_A,      // 输入矩阵A (5×5×8bit = 200bit)
    output reg  [199:0] mat_C,      // 结果矩阵C = scalar × A
    output reg  [2:0]  result_rows, // 结果行数 = rows
    output reg  [2:0]  result_cols, // 结果列数 = cols
    output reg         done         // 计算完成信号
);

    // 状态定义
    localparam IDLE = 2'd0;
    localparam CALC = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state;
    reg [2:0] i, j;  // 循环计数器
    reg [4:0] idx;   // 线性索引 (0-24)

    // 乘法结果临时存储
    wire [15:0] product [0:24];

    // 展开所有25个乘法运算（并行计算）
    assign product[0]  = mat_A[7:0]     * scalar;
    assign product[1]  = mat_A[15:8]    * scalar;
    assign product[2]  = mat_A[23:16]   * scalar;
    assign product[3]  = mat_A[31:24]   * scalar;
    assign product[4]  = mat_A[39:32]   * scalar;
    assign product[5]  = mat_A[47:40]   * scalar;
    assign product[6]  = mat_A[55:48]   * scalar;
    assign product[7]  = mat_A[63:56]   * scalar;
    assign product[8]  = mat_A[71:64]   * scalar;
    assign product[9]  = mat_A[79:72]   * scalar;
    assign product[10] = mat_A[87:80]   * scalar;
    assign product[11] = mat_A[95:88]   * scalar;
    assign product[12] = mat_A[103:96]  * scalar;
    assign product[13] = mat_A[111:104] * scalar;
    assign product[14] = mat_A[119:112] * scalar;
    assign product[15] = mat_A[127:120] * scalar;
    assign product[16] = mat_A[135:128] * scalar;
    assign product[17] = mat_A[143:136] * scalar;
    assign product[18] = mat_A[151:144] * scalar;
    assign product[19] = mat_A[159:152] * scalar;
    assign product[20] = mat_A[167:160] * scalar;
    assign product[21] = mat_A[175:168] * scalar;
    assign product[22] = mat_A[183:176] * scalar;
    assign product[23] = mat_A[191:184] * scalar;
    assign product[24] = mat_A[199:192] * scalar;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
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
                    if (start) begin
                        state <= CALC;
                        i <= 3'd0;
                        j <= 3'd0;
                        idx <= 5'd0;
                        mat_C <= 200'd0;
                        result_rows <= rows;
                        result_cols <= cols;
                    end
                end

                CALC: begin
                    if (i < rows) begin
                        if (j < cols) begin
                            // C[i][j] = scalar × A[i][j]
                            // 取product的低8位作为结果（如需要可扩展到16位）
                            case (idx)
                                5'd0:  mat_C[7:0]     <= product[0][7:0];
                                5'd1:  mat_C[15:8]    <= product[1][7:0];
                                5'd2:  mat_C[23:16]   <= product[2][7:0];
                                5'd3:  mat_C[31:24]   <= product[3][7:0];
                                5'd4:  mat_C[39:32]   <= product[4][7:0];
                                5'd5:  mat_C[47:40]   <= product[5][7:0];
                                5'd6:  mat_C[55:48]   <= product[6][7:0];
                                5'd7:  mat_C[63:56]   <= product[7][7:0];
                                5'd8:  mat_C[71:64]   <= product[8][7:0];
                                5'd9:  mat_C[79:72]   <= product[9][7:0];
                                5'd10: mat_C[87:80]   <= product[10][7:0];
                                5'd11: mat_C[95:88]   <= product[11][7:0];
                                5'd12: mat_C[103:96]  <= product[12][7:0];
                                5'd13: mat_C[111:104] <= product[13][7:0];
                                5'd14: mat_C[119:112] <= product[14][7:0];
                                5'd15: mat_C[127:120] <= product[15][7:0];
                                5'd16: mat_C[135:128] <= product[16][7:0];
                                5'd17: mat_C[143:136] <= product[17][7:0];
                                5'd18: mat_C[151:144] <= product[18][7:0];
                                5'd19: mat_C[159:152] <= product[19][7:0];
                                5'd20: mat_C[167:160] <= product[20][7:0];
                                5'd21: mat_C[175:168] <= product[21][7:0];
                                5'd22: mat_C[183:176] <= product[22][7:0];
                                5'd23: mat_C[191:184] <= product[23][7:0];
                                5'd24: mat_C[199:192] <= product[24][7:0];
                                default: ;
                            endcase

                            j <= j + 1'b1;
                            idx <= idx + 1'b1;
                        end else begin
                            j <= 3'd0;
                            i <= i + 1'b1;
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
