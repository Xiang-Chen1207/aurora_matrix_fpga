`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_uart_output_v2
// Description: ?????????UART??????
// ????????????????0-255?????????????ASCII???????????????
// ?????????????????????????��???ID?��????
// ???????????? (Bonus 3.1)
////////////////////////////////////////////////////////////////////////////////

module matrix_uart_output_v2(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [2:0] matrix_m,          // ???????? (1-8)
    input wire [2:0] matrix_n,          // ???????? (1-10)
    input wire [199:0] matrix_data,     // ???????? (25?????????8��)
    input wire [639:0] conv_data,       // ??????? (80?????????8��)
    input wire is_conv_result,          // ???????????
    input wire tx_busy,
    input wire [2:0] mode,              // 0=Matrix Data, 1=Info List, 2=ID List, 3=Summary, 4=ID+Matrix
    input wire [159:0] info_data,       // Matrix Info: 10 entries *16 bits {id[7:0], m[2:0], n[2:0], 2'b0}
    input wire [15:0] match_ids,        // ??????? ID ?��?
    input wire [3:0] total_count,
    input wire [99:0] summary_counts,   // 25 dims *4bit counts, idx=(m-1)*5+(n-1)
    input wire [7:0] matrix_id,
    output reg tx_start,
    output reg [7:0] tx_data,
    output reg output_done
);

    // ??????????
    localparam IDLE          = 4'd0;
    localparam GET_ELEMENT   = 4'd1;
    localparam SEND_DIGIT_H  = 4'd2;  // ??��
    localparam SEND_DIGIT_T  = 4'd3;  // ?��
    localparam SEND_DIGIT_U  = 4'd4;  // ??��
    localparam SEND_SPACE    = 4'd5;  // ????? (?????)
    localparam SEND_NEWLINE  = 4'd6;
    localparam WAIT_TX       = 4'd7;
    localparam DONE          = 4'd8;
    
    // Info/ID ????? (???)
    localparam SEND_INFO_LOOP    = 4'd9;
    localparam PROCESS_INFO_ITEM = 4'd10;
    localparam SEND_IDS_LOOP     = 4'd11;
    localparam SEND_ID_SPACE     = 4'd12;
    localparam SEND_ID_DIGIT     = 4'd13; 
    localparam SEND_SUMMARY_INIT   = 4'd14;
    localparam SEND_SUMMARY_DIM    = 4'd15;
    localparam SEND_SUMMARY_NEWLINE= 5'd16;
    localparam SEND_ID_FIRST       = 5'd17;
    localparam SEND_ID_SECOND      = 5'd18;
    localparam SEND_HDR_SPACE1     = 5'd19;
    localparam SEND_HDR_M          = 5'd20;
    localparam SEND_HDR_SPACE2     = 5'd21;
    localparam SEND_HDR_N          = 5'd22;
    localparam SEND_HDR_NEWLINE    = 5'd23;

    // ????????/????
    reg [4:0] state, next_after_tx; // ?????5��??????????
    reg [3:0] print_step;
    reg [3:0] loop_idx;
    reg [2:0] row_idx;
    reg [3:0] col_idx; // needs 0-9 for conv (10 cols)
    reg [2:0] chars_printed; // Bonus 3.1: Alignment tracking

    // Summary helpers
    reg [4:0] summary_idx; // 0..24 for 1..5 x 1..5
    reg [3:0] summary_count;

    reg [7:0] element_value;
    reg [3:0] id_tens;
    reg [3:0] id_ones;
    reg id_has_tens;
    
    // Current info word (16 bits per slot): {id[7:0], m[2:0], n[2:0], 2'b0}
    wire [15:0] current_info_word;
    assign current_info_word = info_data[loop_idx*16 +: 16];
    
    // ?????? match_id (??? loop_idx is not constant ????)
    wire [3:0] current_match_id;
    assign current_match_id = match_ids[loop_idx*4 +: 4];

    // Summary decoding helpers
    wire [3:0] total_tens = total_count / 10;
    wire [3:0] total_ones = total_count % 10;
    wire [3:0] summary_count_wire = summary_counts[summary_idx*4 +: 4];
    wire [2:0] summary_m = dim_m_from_idx(summary_idx);
    wire [2:0] summary_n = dim_n_from_idx(summary_idx);

    // 当前元素与拆分出的数字
    reg [7:0] current_value;
    reg [3:0] digit_h, digit_t, digit_u;
    reg has_hundreds, has_tens;

    // 取矩阵元素（稀疏 5x5）
    function [7:0] get_matrix_element;
        input [6:0] idx; // row*5 + col，范围0-24
        input [199:0] data;
        begin
            get_matrix_element = data[idx*8 +: 8];
        end
    endfunction

    // 取卷积结果元素
    function [7:0] get_conv_element;
        input [6:0] idx; // 线性 0-79
        input [639:0] data;
        begin
            get_conv_element = data[idx*8 +: 8];
        end
    endfunction

    // 将 summary_idx 映射到 m,n (1..5)
    function [2:0] dim_m_from_idx;
        input [4:0] idx;
        begin
            dim_m_from_idx = (idx / 5) + 1; // idx 0..24
        end
    endfunction

    function [2:0] dim_n_from_idx;
        input [4:0] idx;
        begin
            dim_n_from_idx = (idx % 5) + 1;
        end
    endfunction

    // 数值转 ASCII
    function [7:0] to_ascii;
        input [3:0] val;
        begin
            if (val <= 9) to_ascii = val + "0";
            else to_ascii = val - 10 + "A";
        end
    endfunction

    // 计算实际输出的行列（卷积固定 8x10，否则使用矩阵维度）
    wire [3:0] actual_rows = is_conv_result ? 4'd8  : {1'b0, matrix_m};
    wire [3:0] actual_cols = is_conv_result ? 4'd10 : {1'b0, matrix_n};

    // ?????? - ??? start ?????, ?? start ?????
    reg start_prev;
    wire start_pulse = start & ~start_prev; // ????????

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
            start_prev <= 0;
            summary_idx <= 0;
            summary_count <= 0;
            id_tens <= 0;
            id_ones <= 0;
            id_has_tens <= 0;
        end else begin
            // ???? start ?????
            start_prev <= start;

            case (state)
                IDLE: begin
                    output_done <= 0;
                    if (start_pulse) begin
                        row_idx <= 0;
                        col_idx <= 0;
                        loop_idx <= 0;
                        chars_printed <= 0;
                        print_step <= 0;
                        summary_idx <= 0;
                        summary_count <= 0;
                        
                        if (mode == 0) state <= GET_ELEMENT;
                        else if (mode == 1) state <= SEND_INFO_LOOP; // Show Info
                        else if (mode == 2) state <= SEND_IDS_LOOP;  // Show IDs
                        else if (mode == 3) state <= SEND_SUMMARY_INIT;
                        else if (mode == 4) begin
                            id_tens <= matrix_id / 10;
                            id_ones <= matrix_id % 10;
                            id_has_tens <= (matrix_id >= 8'd10);
                            state <= SEND_ID_FIRST;
                        end else state <= DONE;
                    end
                end

                // ==========================
                // Mode 4: ID header then Matrix Data
                // ==========================
                SEND_ID_FIRST: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= to_ascii(id_has_tens ? id_tens : id_ones);
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= id_has_tens ? SEND_ID_SECOND : SEND_HDR_SPACE1;
                    end
                end

                SEND_ID_SECOND: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= to_ascii(id_ones);
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_HDR_SPACE1;
                    end
                end

                SEND_HDR_SPACE1: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= 8'd32; // space
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_HDR_M;
                    end
                end

                SEND_HDR_M: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= to_ascii({1'b0, matrix_m});
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_HDR_SPACE2;
                    end
                end

                SEND_HDR_SPACE2: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= 8'd32; // space
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_HDR_N;
                    end
                end

                SEND_HDR_N: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= to_ascii({1'b0, matrix_n});
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= SEND_HDR_NEWLINE;
                    end
                end

                SEND_HDR_NEWLINE: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= 8'd10; // newline
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= GET_ELEMENT;
                    end
                end

                // ==========================
                // Mode 0: Matrix Data (Left Aligned)
                // ==========================
                GET_ELEMENT: begin
                    // 读取当前元素；用阻塞赋值，避免同周期使用旧值
                    if (is_conv_result) begin
                        current_value = get_conv_element(row_idx * 10 + col_idx, conv_data);
                    end else begin
                        // Sparse 5x5: idx = row*5 + col
                        current_value = get_matrix_element(row_idx * 5 + col_idx, matrix_data);
                    end

                    // 判断位数
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
                    chars_printed <= 0; // 重置本元素的字符计数
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
                // ???????? 4 (???? "255 " ?? "3   ")
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
                        state <= WAIT_TX;

                        // current_info_word: {id[15:8], m[7:5], n[4:2], 2'b0}
                        // Format: ID-M-N (ID without leading zero if <10)
                        // Derive decimal digits for ID
                        // Note: id_up_to_255; we print max 3 digits (hundreds handled in to_ascii)
                        case (print_step)
                            0: begin // first ID digit (hundreds or tens/ones)
                                if (current_info_word[15:8] >= 8'd100)
                                    tx_data <= to_ascii((current_info_word[15:8] / 100) % 10);
                                else if (current_info_word[15:8] >= 8'd10)
                                    tx_data <= to_ascii((current_info_word[15:8] / 10) % 10);
                                else
                                    tx_data <= to_ascii(current_info_word[15:8] % 10);
                                // Decide next step based on ID magnitude
                                if (current_info_word[15:8] >= 8'd100)
                                    print_step <= 1; // need tens next
                                else if (current_info_word[15:8] >= 8'd10)
                                    print_step <= 2; // ones next
                                else
                                    print_step <= 3; // go to dash
                                next_after_tx <= PROCESS_INFO_ITEM;
                            end

                            1: begin // second ID digit (tens when hundreds exist)
                                tx_data <= to_ascii((current_info_word[15:8] / 10) % 10);
                                print_step <= 2; // ones next
                                state <= WAIT_TX;
                                next_after_tx <= PROCESS_INFO_ITEM;
                            end

                            2: begin // third ID digit (ones)
                                tx_data <= to_ascii(current_info_word[15:8] % 10);
                                print_step <= 3; // proceed to dash
                                state <= WAIT_TX;
                                next_after_tx <= PROCESS_INFO_ITEM;
                            end

                            3: begin // '-'
                                tx_data <= 8'd45;
                                print_step <= 4;
                                state <= WAIT_TX;
                                next_after_tx <= PROCESS_INFO_ITEM;
                            end

                            4: begin // m
                                tx_data <= to_ascii({1'b0, current_info_word[7:5]});
                                print_step <= 5;
                                state <= WAIT_TX;
                                next_after_tx <= PROCESS_INFO_ITEM;
                            end

                            5: begin // '-'
                                tx_data <= 8'd45;
                                print_step <= 6;
                                state <= WAIT_TX;
                                next_after_tx <= PROCESS_INFO_ITEM;
                            end

                            6: begin // n
                                tx_data <= to_ascii({1'b0, current_info_word[4:2]});
                                print_step <= 7;
                                state <= WAIT_TX;
                                next_after_tx <= PROCESS_INFO_ITEM;
                            end

                            7: begin // trailing space
                                tx_data <= 8'd32;
                                state <= WAIT_TX;
                                next_after_tx <= SEND_INFO_LOOP;
                                print_step <= 0;
                                loop_idx <= loop_idx + 1; // Next matrix
                            end

                            default: begin
                                tx_data <= 8'd32;
                                print_step <= 0;
                                state <= WAIT_TX;
                                next_after_tx <= SEND_INFO_LOOP;
                                loop_idx <= loop_idx + 1;
                            end
                        endcase
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

                // ==========================
                // Mode 3: Summary (total_count + m*n*count ...)
                // ==========================
                SEND_SUMMARY_INIT: begin
                    if (!tx_busy && !tx_start) begin
                        if (print_step == 0) begin
                            if (total_tens != 0) begin
                                tx_data <= to_ascii(total_tens);
                                tx_start <= 1;
                                state <= WAIT_TX;
                                next_after_tx <= SEND_SUMMARY_INIT;
                                print_step <= 1;
                            end else begin
                                print_step <= 1; // skip leading zero
                            end
                        end else if (print_step == 1) begin
                            tx_data <= to_ascii(total_ones);
                            tx_start <= 1;
                            state <= WAIT_TX;
                            next_after_tx <= SEND_SUMMARY_INIT;
                            print_step <= 2;
                        end else if (print_step == 2) begin
                            tx_data <= 8'd32; // space
                            tx_start <= 1;
                            state <= WAIT_TX;
                            next_after_tx <= SEND_SUMMARY_DIM;
                            print_step <= 0;
                            summary_idx <= 0;
                        end
                    end
                end

                SEND_SUMMARY_DIM: begin
                    if (summary_idx > 5'd24) begin
                        state <= SEND_SUMMARY_NEWLINE;
                    end else if (summary_count_wire == 0) begin
                        summary_idx <= summary_idx + 1'b1; // skip zero count
                    end else if (!tx_busy && !tx_start) begin
                        case (print_step)
                            4'd0: begin tx_data <= to_ascii(summary_m); tx_start <= 1; state <= WAIT_TX; next_after_tx <= SEND_SUMMARY_DIM; print_step <= 1; end
                            4'd1: begin tx_data <= 8'd45; tx_start <= 1; state <= WAIT_TX; next_after_tx <= SEND_SUMMARY_DIM; print_step <= 2; end // '-'
                            4'd2: begin tx_data <= to_ascii(summary_n); tx_start <= 1; state <= WAIT_TX; next_after_tx <= SEND_SUMMARY_DIM; print_step <= 3; end
                            4'd3: begin tx_data <= 8'd45; tx_start <= 1; state <= WAIT_TX; next_after_tx <= SEND_SUMMARY_DIM; print_step <= 4; end // '-'
                            4'd4: begin tx_data <= to_ascii(summary_count_wire[3:0]); tx_start <= 1; state <= WAIT_TX; next_after_tx <= SEND_SUMMARY_DIM; print_step <= 5; end
                            4'd5: begin tx_data <= 8'd32; tx_start <= 1; state <= WAIT_TX; next_after_tx <= SEND_SUMMARY_DIM; print_step <= 0; summary_idx <= summary_idx + 1'b1; end
                            default: begin print_step <= 0; end
                        endcase
                    end
                end

                // Add a line break after the summary line to separate it from matrix dumps
                SEND_SUMMARY_NEWLINE: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= 8'd10; // newline
                        tx_start <= 1;
                        state <= WAIT_TX;
                        next_after_tx <= DONE;
                    end
                end

                WAIT_TX: begin
                    tx_start <= 0;
                    if (!tx_busy) begin // Wait for busy to go low (tx idle)
                         state <= next_after_tx;
                    end
                end

                DONE: begin
                    // ???????? output_done ? 1, ???? IDLE,
                    // ????? start ???????, ?????? start ???????
                    output_done <= 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
