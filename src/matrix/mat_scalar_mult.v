`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名称: mat_scalar_mult (标量乘法模块)
// 功能描述: 实现标量与矩阵的乘法运算 C = scalar × A
// 特点: 使用并行乘法器，所有25个乘法在组合逻辑中同时完成
// 存储格式: 输入矩阵按行优先展开，A[i][j] 存储在 mat_A[(i*5+j)*8 +: 8]
// 支持规格: 最大支持5×5矩阵，每个元素8位无符号整数
//////////////////////////////////////////////////////////////////////////////////

module mat_scalar_mult (
    //==================== 输入端口 ====================
    input  wire        clk,         // 系统时钟信号，上升沿触发
    input  wire        rst_n,       // 异步复位信号，低电平有效
    input  wire        start,       // 开始计算信号，高电平触发计算
    input  wire [2:0]  rows,        // 矩阵行数 m，有效范围1-5
    input  wire [2:0]  cols,        // 矩阵列数 n，有效范围1-5
    input  wire [7:0]  scalar,      // 标量值（8位无符号整数，支持0-255）
    input  wire [199:0] mat_A,      // 输入矩阵A，展开为200位 (5×5×8bit = 200bit)

    //==================== 输出端口 ====================
    output reg  [199:0] mat_C,      // 结果矩阵C = scalar × A
    output reg  [2:0]  result_rows, // 结果矩阵的行数，等于输入rows
    output reg  [2:0]  result_cols, // 结果矩阵的列数，等于输入cols
    output reg         done         // 计算完成标志，高电平表示计算完成
    // 注意：此模块没有error输出，因为标量乘法不需要维度匹配检查
);

    //==================== 状态机状态定义 ====================
    // 标量乘法相对简单，只需3个状态
    localparam IDLE = 2'd0;         // 空闲状态：等待start信号
    localparam CALC = 2'd1;         // 计算状态：逐元素存储乘法结果
    localparam DONE = 2'd2;         // 完成状态：输出结果，等待start撤销

    //==================== 内部寄存器定义 ====================
    reg [1:0] state;                // 当前状态寄存器，2位可表示3个状态
    reg [2:0] i, j;                 // 二维循环计数器，i为行索引，j为列索引
    reg [4:0] idx;                  // 线性索引，范围0-24

    //==================== 并行乘法器（核心设计亮点）====================
    // 使用wire数组和assign语句实现25个并行乘法器
    // 这是组合逻辑，所有乘法在一个时钟周期内同时完成，无需等待
    // 乘法结果为16位（8位×8位=16位），可以完整保存中间结果
    wire [15:0] product [0:24];

    // 第0行元素乘法 (索引0-4)
    assign product[0]  = mat_A[7:0]     * scalar;  // A[0][0] × scalar
    assign product[1]  = mat_A[15:8]    * scalar;  // A[0][1] × scalar
    assign product[2]  = mat_A[23:16]   * scalar;  // A[0][2] × scalar
    assign product[3]  = mat_A[31:24]   * scalar;  // A[0][3] × scalar
    assign product[4]  = mat_A[39:32]   * scalar;  // A[0][4] × scalar

    // 第1行元素乘法 (索引5-9)
    assign product[5]  = mat_A[47:40]   * scalar;  // A[1][0] × scalar
    assign product[6]  = mat_A[55:48]   * scalar;  // A[1][1] × scalar
    assign product[7]  = mat_A[63:56]   * scalar;  // A[1][2] × scalar
    assign product[8]  = mat_A[71:64]   * scalar;  // A[1][3] × scalar
    assign product[9]  = mat_A[79:72]   * scalar;  // A[1][4] × scalar

    // 第2行元素乘法 (索引10-14)
    assign product[10] = mat_A[87:80]   * scalar;  // A[2][0] × scalar
    assign product[11] = mat_A[95:88]   * scalar;  // A[2][1] × scalar
    assign product[12] = mat_A[103:96]  * scalar;  // A[2][2] × scalar
    assign product[13] = mat_A[111:104] * scalar;  // A[2][3] × scalar
    assign product[14] = mat_A[119:112] * scalar;  // A[2][4] × scalar

    // 第3行元素乘法 (索引15-19)
    assign product[15] = mat_A[127:120] * scalar;  // A[3][0] × scalar
    assign product[16] = mat_A[135:128] * scalar;  // A[3][1] × scalar
    assign product[17] = mat_A[143:136] * scalar;  // A[3][2] × scalar
    assign product[18] = mat_A[151:144] * scalar;  // A[3][3] × scalar
    assign product[19] = mat_A[159:152] * scalar;  // A[3][4] × scalar

    // 第4行元素乘法 (索引20-24)
    assign product[20] = mat_A[167:160] * scalar;  // A[4][0] × scalar
    assign product[21] = mat_A[175:168] * scalar;  // A[4][1] × scalar
    assign product[22] = mat_A[183:176] * scalar;  // A[4][2] × scalar
    assign product[23] = mat_A[191:184] * scalar;  // A[4][3] × scalar
    assign product[24] = mat_A[199:192] * scalar;  // A[4][4] × scalar

    //==================== 主状态机：时序逻辑 ====================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            //---------- 异步复位：初始化所有寄存器 ----------
            state <= IDLE;              // 状态机回到空闲状态
            done <= 1'b0;               // 清除完成标志
            i <= 3'd0;                  // 行索引清零
            j <= 3'd0;                  // 列索引清零
            idx <= 5'd0;                // 线性索引清零
            mat_C <= 200'd0;            // 结果矩阵清零
            result_rows <= 3'd0;        // 结果行数清零
            result_cols <= 3'd0;        // 结果列数清零
        end else begin
            case (state)
                //========== IDLE状态：等待开始信号 ==========
                IDLE: begin
                    done <= 1'b0;           // 清除上一次的完成标志
                    if (start) begin        // 检测到start信号
                        state <= CALC;      // 转移到计算状态
                        i <= 3'd0;          // 初始化行索引
                        j <= 3'd0;          // 初始化列索引
                        idx <= 5'd0;        // 初始化线性索引
                        mat_C <= 200'd0;    // 清空结果矩阵
                        result_rows <= rows;// 记录结果行数
                        result_cols <= cols;// 记录结果列数
                    end
                end

                //========== CALC状态：逐元素存储乘法结果 ==========
                // 注意：乘法已经在组合逻辑中完成，这里只是按顺序存储结果
                CALC: begin
                    // 外层循环：遍历行
                    if (i < rows) begin
                        // 内层循环：遍历列
                        if (j < cols) begin
                            // 核心操作：C[i][j] = scalar × A[i][j]
                            // 从预计算的product数组中取值，只保留低8位
                            // 高8位被丢弃（如果需要完整结果，可扩展输出位宽）
                            case (idx)
                                // 第0行元素存储
                                5'd0:  mat_C[7:0]     <= product[0][7:0];   // C[0][0]
                                5'd1:  mat_C[15:8]    <= product[1][7:0];   // C[0][1]
                                5'd2:  mat_C[23:16]   <= product[2][7:0];   // C[0][2]
                                5'd3:  mat_C[31:24]   <= product[3][7:0];   // C[0][3]
                                5'd4:  mat_C[39:32]   <= product[4][7:0];   // C[0][4]
                                // 第1行元素存储
                                5'd5:  mat_C[47:40]   <= product[5][7:0];   // C[1][0]
                                5'd6:  mat_C[55:48]   <= product[6][7:0];   // C[1][1]
                                5'd7:  mat_C[63:56]   <= product[7][7:0];   // C[1][2]
                                5'd8:  mat_C[71:64]   <= product[8][7:0];   // C[1][3]
                                5'd9:  mat_C[79:72]   <= product[9][7:0];   // C[1][4]
                                // 第2行元素存储
                                5'd10: mat_C[87:80]   <= product[10][7:0];  // C[2][0]
                                5'd11: mat_C[95:88]   <= product[11][7:0];  // C[2][1]
                                5'd12: mat_C[103:96]  <= product[12][7:0];  // C[2][2]
                                5'd13: mat_C[111:104] <= product[13][7:0];  // C[2][3]
                                5'd14: mat_C[119:112] <= product[14][7:0];  // C[2][4]
                                // 第3行元素存储
                                5'd15: mat_C[127:120] <= product[15][7:0];  // C[3][0]
                                5'd16: mat_C[135:128] <= product[16][7:0];  // C[3][1]
                                5'd17: mat_C[143:136] <= product[17][7:0];  // C[3][2]
                                5'd18: mat_C[151:144] <= product[18][7:0];  // C[3][3]
                                5'd19: mat_C[159:152] <= product[19][7:0];  // C[3][4]
                                // 第4行元素存储
                                5'd20: mat_C[167:160] <= product[20][7:0];  // C[4][0]
                                5'd21: mat_C[175:168] <= product[21][7:0];  // C[4][1]
                                5'd22: mat_C[183:176] <= product[22][7:0];  // C[4][2]
                                5'd23: mat_C[191:184] <= product[23][7:0];  // C[4][3]
                                5'd24: mat_C[199:192] <= product[24][7:0];  // C[4][4]
                                default: ;  // 默认不操作
                            endcase

                            // 更新索引，准备处理下一个元素
                            j <= j + 1'b1;          // 列索引加1
                            idx <= idx + 1'b1;      // 线性索引加1
                        end else begin
                            // 当前行处理完毕，换到下一行
                            j <= 3'd0;              // 列索引归零
                            i <= i + 1'b1;          // 行索引加1
                            // 计算下一行的起始索引：(i+1) * 5
                            // 这样可以跳过5×5存储格式中未使用的位置
                            idx <= (i + 1'b1) * 5;
                        end
                    end else begin
                        // 所有元素处理完毕
                        state <= DONE;
                    end
                end

                //========== DONE状态：输出完成信号 ==========
                DONE: begin
                    done <= 1'b1;           // 设置完成标志
                    // 握手协议：等待start信号撤销
                    if (!start) begin
                        state <= IDLE;      // 返回空闲状态
                    end
                end

                //========== 默认状态：异常恢复 ==========
                default: state <= IDLE;     // 异常时回到空闲状态
            endcase
        end
    end

endmodule
