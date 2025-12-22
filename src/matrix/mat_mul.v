`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 矩阵乘法模块
// 功能：实现两个矩阵的乘法运算 A(m×n) × B(n×p) = C(m×p)
// 要求：矩阵A的列数必须等于矩阵B的行数
// 计算：C[i][j] = Σ(A[i][k] * B[k][j]), k从0到n-1
// 输入矩阵按行优先展开：A[i][j] 存储在 mat_A[(i*5+j)*8 +: 8]
//////////////////////////////////////////////////////////////////////////////////
module mat_mul (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,       // 开始计算信号
    input  wire [2:0]  rows_A,      // 矩阵A行数 m (1-5)
    input  wire [2:0]  cols_A,      // 矩阵A列数 n (1-5)，也是B的行数
    input  wire [2:0]  cols_B,      // 矩阵B列数 p (1-5)
    input  wire [199:0] mat_A,      // 输入矩阵A (5×5×8bit = 200bit)
    input  wire [199:0] mat_B,      // 输入矩阵B
    output reg  [199:0] mat_C,      // 结果矩阵C = A × B
    output reg  [2:0]  result_rows, // 结果行数 = rows_A
    output reg  [2:0]  result_cols, // 结果列数 = cols_B
    output reg         done,        // 计算完成信号
    output reg         error        // 错误标志（维度不满足）
);

    // 状态定义
    localparam IDLE   = 3'd0;
    localparam CHECK  = 3'd1;
    localparam CALC   = 3'd2;
    localparam SUM    = 3'd3;
    localparam STORE  = 3'd4;
    localparam DONE   = 3'd5;

    reg [2:0] state;
    reg [2:0] i, j, k;      // 循环计数器
    reg [15:0] acc;         // 累加器（16位防止溢出）
    reg [7:0] temp_product; // 临时乘积

    // 获取矩阵A元素：A[row][col] = mat_A[(row*5+col)*8 +: 8]
    // 获取矩阵B元素：B[row][col] = mat_B[(row*5+col)*8 +: 8]

    // 预计算所有可能的A元素
    wire [7:0] A_elem [0:4][0:4];
    assign A_elem[0][0] = mat_A[7:0];     assign A_elem[0][1] = mat_A[15:8];    assign A_elem[0][2] = mat_A[23:16];   assign A_elem[0][3] = mat_A[31:24];   assign A_elem[0][4] = mat_A[39:32];
    assign A_elem[1][0] = mat_A[47:40];   assign A_elem[1][1] = mat_A[55:48];   assign A_elem[1][2] = mat_A[63:56];   assign A_elem[1][3] = mat_A[71:64];   assign A_elem[1][4] = mat_A[79:72];
    assign A_elem[2][0] = mat_A[87:80];   assign A_elem[2][1] = mat_A[95:88];   assign A_elem[2][2] = mat_A[103:96];  assign A_elem[2][3] = mat_A[111:104]; assign A_elem[2][4] = mat_A[119:112];
    assign A_elem[3][0] = mat_A[127:120]; assign A_elem[3][1] = mat_A[135:128]; assign A_elem[3][2] = mat_A[143:136]; assign A_elem[3][3] = mat_A[151:144]; assign A_elem[3][4] = mat_A[159:152];
    assign A_elem[4][0] = mat_A[167:160]; assign A_elem[4][1] = mat_A[175:168]; assign A_elem[4][2] = mat_A[183:176]; assign A_elem[4][3] = mat_A[191:184]; assign A_elem[4][4] = mat_A[199:192];

    // 预计算所有可能的B元素
    wire [7:0] B_elem [0:4][0:4];
    assign B_elem[0][0] = mat_B[7:0];     assign B_elem[0][1] = mat_B[15:8];    assign B_elem[0][2] = mat_B[23:16];   assign B_elem[0][3] = mat_B[31:24];   assign B_elem[0][4] = mat_B[39:32];
    assign B_elem[1][0] = mat_B[47:40];   assign B_elem[1][1] = mat_B[55:48];   assign B_elem[1][2] = mat_B[63:56];   assign B_elem[1][3] = mat_B[71:64];   assign B_elem[1][4] = mat_B[79:72];
    assign B_elem[2][0] = mat_B[87:80];   assign B_elem[2][1] = mat_B[95:88];   assign B_elem[2][2] = mat_B[103:96];  assign B_elem[2][3] = mat_B[111:104]; assign B_elem[2][4] = mat_B[119:112];
    assign B_elem[3][0] = mat_B[127:120]; assign B_elem[3][1] = mat_B[135:128]; assign B_elem[3][2] = mat_B[143:136]; assign B_elem[3][3] = mat_B[151:144]; assign B_elem[3][4] = mat_B[159:152];
    assign B_elem[4][0] = mat_B[167:160]; assign B_elem[4][1] = mat_B[175:168]; assign B_elem[4][2] = mat_B[183:176]; assign B_elem[4][3] = mat_B[191:184]; assign B_elem[4][4] = mat_B[199:192];

    // 当前选择的A和B元素
    reg [7:0] curr_a, curr_b;
    wire [15:0] curr_product;
    assign curr_product = curr_a * curr_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            error <= 1'b0;
            i <= 3'd0;
            j <= 3'd0;
            k <= 3'd0;
            acc <= 16'd0;
            mat_C <= 200'd0;
            result_rows <= 3'd0;
            result_cols <= 3'd0;
            curr_a <= 8'd0;
            curr_b <= 8'd0;
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
                    if (rows_A >= 3'd1 && rows_A <= 3'd5 &&
                        cols_A >= 3'd1 && cols_A <= 3'd5 &&
                        cols_B >= 3'd1 && cols_B <= 3'd5) begin
                        state <= CALC;
                        i <= 3'd0;
                        j <= 3'd0;
                        k <= 3'd0;
                        acc <= 16'd0;
                        mat_C <= 200'd0;
                        result_rows <= rows_A;
                        result_cols <= cols_B;
                    end else begin
                        error <= 1'b1;
                        state <= DONE;
                    end
                end

                CALC: begin
                    // 获取A[i][k]和B[k][j]
                    case (i)
                        3'd0: case (k)
                            3'd0: curr_a <= A_elem[0][0];
                            3'd1: curr_a <= A_elem[0][1];
                            3'd2: curr_a <= A_elem[0][2];
                            3'd3: curr_a <= A_elem[0][3];
                            3'd4: curr_a <= A_elem[0][4];
                            default: curr_a <= 8'd0;
                        endcase
                        3'd1: case (k)
                            3'd0: curr_a <= A_elem[1][0];
                            3'd1: curr_a <= A_elem[1][1];
                            3'd2: curr_a <= A_elem[1][2];
                            3'd3: curr_a <= A_elem[1][3];
                            3'd4: curr_a <= A_elem[1][4];
                            default: curr_a <= 8'd0;
                        endcase
                        3'd2: case (k)
                            3'd0: curr_a <= A_elem[2][0];
                            3'd1: curr_a <= A_elem[2][1];
                            3'd2: curr_a <= A_elem[2][2];
                            3'd3: curr_a <= A_elem[2][3];
                            3'd4: curr_a <= A_elem[2][4];
                            default: curr_a <= 8'd0;
                        endcase
                        3'd3: case (k)
                            3'd0: curr_a <= A_elem[3][0];
                            3'd1: curr_a <= A_elem[3][1];
                            3'd2: curr_a <= A_elem[3][2];
                            3'd3: curr_a <= A_elem[3][3];
                            3'd4: curr_a <= A_elem[3][4];
                            default: curr_a <= 8'd0;
                        endcase
                        3'd4: case (k)
                            3'd0: curr_a <= A_elem[4][0];
                            3'd1: curr_a <= A_elem[4][1];
                            3'd2: curr_a <= A_elem[4][2];
                            3'd3: curr_a <= A_elem[4][3];
                            3'd4: curr_a <= A_elem[4][4];
                            default: curr_a <= 8'd0;
                        endcase
                        default: curr_a <= 8'd0;
                    endcase

                    case (k)
                        3'd0: case (j)
                            3'd0: curr_b <= B_elem[0][0];
                            3'd1: curr_b <= B_elem[0][1];
                            3'd2: curr_b <= B_elem[0][2];
                            3'd3: curr_b <= B_elem[0][3];
                            3'd4: curr_b <= B_elem[0][4];
                            default: curr_b <= 8'd0;
                        endcase
                        3'd1: case (j)
                            3'd0: curr_b <= B_elem[1][0];
                            3'd1: curr_b <= B_elem[1][1];
                            3'd2: curr_b <= B_elem[1][2];
                            3'd3: curr_b <= B_elem[1][3];
                            3'd4: curr_b <= B_elem[1][4];
                            default: curr_b <= 8'd0;
                        endcase
                        3'd2: case (j)
                            3'd0: curr_b <= B_elem[2][0];
                            3'd1: curr_b <= B_elem[2][1];
                            3'd2: curr_b <= B_elem[2][2];
                            3'd3: curr_b <= B_elem[2][3];
                            3'd4: curr_b <= B_elem[2][4];
                            default: curr_b <= 8'd0;
                        endcase
                        3'd3: case (j)
                            3'd0: curr_b <= B_elem[3][0];
                            3'd1: curr_b <= B_elem[3][1];
                            3'd2: curr_b <= B_elem[3][2];
                            3'd3: curr_b <= B_elem[3][3];
                            3'd4: curr_b <= B_elem[3][4];
                            default: curr_b <= 8'd0;
                        endcase
                        3'd4: case (j)
                            3'd0: curr_b <= B_elem[4][0];
                            3'd1: curr_b <= B_elem[4][1];
                            3'd2: curr_b <= B_elem[4][2];
                            3'd3: curr_b <= B_elem[4][3];
                            3'd4: curr_b <= B_elem[4][4];
                            default: curr_b <= 8'd0;
                        endcase
                        default: curr_b <= 8'd0;
                    endcase

                    state <= SUM;
                end

                SUM: begin
                    // 累加 A[i][k] * B[k][j]
                    acc <= acc + curr_product;

                    if (k + 1'b1 < cols_A) begin
                        // 继续累加
                        k <= k + 1'b1;
                        state <= CALC;
                    end else begin
                        // 完成C[i][j]的计算，存储结果
                        state <= STORE;
                    end
                end

                STORE: begin
                    // 存储结果到mat_C[i][j]
                    // 索引 = (i * 5 + j) * 8
                    case ({i, j})
                        6'b000_000: mat_C[7:0]     <= acc[7:0];
                        6'b000_001: mat_C[15:8]    <= acc[7:0];
                        6'b000_010: mat_C[23:16]   <= acc[7:0];
                        6'b000_011: mat_C[31:24]   <= acc[7:0];
                        6'b000_100: mat_C[39:32]   <= acc[7:0];
                        6'b001_000: mat_C[47:40]   <= acc[7:0];
                        6'b001_001: mat_C[55:48]   <= acc[7:0];
                        6'b001_010: mat_C[63:56]   <= acc[7:0];
                        6'b001_011: mat_C[71:64]   <= acc[7:0];
                        6'b001_100: mat_C[79:72]   <= acc[7:0];
                        6'b010_000: mat_C[87:80]   <= acc[7:0];
                        6'b010_001: mat_C[95:88]   <= acc[7:0];
                        6'b010_010: mat_C[103:96]  <= acc[7:0];
                        6'b010_011: mat_C[111:104] <= acc[7:0];
                        6'b010_100: mat_C[119:112] <= acc[7:0];
                        6'b011_000: mat_C[127:120] <= acc[7:0];
                        6'b011_001: mat_C[135:128] <= acc[7:0];
                        6'b011_010: mat_C[143:136] <= acc[7:0];
                        6'b011_011: mat_C[151:144] <= acc[7:0];
                        6'b011_100: mat_C[159:152] <= acc[7:0];
                        6'b100_000: mat_C[167:160] <= acc[7:0];
                        6'b100_001: mat_C[175:168] <= acc[7:0];
                        6'b100_010: mat_C[183:176] <= acc[7:0];
                        6'b100_011: mat_C[191:184] <= acc[7:0];
                        6'b100_100: mat_C[199:192] <= acc[7:0];
                        default: ;
                    endcase

                    // 重置累加器
                    acc <= 16'd0;
                    k <= 3'd0;

                    // 移动到下一个元素
                    if (j + 1'b1 < cols_B) begin
                        j <= j + 1'b1;
                        state <= CALC;
                    end else if (i + 1'b1 < rows_A) begin
                        j <= 3'd0;
                        i <= i + 1'b1;
                        state <= CALC;
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
