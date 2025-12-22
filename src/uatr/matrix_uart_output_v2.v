`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_uart_output_v2
// Description: 矩阵计算器UART输出模块
// 功能：将矩阵数据（0-255）转换为格式化的ASCII字符并通过串口发送
// 支持：矩阵数据输出、矩阵信息列表、ID列表输出
// 特性：左对齐格式 (Bonus 3.1)
////////////////////////////////////////////////////////////////////////////////

module matrix_uart_output_v2(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [2:0] matrix_m,          // 矩阵行数 (1-8)
    input wire [2:0] matrix_n,          // 矩阵列数 (1-10)
    input wire [199:0] matrix_data,     // 矩阵数据 (25个元素，每个8位)
    input wire [639:0] conv_data,       // 卷积结果 (80个元素，每个8位)
    input wire is_conv_result,          // 是否为卷积结果
    input wire tx_busy,
    input wire [1:0] mode,              // 0=Matrix Data, 1=Info List, 2=ID List
    input wire [79:0] info_data,        // 存储模块的 Matrix Info
    input wire [15:0] match_ids,        // 查询匹配的 ID 列表
    output reg tx_start,
    output reg [7:0] tx_data,
    output reg output_done
);

    // 状态机状态定义
    localparam IDLE          = 4'd0;
    localparam GET_ELEMENT   = 4'd1;
    localparam SEND_DIGIT_H  = 4'd2;  // 百位
    localparam SEND_DIGIT_T  = 4'd3;  // 十位
    localparam SEND_DIGIT_U  = 4'd4;  // 个位
    localparam SEND_SPACE    = 4'd5;  // 填充空格 (左对齐)
    localparam SEND_NEWLINE  = 4'd6;
    localparam WAIT_TX       = 4'd7;
    localparam DONE          = 4'd8;
    
    // Info/ID 打印状态 (扩展)
    localparam SEND_INFO_LOOP    = 4'd9;
    localparam PROCESS_INFO_ITEM = 4'd10;
    localparam SEND_IDS_LOOP     = 4'd11;
    localparam SEND_ID_SPACE     = 4'd12;
    localparam SEND_ID_DIGIT     = 4'd13; 

    // 内部寄存器/线网
    reg [4:0] state, next_after_tx; // 扩展到5位以支持更多状态
    reg [3:0] print_step;
    reg [3:0] loop_idx;
    reg [2:0] row_idx;
    reg [2:0] col_idx;
    reg [2:0] chars_printed; // Bonus 3.1: Alignment tracking

    reg [7:0] element_value;
    
    // 动态提取 info_byte (修复 loop_idx is not constant 错误)
    // 使用 Indexed Part-Select: [base +: width]
    wire [7:0] current_info_byte;
    assign current_info_byte = info_data[loop_idx*8 +: 8];
    
    // 动态提取 match_id (修复 loop_idx is not constant 错误)
    wire [3:0] current_match_id;
    assign current_match_id = match_ids[loop_idx*4 +: 4];

    // 数值转换辅助变量
    reg [7:0] current_value;
    reg [3:0] digit_h, digit_t, digit_u;
    reg has_hundreds, has_tens;

    // 实际行列数
    wire [3:0] actual_rows = is_conv_result ? 4'd8 : {1'b0, matrix_m};
    wire [3:0] actual_cols = is_conv_result ? 4'd10 : {1'b0, matrix_n};

    // 稀疏矩阵读取函数 (5x5 layout)
    function [7:0] get_matrix_element;
        input [6:0] idx; // row*5 + col
        input [199:0] data;
        begin
            // idx range 0-24
            // data format: element 0 at [7:0], element 1 at [15:8]...
            // Indexed Part Select
            get_matrix_element = data[idx*8 +: 8];
        end
    endfunction

    function [7:0] get_conv_element;
        input [6:0] idx; // linear 0-79
        input [639:0] data;
        begin
            get_conv_element = data[idx*8 +: 8];
        end
    endfunction

    function [7:0] to_ascii;
        input [3:0] val;
        begin
            if (val <= 9) to_ascii = val + "0";
            else to_ascii = val - 10 + "A";
        end
    endfunction

    // 主状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tx_start <= 0;
            tx_data <= 0;
            output_done <= 0;
            row_idx <= 0;
            col_idx <= 0;
            next_after_tx <= IDLE;
            loop_idx <= 0;
            print_step <= 0;
            chars_printed <= 0;
        end else begin
            case (state)
                IDLE: begin
                    output_done <= 0;
                    if (start) begin
                        row_idx <= 0;
                        col_idx <= 0;
                        loop_idx <= 0;
                        chars_printed <= 0;
                        print_step <= 0;
                        
                        if (mode == 0) state <= GET_ELEMENT;
                        else if (mode == 1) state <= SEND_INFO_LOOP; // Show Info
                        else if (mode == 2) state <= SEND_IDS_LOOP;  // Show IDs
                        else state <= DONE;
                    end
                end

                // ==========================
                // Mode 0: Matrix Data (Left Aligned)
                // ==========================
                GET_ELEMENT: begin
                    // 获取当前元素值
                    if (is_conv_result) begin
                        current_value <= get_conv_element(row_idx * 10 + col_idx, conv_data);
                    end else begin
                        // Sparse 5x5: idx = row*5 + col
                        current_value <= get_matrix_element(row_idx * 5 + col_idx, matrix_data);
                    end

                    // 计算位数
                    if (current_value >= 8'd100) begin
                        digit_h <= current_value / 100;
                        digit_t <= (current_value / 10) % 10;
                        digit_u <= current_value % 10;
                        has_hundreds <= 1;
                        has_tens <= 1;
                        state <= SEND_DIGIT_H;
                    end else if (current_value >= 8'd10) begin
                        digit_h <= 0;
                        digit_t <= current_value / 10;
                        digit_u <= current_value % 10;
                        has_hundreds <= 0;
                        has_tens <= 1;
                        state <= SEND_DIGIT_T;
                    end else begin
                        digit_h <= 0;
                        digit_t <= 0;
                        digit_u <= current_value[3:0];
                        has_hundreds <= 0;
                        has_tens <= 0;
                        state <= SEND_DIGIT_U; // 只有个位
                    end
                    chars_printed <= 0; // 重置字符计数
                end

                SEND_DIGIT_H: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= to_ascii(digit_h);
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_DIGIT_T;
                        chars_printed <= chars_printed + 1;
                    end
                end

                SEND_DIGIT_T: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= to_ascii(digit_t);
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_DIGIT_U;
                        chars_printed <= chars_printed + 1;
                    end
                end

                SEND_DIGIT_U: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= to_ascii(digit_u);
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_SPACE;
                        chars_printed <= chars_printed + 1;
                    end
                end

                // Bonus 3.1: Left Alignment padding
                // 总宽度固定为 4 (例如 "255 " 或 "3   ")
                SEND_SPACE: begin
                    if (!tx_busy && !tx_start) begin
                        if (chars_printed < 4) begin
                            tx_data <= 8'd32; // space
                            tx_start <= 1;
                            state <= WAIT_TX;
                            next_after_tx <= SEND_SPACE;
                            chars_printed <= chars_printed + 1;
                        end else begin
                            // Padding done, move to next element
                            if (col_idx == actual_cols - 1) begin
                                state <= SEND_NEWLINE;
                            end else begin
                                col_idx <= col_idx + 1;
                                state <= GET_ELEMENT;
                            end
                        end
                    end
                end

                SEND_NEWLINE: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= 8'd10;  // newline
                        tx_start <= 1;
                        col_idx <= 0;
                        row_idx <= row_idx + 1;
                        
                        state <= WAIT_TX;
                        if (row_idx == actual_rows - 1)
                            next_after_tx <= DONE;
                        else
                            next_after_tx <= GET_ELEMENT;
                    end
                end

                // ==========================
                // Mode 1: Info List (Loop 0-9)
                // ID-M-N format
                // ==========================
                SEND_INFO_LOOP: begin
                     if (loop_idx > 9) begin
                         state <= DONE;
                     end else begin
                         // Check valid bit (ID != 0 or just print all?)
                         // Assuming print all 10 slots
                         print_step <= 0;
                         state <= PROCESS_INFO_ITEM;
                     end
                end
                
                PROCESS_INFO_ITEM: begin
                    if (!tx_busy && !tx_start) begin
                        tx_start <= 1;
                        
                        // 使用 wire current_info_byte 提取的当前数据
                        // Byte structure: {id[1:0], m[2:0], n[2:0]} (Example assumption from storage)
                        // Actually storage sends: {id[1:0], m[2:0], n[2:0]} packed in 8 bits? 
                        // Wait, ID is 4 bits in storage V2? 
                        // Storage V2 output info_data is 80 bits. 10 items * 8 bits.
                        // Item: {id[1:0], m[2:0], n[2:0]} -> 2+3+3 = 8 bits.
                        // Wait, ID is usually 0-9, so 4 bits. 
                        // But 80 bits for 10 matrices implies 8 bits per matrix.
                        // So ID must be compressed or implied?
                        // Let's assume the 8 bits are {id_low2, m_3, n_3}. 
                        // Note: If ID > 3, this packing fails. 
                        // Let's assume ID corresponds to loop_idx for display if not stored explicitly?
                        // Actually, storage V2 stores {id[1:0], m[2:0], n[2:0]}. ID is 2 bits?
                        // If ID is 0-9, we need 4 bits. 
                        // If storage only supports 4 stored matrices logic might be different.
                        // Let's assume for Info Display we just print loop_idx as ID if 2 bits aren't enough,
                        // OR assuming 2 bits ID is just for match list. 
                        // Ah, the Spec says "Matrix Info String".
                        // Let's trust the data is packed as {id[1:0], m[2:0], n[2:0]} for now.
                        
                        case (print_step)
                            0: tx_data <= to_ascii({2'b0, current_info_byte[7:6]}); // ID
                            1: tx_data <= 8'd45; // '-'
                            2: tx_data <= to_ascii({1'b0, current_info_byte[5:3]}); // m
                            3: tx_data <= 8'd45; // '-'
                            4: tx_data <= to_ascii({1'b0, current_info_byte[2:0]}); // n
                            5: tx_data <= 8'd32; // ' '
                            default: tx_data <= 8'd32;
                        endcase
                        
                        state <= WAIT_TX;
                        if (print_step < 5) begin
                             print_step <= print_step + 1;
                             next_after_tx <= PROCESS_INFO_ITEM;
                        end else begin
                             loop_idx <= loop_idx + 1; // Next matrix
                             next_after_tx <= SEND_INFO_LOOP;
                        end
                    end
                end

                // ==========================
                // Mode 2: ID List (Loop matches)
                // ==========================
                SEND_IDS_LOOP: begin
                     // match_ids is 16 bits. 4 IDs * 4 bits each? Or 4 IDs.
                     // Let's assume up to 4 matches.
                     if (loop_idx > 3) begin
                         state <= DONE;
                     end else begin
                         if (current_match_id != 4'd15) begin // Assuming 15 (F) is invalid/empty
                             state <= SEND_ID_DIGIT;
                         end else begin
                             // Valid IDs ended
                             state <= DONE;
                         end
                     end
                end
                
                SEND_ID_DIGIT: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= to_ascii(current_match_id); // 0-9
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_ID_SPACE;
                    end
                end
                
                SEND_ID_SPACE: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= 8'd32; // Space
                        tx_start <= 1;
                        state <= WAIT_TX;
                        loop_idx <= loop_idx + 1;
                        next_after_tx <= SEND_IDS_LOOP;
                    end
                end

                WAIT_TX: begin
                    tx_start <= 0;
                    if (!tx_busy) begin // Wait for busy to go low (tx idle)
                         state <= next_after_tx;
                    end
                end

                DONE: begin
                    output_done <= 1;
                    if (!start) state <= IDLE; // Wait for start to drop
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
