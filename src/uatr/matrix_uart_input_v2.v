`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_uart_input_v2
// Description: 增强版UART矩阵输入模块
// 输入格式: m n e11 e12 ... emn (用空格分隔)
// 支持200位输出（8位/元素）
// 元素值范围: 0-9（单个数字）或多位数字
//////////////////////////////////////////////////////////////////////////////////

module matrix_uart_input_v2(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [7:0] rx_data,
    input wire rx_done,
    output reg [2:0] matrix_m,          // 行数
    output reg [2:0] matrix_n,          // 列数
    output reg [199:0] matrix_data,     // 矩阵数据（25×8位）
    output reg matrix_ready,
    output reg [7:0] error_code
);

    // 状态定义
    localparam IDLE = 4'd0;
    localparam WAIT_M = 4'd1;
    localparam WAIT_SPACE1 = 4'd2;
    localparam READ_N = 4'd3;
    localparam WAIT_SPACE2 = 4'd4;
    localparam READ_ELEMENTS = 4'd5;
    localparam WAIT_NEXT = 4'd6;
    localparam READ_MULTI_DIGIT = 4'd7;
    localparam DONE = 4'd8;
    localparam ERROR = 4'd9;

    reg [3:0] state;
    reg [4:0] element_cnt;
    reg [4:0] expected_cnt;
    reg active;

    // 行列计数器 (稀疏存储)
    reg [2:0] cur_row;
    reg [2:0] cur_col;

    // 多位数字支持
    reg [7:0] current_value;
    reg parsing_number;

    // ASCII转数字
    function [3:0] ascii_to_num;
        input [7:0] ascii;
        begin
            if (ascii >= 8'd48 && ascii <= 8'd57)
                ascii_to_num = ascii - 8'd48;
            else
                ascii_to_num = 4'd15;
        end
    endfunction

    // 检查是否是数字
    function is_digit;
        input [7:0] ascii;
        begin
            is_digit = (ascii >= 8'd48 && ascii <= 8'd57);
        end
    endfunction

    // 检查是否是分隔符（空格、回车、换行）
    function is_separator;
        input [7:0] ascii;
        begin
            is_separator = (ascii == 8'd32 || ascii == 8'd13 || ascii == 8'd10);
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            matrix_m <= 0;
            matrix_n <= 0;
            matrix_ready <= 0;
            error_code <= 0;
            element_cnt <= 0;
            expected_cnt <= 0;
            active <= 0;
            matrix_data <= 200'd0;
            current_value <= 0;
            parsing_number <= 0;
            cur_row <= 0;
            cur_col <= 0;
        end else begin
            case (state)
                IDLE: begin
                    matrix_ready <= 0;
                    error_code <= 0;
                    element_cnt <= 0;
                    current_value <= 0;
                    parsing_number <= 0;
                    cur_row <= 0;
                    cur_col <= 0;

                    if (start && !active) begin
                        active <= 1;
                        matrix_data <= 200'd0;
                        state <= WAIT_M;
                    end else if (!start) begin
                        active <= 0;
                    end
                end

                WAIT_M: begin
                    if (rx_done) begin
                        if (rx_data >= 8'd49 && rx_data <= 8'd53) begin  // '1'-'5'
                            matrix_m <= ascii_to_num(rx_data);
                            state <= WAIT_SPACE1;
                        end else if (!is_separator(rx_data)) begin
                            error_code <= 8'd1;  // 行数无效
                            state <= ERROR;
                        end
                        // 忽略前导空格
                    end
                end

                WAIT_SPACE1: begin
                    if (rx_done) begin
                        if (rx_data == 8'd32) begin
                            state <= READ_N;
                        end else begin
                            error_code <= 8'd2;
                            state <= ERROR;
                        end
                    end
                end

                READ_N: begin
                    if (rx_done) begin
                        if (rx_data >= 8'd49 && rx_data <= 8'd53) begin  // '1'-'5'
                            matrix_n <= ascii_to_num(rx_data);
                            expected_cnt <= matrix_m * ascii_to_num(rx_data);
                            state <= WAIT_SPACE2;
                        end else begin
                            error_code <= 8'd3;
                            state <= ERROR;
                        end
                    end
                end

                WAIT_SPACE2: begin
                    if (rx_done) begin
                        if (rx_data == 8'd32) begin
                            state <= READ_ELEMENTS;
                            current_value <= 0;
                        end else begin
                            error_code <= 8'd4;
                            state <= ERROR;
                        end
                    end
                end

                READ_ELEMENTS: begin
                    if (rx_done) begin
                        if (is_digit(rx_data)) begin
                            // 累积数字值
                            current_value <= current_value * 10 + ascii_to_num(rx_data);
                            parsing_number <= 1;
                        end else if (is_separator(rx_data)) begin
                            if (parsing_number) begin
                                // 存储当前数字 - 修改为稀疏存储 (row*5 + col)
                                matrix_data[(cur_row * 5 + cur_col) * 8 +: 8] <= current_value;

                                // 更新行列计数
                                if (cur_col == matrix_n - 1) begin
                                    cur_col <= 0;
                                    cur_row <= cur_row + 1;
                                end else begin
                                    cur_col <= cur_col + 1;
                                end

                                element_cnt <= element_cnt + 1;
                                current_value <= 0;
                                parsing_number <= 0;

                                if (element_cnt + 1 >= expected_cnt) begin
                                    state <= DONE;
                                end else if (rx_data == 8'd13 || rx_data == 8'd10) begin
                                    // 回车/换行表示输入结束
                                    state <= DONE;
                                end
                            end
                            // 忽略连续的分隔符
                        end else begin
                            error_code <= 8'd6;
                            state <= ERROR;
                        end
                    end
                end

                DONE: begin
                    // 处理最后一个数字（如果没有分隔符结尾）
                    if (parsing_number && element_cnt < 25) begin
                        // 稀疏存储
                        matrix_data[(cur_row * 5 + cur_col) * 8 +: 8] <= current_value;
                    end
                    matrix_ready <= 1;
                    state <= IDLE;
                end

                ERROR: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
