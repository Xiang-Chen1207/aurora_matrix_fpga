`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_uart_input_v2 (4-bit style parser, 8-bit output)
// Description: 简化版 UART 矩阵输入，仅接受单字符数字 0~9，与旧4bit设计一致，
//              但总线保持 8bit/元素（200bit）以兼容现有存储/计算/输出链路。
// 输入格式: m n e11 e12 ... emn （空格/回车/换行分隔，m,n ∈ [1,5]）
//////////////////////////////////////////////////////////////////////////////////

module matrix_uart_input_v2(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] rx_data,
    input  wire       rx_done,
    output reg  [2:0] matrix_m,
    output reg  [2:0] matrix_n,
    output reg  [199:0] matrix_data,   // 25 * 8bit, zero-extended from 4bit digit
    output reg        matrix_ready,
    output reg  [7:0] error_code
);

    // 状态定义
    localparam IDLE        = 4'd0;
    localparam WAIT_M      = 4'd1;
    localparam WAIT_SPACE1 = 4'd2;
    localparam READ_N      = 4'd3;
    localparam WAIT_SPACE2 = 4'd4;
    localparam READ_ELEMS  = 4'd5;
    localparam WAIT_NEXT   = 4'd6;
    localparam DONE        = 4'd7;
    localparam ERROR       = 4'd8;
    localparam SKIP_EXTRA  = 4'd9;   // 忽略多余元素（读数字）
    localparam SKIP_WAIT   = 4'd10;  // 忽略完元素后等待空格/换行
    localparam WAIT_FINAL  = 4'd11;  // 元素满后等待最终判断（带超时）

    reg [3:0] state;
    reg [4:0] element_cnt;
    reg [4:0] expected_cnt;
    reg       active;
    reg [2:0] cur_row, cur_col;
    reg [15:0] timeout_cnt;  // 超时计数器，检测元素满后是否有紧跟字符

    // ASCII 转 4bit 数字
    function [3:0] ascii_to_num;
        input [7:0] ascii;
        begin
            if (ascii >= 8'd48 && ascii <= 8'd57)
                ascii_to_num = ascii - 8'd48;
            else
                ascii_to_num = 4'd15;
        end
    endfunction

    // 分隔符判定（空格/CR/LF）
    function is_sep;
        input [7:0] ascii;
        begin
            is_sep = (ascii == 8'd32 || ascii == 8'd13 || ascii == 8'd10);
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
            cur_row <= 0;
            cur_col <= 0;
            timeout_cnt <= 0;
        end else begin
            case (state)
                IDLE: begin
                    matrix_ready <= 0;
                    error_code <= 0;
                    element_cnt <= 0;
                    cur_row <= 0;
                    cur_col <= 0;
                    // 只有在新一轮 start 边沿时才清空数据
                    if (start && !active) begin
                        matrix_data <= 200'd0;
                    end

                    if (start && !active) begin
                        active <= 1;
                        state <= WAIT_M;
                    end else if (!start) begin
                        active <= 0;
                    end
                end

                WAIT_M: begin
                    if (rx_done) begin
                        if (rx_data >= 8'd49 && rx_data <= 8'd53) begin // '1'~'5'
                            matrix_m <= ascii_to_num(rx_data);
                            state <= WAIT_SPACE1;
                        end else if (!is_sep(rx_data)) begin
                            error_code <= 8'd1;
                            state <= ERROR;
                        end
                        // 分隔符/空白直接忽略
                    end
                end

                WAIT_SPACE1: begin
                    if (rx_done) begin
                        if (is_sep(rx_data)) begin
                            state <= READ_N;
                        end else begin
                            error_code <= 8'd2;
                            state <= ERROR;
                        end
                    end
                end

                READ_N: begin
                    if (rx_done) begin
                        if (rx_data >= 8'd49 && rx_data <= 8'd53) begin // '1'~'5'
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
                        if (is_sep(rx_data)) begin
                            state <= READ_ELEMS;
                        end else begin
                            error_code <= 8'd4;
                            state <= ERROR;
                        end
                    end
                end

                READ_ELEMS: begin
                    if (rx_done) begin
                        if (rx_data >= 8'd48 && rx_data <= 8'd57) begin // 单字符数字
                            matrix_data[(cur_row*5 + cur_col)*8 +: 8] <= {4'd0, ascii_to_num(rx_data)};
                            element_cnt <= element_cnt + 1;

                            // 更新行列
                            if (cur_col == matrix_n - 1) begin
                                cur_col <= 0;
                                cur_row <= cur_row + 1;
                            end else begin
                                cur_col <= cur_col + 1;
                            end

                            // 判断元素是否满足
                            if (element_cnt + 1 >= expected_cnt) begin
                                // 元素已满，进入WAIT_FINAL等待判断（带超时）
                                state <= WAIT_FINAL;
                                timeout_cnt <= 0;
                            end else begin
                                // 元素未满，继续等待下一个元素
                                state <= WAIT_NEXT;
                                timeout_cnt <= 0;  // 初始化超时计数器
                            end
                        end else if (rx_data == 8'd13 || rx_data == 8'd10) begin
                            state <= DONE; // 提前结束，缺省补零
                        end else begin
                            error_code <= 8'd6;
                            state <= ERROR;
                        end
                    end
                end

                WAIT_NEXT: begin
                    if (rx_done) begin
                        // 元素未满，正常处理
                        if (rx_data == 8'd32) begin
                            state <= READ_ELEMS;
                            timeout_cnt <= 0;
                        end else if (rx_data == 8'd13 || rx_data == 8'd10) begin
                            state <= DONE;  // 提前结束，缺省补零
                            timeout_cnt <= 0;
                        end else begin
                            error_code <= 8'd7;  // 格式错误
                            state <= ERROR;
                            timeout_cnt <= 0;
                        end
                    end else begin
                        // 超时检测：元素未满，等待下一个元素
                        if (timeout_cnt >= 16'd10000) begin  // 超时约100us
                            state <= DONE;  // 元素不足，自动补0
                        end else begin
                            timeout_cnt <= timeout_cnt + 1;
                        end
                    end
                end

                WAIT_FINAL: begin
                    // 元素已满后的最终判断（带超时）
                    if (rx_done) begin
                        // 有新字符到达
                        if (rx_data == 8'd13 || rx_data == 8'd10) begin
                            state <= DONE;  // 换行符，正常结束
                        end else if (rx_data == 8'd32) begin
                            state <= SKIP_EXTRA;  // 空格，后面还有元素要忽略
                        end else begin
                            // 其他字符（包括数字），说明是紧跟的非法字符（如'11'的第二个'1'）
                            error_code <= 8'd6;  // 元素值错误
                            state <= ERROR;
                        end
                        timeout_cnt <= 0;  // 重置超时计数器
                    end else begin
                        // 没有新字符，超时计数
                        if (timeout_cnt >= 16'd10000) begin  // 超时约100us（100MHz时钟）
                            // 超时，认为数据发送完毕，正常结束
                            state <= DONE;
                        end else begin
                            timeout_cnt <= timeout_cnt + 1;
                        end
                    end
                end

                SKIP_EXTRA: begin
                    // 忽略多余的元素（只读取，不存储）
                    if (rx_done) begin
                        if (rx_data >= 8'd48 && rx_data <= 8'd57) begin
                            // 读到数字，忽略它，进入SKIP_WAIT
                            state <= SKIP_WAIT;
                            timeout_cnt <= 0;
                        end else if (rx_data == 8'd13 || rx_data == 8'd10) begin
                            state <= DONE;  // 换行，结束
                            timeout_cnt <= 0;
                        end else if (rx_data == 8'd32) begin
                            // 连续空格，继续等待数字或换行
                            state <= SKIP_EXTRA;
                            timeout_cnt <= 0;
                        end else begin
                            error_code <= 8'd6;  // 非法字符
                            state <= ERROR;
                            timeout_cnt <= 0;
                        end
                    end else begin
                        // 超时检测：忽略模式中等待数字
                        if (timeout_cnt >= 16'd10000) begin  // 超时约100us
                            state <= DONE;  // 超时，正常结束（忽略完多余元素）
                        end else begin
                            timeout_cnt <= timeout_cnt + 1;
                        end
                    end
                end

                SKIP_WAIT: begin
                    // 忽略完一个元素后，等待空格或换行
                    if (rx_done) begin
                        if (rx_data == 8'd32) begin
                            state <= SKIP_EXTRA;  // 继续忽略下一个元素
                            timeout_cnt <= 0;
                        end else if (rx_data == 8'd13 || rx_data == 8'd10) begin
                            state <= DONE;  // 结束
                            timeout_cnt <= 0;
                        end else begin
                            // 非空格非换行，说明是多字符数字（如'11'），报错
                            error_code <= 8'd6;  // 元素值错误
                            state <= ERROR;
                            timeout_cnt <= 0;
                        end
                    end else begin
                        // 超时检测：等待空格或换行
                        if (timeout_cnt >= 16'd10000) begin  // 超时约100us
                            state <= DONE;  // 超时，正常结束
                        end else begin
                            timeout_cnt <= timeout_cnt + 1;
                        end
                    end
                end

                DONE: begin
                    // 不足元素自动补零已由 matrix_data 缺省完成
                    matrix_ready <= 1; // 单拍脉冲
                    state <= IDLE;
                end

                ERROR: begin
                    matrix_ready <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase

            // 保持 matrix_ready 直到 start 拉低（FSM 离开输入态后）
            if (!start) begin
                matrix_ready <= 0;
            end
        end
    end

endmodule
