`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名称: mat_mul (矩阵乘法模块)
// 功能描述: 实现两个矩阵的乘法运算 A(m×n) × B(n×p) = C(m×p)
// 数学原理: C[i][j] = Σ(A[i][k] * B[k][j]), 其中k从0到n-1
// 约束条件: 矩阵A的列数必须等于矩阵B的行数
// 存储格式: 输入矩阵按行优先展开，A[i][j] 存储在 mat_A[(i*5+j)*8 +: 8]
// 支持规格: 最大支持5×5矩阵，每个元素8位无符号整数
//////////////////////////////////////////////////////////////////////////////////

module mat_mul (
    //==================== 输入端口 ====================
    input  wire        clk,         // 系统时钟信号，上升沿触发
    input  wire        rst_n,       // 异步复位信号，低电平有效
    input  wire        start,       // 开始计算信号，高电平触发计算
    input  wire [2:0]  rows_A,      // 矩阵A的行数 m，有效范围1-5
    input  wire [2:0]  cols_A,      // 矩阵A的列数 n，有效范围1-5，同时也是矩阵B的行数
    input  wire [2:0]  cols_B,      // 矩阵B的列数 p，有效范围1-5
    input  wire [199:0] mat_A,      // 输入矩阵A，展开为200位 (5×5×8bit = 200bit)
    input  wire [199:0] mat_B,      // 输入矩阵B，展开为200位 (5×5×8bit = 200bit)

    //==================== 输出端口 ====================
    output reg  [199:0] mat_C,      // 结果矩阵C = A × B，维度为 m×p
    output reg  [2:0]  result_rows, // 结果矩阵的行数，等于rows_A (m)
    output reg  [2:0]  result_cols, // 结果矩阵的列数，等于cols_B (p)
    output reg         done,        // 计算完成标志，高电平表示计算完成
    output reg         error        // 错误标志，高电平表示维度不满足乘法条件
);

    //==================== 状态机状态定义 ====================
    // 矩阵乘法需要更多状态来处理三重循环和累加操作
    localparam IDLE   = 3'd0;       // 空闲状态：等待start信号
    localparam CHECK  = 3'd1;       // 检查状态：验证输入维度的有效性
    localparam CALC   = 3'd2;       // 计算状态：获取A[i][k]和B[k][j]元素
    localparam SUM    = 3'd3;       // 累加状态：执行乘加运算 acc += A[i][k] * B[k][j]
    localparam STORE  = 3'd4;       // 存储状态：将累加结果存入C[i][j]
    localparam DONE   = 3'd5;       // 完成状态：输出结果，等待start撤销

    //==================== 内部寄存器定义 ====================
    reg [2:0] state;                // 当前状态寄存器，3位可表示6个状态
    reg [2:0] i, j, k;              // 三重循环计数器：i-行, j-列, k-累加索引
    reg [15:0] acc;                 // 16位累加器，防止8位×8位乘法结果溢出
    reg [7:0] temp_product;         // 临时乘积存储（实际未使用，可优化删除）

    //==================== 矩阵元素预提取 ====================
    // 为了便于索引访问，将200位的扁平矩阵解析为二维wire数组
    // 这是组合逻辑，不消耗时钟周期，只是方便后续访问

    // 预计算所有可能的A矩阵元素 A[row][col]
    wire [7:0] A_elem [0:4][0:4];   // 5×5的8位元素数组
    // 第0行元素
    assign A_elem[0][0] = mat_A[7:0];     // A[0][0] = mat_A[7:0]
    assign A_elem[0][1] = mat_A[15:8];    // A[0][1] = mat_A[15:8]
    assign A_elem[0][2] = mat_A[23:16];   // A[0][2] = mat_A[23:16]
    assign A_elem[0][3] = mat_A[31:24];   // A[0][3] = mat_A[31:24]
    assign A_elem[0][4] = mat_A[39:32];   // A[0][4] = mat_A[39:32]
    // 第1行元素
    assign A_elem[1][0] = mat_A[47:40];   // A[1][0]
    assign A_elem[1][1] = mat_A[55:48];   // A[1][1]
    assign A_elem[1][2] = mat_A[63:56];   // A[1][2]
    assign A_elem[1][3] = mat_A[71:64];   // A[1][3]
    assign A_elem[1][4] = mat_A[79:72];   // A[1][4]
    // 第2行元素
    assign A_elem[2][0] = mat_A[87:80];   // A[2][0]
    assign A_elem[2][1] = mat_A[95:88];   // A[2][1]
    assign A_elem[2][2] = mat_A[103:96];  // A[2][2]
    assign A_elem[2][3] = mat_A[111:104]; // A[2][3]
    assign A_elem[2][4] = mat_A[119:112]; // A[2][4]
    // 第3行元素
    assign A_elem[3][0] = mat_A[127:120]; // A[3][0]
    assign A_elem[3][1] = mat_A[135:128]; // A[3][1]
    assign A_elem[3][2] = mat_A[143:136]; // A[3][2]
    assign A_elem[3][3] = mat_A[151:144]; // A[3][3]
    assign A_elem[3][4] = mat_A[159:152]; // A[3][4]
    // 第4行元素
    assign A_elem[4][0] = mat_A[167:160]; // A[4][0]
    assign A_elem[4][1] = mat_A[175:168]; // A[4][1]
    assign A_elem[4][2] = mat_A[183:176]; // A[4][2]
    assign A_elem[4][3] = mat_A[191:184]; // A[4][3]
    assign A_elem[4][4] = mat_A[199:192]; // A[4][4]

    // 预计算所有可能的B矩阵元素 B[row][col]
    wire [7:0] B_elem [0:4][0:4];   // 5×5的8位元素数组
    // 第0行元素
    assign B_elem[0][0] = mat_B[7:0];     // B[0][0]
    assign B_elem[0][1] = mat_B[15:8];    // B[0][1]
    assign B_elem[0][2] = mat_B[23:16];   // B[0][2]
    assign B_elem[0][3] = mat_B[31:24];   // B[0][3]
    assign B_elem[0][4] = mat_B[39:32];   // B[0][4]
    // 第1行元素
    assign B_elem[1][0] = mat_B[47:40];   // B[1][0]
    assign B_elem[1][1] = mat_B[55:48];   // B[1][1]
    assign B_elem[1][2] = mat_B[63:56];   // B[1][2]
    assign B_elem[1][3] = mat_B[71:64];   // B[1][3]
    assign B_elem[1][4] = mat_B[79:72];   // B[1][4]
    // 第2行元素
    assign B_elem[2][0] = mat_B[87:80];   // B[2][0]
    assign B_elem[2][1] = mat_B[95:88];   // B[2][1]
    assign B_elem[2][2] = mat_B[103:96];  // B[2][2]
    assign B_elem[2][3] = mat_B[111:104]; // B[2][3]
    assign B_elem[2][4] = mat_B[119:112]; // B[2][4]
    // 第3行元素
    assign B_elem[3][0] = mat_B[127:120]; // B[3][0]
    assign B_elem[3][1] = mat_B[135:128]; // B[3][1]
    assign B_elem[3][2] = mat_B[143:136]; // B[3][2]
    assign B_elem[3][3] = mat_B[151:144]; // B[3][3]
    assign B_elem[3][4] = mat_B[159:152]; // B[3][4]
    // 第4行元素
    assign B_elem[4][0] = mat_B[167:160]; // B[4][0]
    assign B_elem[4][1] = mat_B[175:168]; // B[4][1]
    assign B_elem[4][2] = mat_B[183:176]; // B[4][2]
    assign B_elem[4][3] = mat_B[191:184]; // B[4][3]
    assign B_elem[4][4] = mat_B[199:192]; // B[4][4]

    //==================== 当前选择的元素和乘积 ====================
    reg [7:0] curr_a, curr_b;       // 当前选中的A和B元素，用于乘法计算
    wire [15:0] curr_product;       // 当前乘积结果（组合逻辑）
    assign curr_product = curr_a * curr_b;  // 8位×8位 = 16位乘法

    //==================== 主状态机：时序逻辑 ====================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            //---------- 异步复位：初始化所有寄存器 ----------
            state <= IDLE;              // 状态机回到空闲状态
            done <= 1'b0;               // 清除完成标志
            error <= 1'b0;              // 清除错误标志
            i <= 3'd0;                  // 行索引清零
            j <= 3'd0;                  // 列索引清零
            k <= 3'd0;                  // 累加索引清零
            acc <= 16'd0;               // 累加器清零
            mat_C <= 200'd0;            // 结果矩阵清零
            result_rows <= 3'd0;        // 结果行数清零
            result_cols <= 3'd0;        // 结果列数清零
            curr_a <= 8'd0;             // 当前A元素清零
            curr_b <= 8'd0;             // 当前B元素清零
        end else begin
            case (state)
                //========== IDLE状态：等待开始信号 ==========
                IDLE: begin
                    done <= 1'b0;           // 清除上一次的完成标志
                    error <= 1'b0;          // 清除上一次的错误标志
                    if (start) begin        // 检测到start信号
                        state <= CHECK;     // 转移到检查状态
                    end
                end

                //========== CHECK状态：验证输入维度 ==========
                CHECK: begin
                    // 检查所有维度是否在有效范围内（1到5）
                    // 注意：这里没有检查 cols_A == rows_B，假设调用者保证这一点
                    if (rows_A >= 3'd1 && rows_A <= 3'd5 &&
                        cols_A >= 3'd1 && cols_A <= 3'd5 &&
                        cols_B >= 3'd1 && cols_B <= 3'd5) begin
                        // 维度有效，准备开始计算
                        state <= CALC;          // 转移到计算状态
                        i <= 3'd0;              // 初始化行索引（结果矩阵的行）
                        j <= 3'd0;              // 初始化列索引（结果矩阵的列）
                        k <= 3'd0;              // 初始化累加索引
                        acc <= 16'd0;           // 清空累加器
                        mat_C <= 200'd0;        // 清空结果矩阵
                        result_rows <= rows_A;  // 结果行数 = A的行数
                        result_cols <= cols_B;  // 结果列数 = B的列数
                    end else begin
                        // 维度无效，报错
                        error <= 1'b1;          // 设置错误标志
                        state <= DONE;          // 直接跳到完成状态
                    end
                end

                //========== CALC状态：获取当前需要相乘的元素 ==========
                // 对于 C[i][j] = Σ A[i][k] * B[k][j]，需要获取 A[i][k] 和 B[k][j]
                CALC: begin
                    // 根据当前的i和k值选择A[i][k]
                    // 使用嵌套case语句实现二维索引访问
                    case (i)
                        3'd0: case (k)  // 当i=0时，选择A的第0行
                            3'd0: curr_a <= A_elem[0][0];  // A[0][0]
                            3'd1: curr_a <= A_elem[0][1];  // A[0][1]
                            3'd2: curr_a <= A_elem[0][2];  // A[0][2]
                            3'd3: curr_a <= A_elem[0][3];  // A[0][3]
                            3'd4: curr_a <= A_elem[0][4];  // A[0][4]
                            default: curr_a <= 8'd0;       // 默认值
                        endcase
                        3'd1: case (k)  // 当i=1时，选择A的第1行
                            3'd0: curr_a <= A_elem[1][0];
                            3'd1: curr_a <= A_elem[1][1];
                            3'd2: curr_a <= A_elem[1][2];
                            3'd3: curr_a <= A_elem[1][3];
                            3'd4: curr_a <= A_elem[1][4];
                            default: curr_a <= 8'd0;
                        endcase
                        3'd2: case (k)  // 当i=2时，选择A的第2行
                            3'd0: curr_a <= A_elem[2][0];
                            3'd1: curr_a <= A_elem[2][1];
                            3'd2: curr_a <= A_elem[2][2];
                            3'd3: curr_a <= A_elem[2][3];
                            3'd4: curr_a <= A_elem[2][4];
                            default: curr_a <= 8'd0;
                        endcase
                        3'd3: case (k)  // 当i=3时，选择A的第3行
                            3'd0: curr_a <= A_elem[3][0];
                            3'd1: curr_a <= A_elem[3][1];
                            3'd2: curr_a <= A_elem[3][2];
                            3'd3: curr_a <= A_elem[3][3];
                            3'd4: curr_a <= A_elem[3][4];
                            default: curr_a <= 8'd0;
                        endcase
                        3'd4: case (k)  // 当i=4时，选择A的第4行
                            3'd0: curr_a <= A_elem[4][0];
                            3'd1: curr_a <= A_elem[4][1];
                            3'd2: curr_a <= A_elem[4][2];
                            3'd3: curr_a <= A_elem[4][3];
                            3'd4: curr_a <= A_elem[4][4];
                            default: curr_a <= 8'd0;
                        endcase
                        default: curr_a <= 8'd0;  // 默认值
                    endcase

                    // 根据当前的k和j值选择B[k][j]
                    case (k)
                        3'd0: case (j)  // 当k=0时，选择B的第0行
                            3'd0: curr_b <= B_elem[0][0];  // B[0][0]
                            3'd1: curr_b <= B_elem[0][1];  // B[0][1]
                            3'd2: curr_b <= B_elem[0][2];  // B[0][2]
                            3'd3: curr_b <= B_elem[0][3];  // B[0][3]
                            3'd4: curr_b <= B_elem[0][4];  // B[0][4]
                            default: curr_b <= 8'd0;
                        endcase
                        3'd1: case (j)  // 当k=1时，选择B的第1行
                            3'd0: curr_b <= B_elem[1][0];
                            3'd1: curr_b <= B_elem[1][1];
                            3'd2: curr_b <= B_elem[1][2];
                            3'd3: curr_b <= B_elem[1][3];
                            3'd4: curr_b <= B_elem[1][4];
                            default: curr_b <= 8'd0;
                        endcase
                        3'd2: case (j)  // 当k=2时，选择B的第2行
                            3'd0: curr_b <= B_elem[2][0];
                            3'd1: curr_b <= B_elem[2][1];
                            3'd2: curr_b <= B_elem[2][2];
                            3'd3: curr_b <= B_elem[2][3];
                            3'd4: curr_b <= B_elem[2][4];
                            default: curr_b <= 8'd0;
                        endcase
                        3'd3: case (j)  // 当k=3时，选择B的第3行
                            3'd0: curr_b <= B_elem[3][0];
                            3'd1: curr_b <= B_elem[3][1];
                            3'd2: curr_b <= B_elem[3][2];
                            3'd3: curr_b <= B_elem[3][3];
                            3'd4: curr_b <= B_elem[3][4];
                            default: curr_b <= 8'd0;
                        endcase
                        3'd4: case (j)  // 当k=4时，选择B的第4行
                            3'd0: curr_b <= B_elem[4][0];
                            3'd1: curr_b <= B_elem[4][1];
                            3'd2: curr_b <= B_elem[4][2];
                            3'd3: curr_b <= B_elem[4][3];
                            3'd4: curr_b <= B_elem[4][4];
                            default: curr_b <= 8'd0;
                        endcase
                        default: curr_b <= 8'd0;  // 默认值
                    endcase

                    state <= SUM;  // 元素选择完毕，进入累加状态
                end

                //========== SUM状态：执行乘加运算 ==========
                SUM: begin
                    // 累加：acc = acc + A[i][k] * B[k][j]
                    // curr_product 是组合逻辑，在上一个时钟周期CALC状态设置完curr_a和curr_b后有效
                    acc <= acc + curr_product;

                    // 判断是否还需要继续累加（k是否遍历完cols_A）
                    if (k + 1'b1 < cols_A) begin
                        // 还有更多的k值需要累加
                        k <= k + 1'b1;      // k自增
                        state <= CALC;      // 返回CALC状态获取下一组元素
                    end else begin
                        // k遍历完毕，C[i][j]计算完成，准备存储
                        state <= STORE;
                    end
                end

                //========== STORE状态：存储计算结果 ==========
                STORE: begin
                    // 将累加结果存储到mat_C[i][j]
                    // 索引计算：线性地址 = (i * 5 + j) * 8
                    // 注意：只取acc的低8位，高位溢出被丢弃
                    case ({i, j})  // 将i和j拼接成6位索引
                        // 第0行结果
                        6'b000_000: mat_C[7:0]     <= acc[7:0];  // C[0][0]
                        6'b000_001: mat_C[15:8]    <= acc[7:0];  // C[0][1]
                        6'b000_010: mat_C[23:16]   <= acc[7:0];  // C[0][2]
                        6'b000_011: mat_C[31:24]   <= acc[7:0];  // C[0][3]
                        6'b000_100: mat_C[39:32]   <= acc[7:0];  // C[0][4]
                        // 第1行结果
                        6'b001_000: mat_C[47:40]   <= acc[7:0];  // C[1][0]
                        6'b001_001: mat_C[55:48]   <= acc[7:0];  // C[1][1]
                        6'b001_010: mat_C[63:56]   <= acc[7:0];  // C[1][2]
                        6'b001_011: mat_C[71:64]   <= acc[7:0];  // C[1][3]
                        6'b001_100: mat_C[79:72]   <= acc[7:0];  // C[1][4]
                        // 第2行结果
                        6'b010_000: mat_C[87:80]   <= acc[7:0];  // C[2][0]
                        6'b010_001: mat_C[95:88]   <= acc[7:0];  // C[2][1]
                        6'b010_010: mat_C[103:96]  <= acc[7:0];  // C[2][2]
                        6'b010_011: mat_C[111:104] <= acc[7:0];  // C[2][3]
                        6'b010_100: mat_C[119:112] <= acc[7:0];  // C[2][4]
                        // 第3行结果
                        6'b011_000: mat_C[127:120] <= acc[7:0];  // C[3][0]
                        6'b011_001: mat_C[135:128] <= acc[7:0];  // C[3][1]
                        6'b011_010: mat_C[143:136] <= acc[7:0];  // C[3][2]
                        6'b011_011: mat_C[151:144] <= acc[7:0];  // C[3][3]
                        6'b011_100: mat_C[159:152] <= acc[7:0];  // C[3][4]
                        // 第4行结果
                        6'b100_000: mat_C[167:160] <= acc[7:0];  // C[4][0]
                        6'b100_001: mat_C[175:168] <= acc[7:0];  // C[4][1]
                        6'b100_010: mat_C[183:176] <= acc[7:0];  // C[4][2]
                        6'b100_011: mat_C[191:184] <= acc[7:0];  // C[4][3]
                        6'b100_100: mat_C[199:192] <= acc[7:0];  // C[4][4]
                        default: ;  // 默认不操作
                    endcase

                    // 重置累加器和k索引，准备计算下一个C元素
                    acc <= 16'd0;       // 累加器清零
                    k <= 3'd0;          // k索引归零

                    // 移动到下一个输出元素位置
                    if (j + 1'b1 < cols_B) begin
                        // 当前行还有更多列需要计算
                        j <= j + 1'b1;      // 列索引加1
                        state <= CALC;      // 返回CALC状态
                    end else if (i + 1'b1 < rows_A) begin
                        // 当前行完成，移到下一行
                        j <= 3'd0;          // 列索引归零
                        i <= i + 1'b1;      // 行索引加1
                        state <= CALC;      // 返回CALC状态
                    end else begin
                        // 所有元素计算完成
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
