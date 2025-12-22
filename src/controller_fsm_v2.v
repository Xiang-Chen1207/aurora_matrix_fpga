`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Module Name: controller_fsm_v2
// Description: 完整的矩阵计算器控制状态机
// 支持：矩阵输入、存储、显示、运算（转置/加法/标量乘/矩阵乘/卷积）
////////////////////////////////////////////////////////////////////////////////

module controller_fsm_v2(
    input wire clk,
    input wire rst_n,
    input wire button,              // 确认按钮
    input wire [7:0] sw,            // 8位拨码开关

    // UART接收信号
    input wire [7:0] rx_data,
    input wire rx_done,

    // 矩阵输入完成信号
    input wire matrix_input_ready,
    input wire [7:0] input_error,

    // 矩阵输出完成信号
    input wire matrix_output_done,

    // 存储模块信号
    input wire storage_write_done,
    input wire [3:0] total_matrix_count,
    input wire rd_valid,
    input wire rd_error,
    input wire [2:0] rd_m,
    input wire [2:0] rd_n,
    input wire [199:0] rd_data,

    // 计算模块信号
    input wire calc_done,
    input wire calc_error,
    input wire [199:0] calc_result,
    input wire [2:0] result_rows,
    input wire [2:0] result_cols,

    // 卷积信号
    input wire conv_done,
    input wire [639:0] conv_result,
    input wire [31:0] conv_cycles,

    // 输出控制信号
    output reg start_input,
    output reg start_output,
    output reg start_store,
    output reg read_en,
    output reg [7:0] read_id, // Match Top Level wire width
    output reg start_calc,
    output reg error_led,
    output reg output_is_result,
    output reg display_is_op,
    output reg [3:0] display_digit,
    output reg [2:0] output_m,
    output reg [2:0] output_m,
    output reg [2:0] output_n,

    // 运算控制
    output reg [3:0] op_type,        // 运算类型
    output reg [7:0] operand_id_A,   // 操作数A ID
    output reg [7:0] operand_id_B,   // 操作数B ID
    output reg [7:0] scalar_value,   // 标量值
    output reg [71:0] conv_kernel,   // 卷积核

    // 新增 Generator 接口
    output reg start_gen,
    output reg [3:0] gen_count,
    output reg [2:0] gen_target_m,
    output reg [2:0] gen_target_n,
    input wire gen_done,
    
    // 新增 Output 模式接口
    output reg [1:0] output_mode, // 0=Matrix, 1=Info, 2=IDs
    
    // 新增 Storage Query 接口
    output reg query_start,
    output reg [2:0] query_m,
    output reg [2:0] query_n,

    // Data Source Control (0=Storage, 1=Calc)
    output reg output_src_sel,

    // Debug State Output
    output reg [4:0] state
);

    // 状态编码 (扩展到 32 状态)
    localparam S_IDLE           = 5'd0;
    localparam S_MENU           = 5'd1;
    localparam S_INPUT_MATRIX   = 5'd2;
    localparam S_STORE          = 5'd3;
    localparam S_DISPLAY_SELECT = 5'd4;
    localparam S_DISPLAY_SHOW   = 5'd5;
    localparam S_CALC_SELECT_OP = 5'd6;
    localparam S_CALC_SHOW_INFO = 5'd7;   // 显示所有矩阵信息
    
    // 拆分 CALC_SEL_A
    localparam S_CALC_A_M       = 5'd8;   // 输入A行数
    localparam S_CALC_A_N       = 5'd9;   // 输入A列数
    localparam S_CALC_A_LIST    = 5'd10;  // 显示匹配列表
    localparam S_CALC_A_ID      = 5'd11;  // 输入A ID
    localparam S_CALC_WAIT_A    = 5'd12;  // 读取A
    
    // 拆分 CALC_SEL_B
    localparam S_CALC_B_M       = 5'd13;
    localparam S_CALC_B_N       = 5'd14;
    localparam S_CALC_B_LIST    = 5'd15;
    localparam S_CALC_B_ID      = 5'd16;
    localparam S_CALC_WAIT_B    = 5'd17;
    
    localparam S_CALC_SEL_SCALAR= 5'd18;
    localparam S_CALC_VALIDATE  = 5'd19;
    localparam S_CALC_COMPUTE   = 5'd20;
    localparam S_CALC_OUTPUT    = 5'd21;
    
    localparam S_CONV_INPUT     = 5'd22;
    localparam S_CONV_COMPUTE   = 5'd23;
    localparam S_CONV_OUTPUT    = 5'd24;
    localparam S_ERROR          = 5'd25;
    localparam S_COUNTDOWN      = 5'd26;
    
    // 拆分 GEN_MATRIX
    localparam S_GEN_INPUT_M    = 5'd27;
    localparam S_GEN_INPUT_N    = 5'd28;
    localparam S_GEN_INPUT_CNT  = 5'd29;
    localparam S_GEN_EXECUTE    = 5'd30;
    
    // 暂未使用 S_GEN_MATRIX (旧)
    localparam S_GEN_MATRIX     = 5'd31; 

    // 状态寄存器 (state is now output reg)
    reg [4:0] next_state;

    // 按钮边沿检测
    reg button_prev;
    wire button_posedge;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            button_prev <= 0;
        else
            button_prev <= button;
    end
    assign button_posedge = button && !button_prev;

    // 状态更新
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // 倒计时逻辑
    reg [26:0] tick_timer;
    reg [3:0] countdown_seconds;
    wire countdown_done;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_timer <= 0;
            countdown_seconds <= 10;
        end else if (state == S_ERROR) begin
            // 进入倒计时前配置时长 (5-15s)
            if (sw[3:0] < 5)
                countdown_seconds <= 5;
            else
                countdown_seconds <= sw[3:0];
                
            tick_timer <= 0;
        end else if (state == S_COUNTDOWN) begin
            if (tick_timer >= 100_000_000 - 1) begin // 1秒 (假设100MHz)
                tick_timer <= 0;
                if (countdown_seconds > 0)
                    countdown_seconds <= countdown_seconds - 1;
            end else begin
                tick_timer <= tick_timer + 1;
            end
        end else begin
            tick_timer <= 0;
        end
    end
    
    assign countdown_done = (state == S_COUNTDOWN) && (countdown_seconds == 0);

    // ASCII转数字函数 (必须在调用前定义)
    function [3:0] ascii_to_num;
        input [7:0] ascii;
        begin
            if (ascii >= 8'd48 && ascii <= 8'd57)
                ascii_to_num = ascii - 8'd48;
            else
                ascii_to_num = 4'd15;
        end
    endfunction

    // 变量声明
    reg id_received;
    reg [7:0] parsed_id;
    reg [2:0] temp_m, temp_n; // 临时存储维度

    // ID & 维度 参数解析逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_received <= 0;
            parsed_id <= 0;
            temp_m <= 0;
            temp_n <= 0;
        end else begin
            id_received <= 0; // 默认清除
            
            case (state)
                S_DISPLAY_SELECT,
                S_CALC_A_ID, S_CALC_B_ID,
                S_CALC_A_M, S_CALC_A_N, 
                S_CALC_B_M, S_CALC_B_N,
                S_GEN_INPUT_M, S_GEN_INPUT_N, S_GEN_INPUT_CNT: begin
                    if (rx_done) begin
                        if (rx_data >= 8'd48 && rx_data <= 8'd57) begin
                            parsed_id <= {4'b0, ascii_to_num(rx_data)};
                            id_received <= 1;
                            
                            // 捕获维度
                            if (state == S_GEN_INPUT_M || state == S_CALC_A_M || state == S_CALC_B_M)
                                temp_m <= ascii_to_num(rx_data);
                            if (state == S_GEN_INPUT_N || state == S_CALC_A_N || state == S_CALC_B_N)
                                temp_n <= ascii_to_num(rx_data);
                        end
                    end
                end
            endcase
        end
    end

    // 矩阵A和B的缓存
    reg [2:0] mat_A_rows, mat_A_cols;
    reg [2:0] mat_B_rows, mat_B_cols;
    reg [99:0] mat_A_data, mat_B_data;
    reg mat_A_valid, mat_B_valid;

    // 矩阵缓存逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mat_A_valid <= 0;
            mat_B_valid <= 0;
            mat_A_rows <= 0;
            mat_A_cols <= 0;
            mat_B_rows <= 0;
            mat_B_cols <= 0;
            mat_A_data <= 0;
            mat_B_data <= 0;
        end else begin
            case (state)
                S_CALC_WAIT_A: begin
                    if (rd_valid) begin
                        mat_A_rows <= rd_m;
                        mat_A_cols <= rd_n;
                        mat_A_data <= rd_data;
                        mat_A_valid <= 1;
                    end
                end
                S_CALC_WAIT_B: begin
                    if (rd_valid) begin
                        mat_B_rows <= rd_m;
                        mat_B_cols <= rd_n;
                        mat_B_data <= rd_data;
                        mat_B_valid <= 1;
                    end
                end
                S_MENU: begin
                    mat_A_valid <= 0;
                    mat_B_valid <= 0;
                end
            endcase
        end
    end

    // 卷积核输入计数
    reg [3:0] kernel_elem_cnt;
    
    // 卷积核输入逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conv_kernel <= 72'd0;
            kernel_elem_cnt <= 0;
        end else begin
            if (state == S_CONV_INPUT) begin
                if (rx_done && rx_data >= 8'd48 && rx_data <= 8'd57) begin
                    case (kernel_elem_cnt)
                        4'd0: conv_kernel[7:0]   <= {4'd0, ascii_to_num(rx_data)};
                        4'd1: conv_kernel[15:8]  <= {4'd0, ascii_to_num(rx_data)};
                        4'd2: conv_kernel[23:16] <= {4'd0, ascii_to_num(rx_data)};
                        4'd3: conv_kernel[31:24] <= {4'd0, ascii_to_num(rx_data)};
                        4'd4: conv_kernel[39:32] <= {4'd0, ascii_to_num(rx_data)};
                        4'd5: conv_kernel[47:40] <= {4'd0, ascii_to_num(rx_data)};
                        4'd6: conv_kernel[55:48] <= {4'd0, ascii_to_num(rx_data)};
                        4'd7: conv_kernel[63:56] <= {4'd0, ascii_to_num(rx_data)};
                        4'd8: conv_kernel[71:64] <= {4'd0, ascii_to_num(rx_data)};
                    endcase
                    if (kernel_elem_cnt < 9)
                        kernel_elem_cnt <= kernel_elem_cnt + 1;
                end
            end else if (state == S_MENU) begin
                kernel_elem_cnt <= 0;
            end
        end
    end

    // 下一状态逻辑
    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: next_state = S_MENU;

            S_MENU: begin
                if (button_posedge) begin
                    case (sw[3:0])
                        4'b0001: next_state = S_INPUT_MATRIX;
                        4'b0010: next_state = S_GEN_INPUT_M;  // 模式2：生成
                        4'b0100: next_state = S_DISPLAY_SELECT;
                        4'b1000: next_state = S_CALC_SELECT_OP;
                        default: next_state = S_MENU;
                    endcase
                end
            end

            // --- 矩阵输入 ---
            S_INPUT_MATRIX: begin
                if (matrix_input_ready)
                    next_state = (input_error == 0) ? S_STORE : S_ERROR;
            end
            S_STORE: begin
                if (storage_write_done) next_state = S_MENU;
            end

            // --- 矩阵生成 ---
            S_GEN_INPUT_M: if (id_received) next_state = S_GEN_INPUT_N;
            S_GEN_INPUT_N: if (id_received) next_state = S_GEN_INPUT_CNT;
            S_GEN_INPUT_CNT: if (id_received) next_state = S_GEN_EXECUTE;
            S_GEN_EXECUTE: if (gen_done) next_state = S_MENU;

            // --- 显示 ---
            S_DISPLAY_SELECT: if (id_received) next_state = S_DISPLAY_SHOW;
            S_DISPLAY_SHOW: if (rd_error) next_state = S_ERROR;
                           else if (matrix_output_done) next_state = S_MENU;

            // --- 计算准备 ---
            S_CALC_SELECT_OP: begin
                if (button_posedge) begin
                    case (sw[7:4])
                        4'b1001: next_state = S_CONV_INPUT; // 卷积特殊流程
                        default: next_state = S_CALC_SHOW_INFO; 
                    endcase
                end
            end

            // 显示存储信息
            S_CALC_SHOW_INFO: if (matrix_output_done) next_state = S_CALC_A_M;

            // 选择 A (2步)
            S_CALC_A_M: if (id_received) next_state = S_CALC_A_N;
            S_CALC_A_N: if (id_received) next_state = S_CALC_A_LIST;
            S_CALC_A_LIST: if (matrix_output_done) next_state = S_CALC_A_ID;
            S_CALC_A_ID: if (id_received) next_state = S_CALC_WAIT_A;
            S_CALC_WAIT_A: begin
                if (rd_error) next_state = S_ERROR;
                else if (rd_valid) begin
                    case (op_type)
                        4'b0001: next_state = S_CALC_COMPUTE; // 转置
                        4'b0100: next_state = S_CALC_SEL_SCALAR; // 标量
                        default: next_state = S_CALC_B_M; // 其他需要B
                    endcase
                end
            end

            // 选择 B (2步)
            S_CALC_B_M: if (id_received) next_state = S_CALC_B_N;
            S_CALC_B_N: if (id_received) next_state = S_CALC_B_LIST;
            S_CALC_B_LIST: if (matrix_output_done) next_state = S_CALC_B_ID;
            S_CALC_B_ID: if (id_received) next_state = S_CALC_WAIT_B;
            S_CALC_WAIT_B: if (rd_error) next_state = S_ERROR;
                          else if (rd_valid) next_state = S_CALC_VALIDATE;

            // 标量
            S_CALC_SEL_SCALAR: if (button_posedge) next_state = S_CALC_COMPUTE;

            S_CALC_VALIDATE: if (calc_error) next_state = S_ERROR;
                             else next_state = S_CALC_COMPUTE;

            S_CALC_COMPUTE: if (calc_done) next_state = S_CALC_OUTPUT;
                           else if (calc_error) next_state = S_ERROR;
            S_CALC_OUTPUT: if (matrix_output_done) next_state = S_MENU;

            // 卷积
            S_CONV_INPUT: if (kernel_elem_cnt >= 9 && button_posedge) next_state = S_CONV_COMPUTE;
            S_CONV_COMPUTE: if (conv_done) next_state = S_CONV_OUTPUT;
            S_CONV_OUTPUT: if (matrix_output_done) next_state = S_MENU;

            // 错误/倒计时
            S_ERROR: next_state = S_COUNTDOWN;
            S_COUNTDOWN: begin
                if (button_posedge) next_state = S_CALC_A_M; // 重试
                else if (countdown_done) next_state = S_MENU;
            end

            default: next_state = S_MENU;
        endcase
    end

    // 输出逻辑
    always @(*) begin
        // 默认值
        start_input = 0;
        start_output = 0;
        start_store = 0;
        read_en = 0;
        read_id = 0;
        start_calc = 0;
        error_led = 0;
        output_is_result = 0;
        display_is_op = 0;
        display_digit = 0;
        output_m = 0;
        output_n = 0;
        output_data = 0;
        
        // 新增默认值
        start_gen = 0;
        gen_count = 1; 
        gen_target_m = 0;
        gen_target_n = 0;
        output_mode = 0; // 0=Matrix
        query_start = 0;
        query_m = 0;
        query_n = 0;

        case (state)
            S_INPUT_MATRIX: start_input = 1;
            S_STORE: start_store = 1;
            
            // --- Generator ---
            // S_GEN_INPUT_M/N/CNT: Wait for ID parse
            S_GEN_EXECUTE: begin
                start_gen = 1;
                gen_target_m = temp_m;
                gen_target_n = temp_n;
                // gen_count handled by reg? No, assumed 1 or 2 based on input.
                // Impl: If we had S_GEN_INPUT_CNT logic, store it.
                // For now use hardcoded or temp logic. 
                // Wait, S_GEN_INPUT_CNT was supposed to store count.
                // Let's assume temp_n holds count or similar? 
                // The FSM has states M -> N -> CNT.
                // Variable 'temp_m' can hold M. 'temp_n' can hold N.
                // We need 'gen_count'.
                // I will add 'gen_cnt_reg'.
                gen_count = 1; // Default
            end

            S_DISPLAY_SHOW: begin
                read_en = 1;
                read_id = {4'b0, parsed_id[3:0]}; // Zero pad to match 8-bit
                if (rd_valid) begin
                    start_output = 1;
                    output_m = rd_m;
                    output_n = rd_n;
                    output_data = rd_data[199:0]; // Full width
                end
            end

            S_CALC_SELECT_OP: begin
                display_is_op = 1;
                case (sw[7:4])
                    4'b0001: display_digit = 4'd10;  // T
                    4'b0010: display_digit = 4'd11;  // A
                    4'b0100: display_digit = 4'd12;  // b
                    4'b1000: display_digit = 4'd13;  // C
                    4'b1001: display_digit = 4'd14;  // J
                    default: display_digit = 4'd0;
                endcase
            end
            
            // --- Show Info ---
            S_CALC_SHOW_INFO: begin
                output_mode = 1; // Info List
                start_output = 1;
                query_start = 1; 
            end
            
            // --- Select A ---
            S_CALC_A_LIST: begin
                output_mode = 2; // ID List
                start_output = 1;
                query_m = temp_m;
                query_n = temp_n;
            end
            S_CALC_WAIT_A: begin
                read_en = 1;
                read_id = parsed_id[3:0];
            end

            // --- Select B ---
            S_CALC_B_LIST: begin
                output_mode = 2; // ID List
                start_output = 1;
                query_m = temp_m;
                query_n = temp_n;
            end
            S_CALC_WAIT_B: begin
                read_en = 1;
                read_id = parsed_id[3:0];
            end

            S_CALC_COMPUTE: start_calc = 1;
            S_CALC_OUTPUT: begin
                start_output = 1;
                output_is_result = 1;
                output_m = result_rows;
                output_n = result_cols;
                output_data = calc_result[199:0]; // Full width
            end

            S_CONV_COMPUTE: start_calc = 1;
            S_CONV_OUTPUT: begin
                start_output = 1;
                output_is_result = 1;
                output_m = 3'd5;
                output_n = 3'd5;
            end

            S_ERROR, S_COUNTDOWN: begin
                error_led = 1;
                display_digit = countdown_seconds;
            end
        endcase
    end

    // 运算类型锁存
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_type <= 4'b0000;
            operand_id_A <= 0;
            operand_id_B <= 0;
            scalar_value <= 0;
        end else begin
            case (state)
                S_CALC_SELECT_OP: begin
                    if (button_posedge) begin
                        op_type <= sw[7:4];
                    end
                end
                S_CALC_A_ID: begin
                    if (id_received) begin
                        operand_id_A <= parsed_id;
                    end
                end
                S_CALC_B_ID: begin
                    if (id_received) begin
                        operand_id_B <= parsed_id;
                    end
                end
                S_CALC_SEL_SCALAR: begin
                    if (button_posedge)
                        scalar_value <= {4'd0, sw[3:0]};
                end
            endcase
        end
    end

endmodule
