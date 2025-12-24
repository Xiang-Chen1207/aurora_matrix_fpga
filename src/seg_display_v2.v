`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Module Name: seg_display_v2
// Description: Enhanced 7-Segment Display Controller
// Features: Displays State, Op Type (T/A/b/C/J), and Conv Cycles
// Supports 8-digit dynamic scanning
////////////////////////////////////////////////////////////////////////////////

module seg_display_v2(
    input wire clk,
    input wire rst_n,
    input wire [4:0] state,
    input wire [3:0] op_type,
    input wire [3:0] display_digit,
    input wire display_is_op,
    input wire countdown_active,
    input wire [31:0] conv_cycles,
    output reg [6:0] seg,
    output reg [7:0] an
);

    // State definitions (Matched with FSM)
    localparam S_MENU = 5'd1;
    localparam S_CALC_SELECT_OP = 5'd6;
    localparam S_CONV_OUTPUT = 5'd18; // Note: Ensure this matches FSM S_GEN_EXECUTE or similar if needed?
                                      // Actually S_CONV_OUTPUT is 24 in FSM_V2.
                                      // Let's check FSM V2.
                                      // S_CONV_OUTPUT = 24.
                                      // User file had localparam S_CONV_OUTPUT = 5'd18; -> OLD FSM VALUE!
                                      // This logic was looking for old state values.
                                      // I must update these localparams to match FSM V2!

    // UPDATE LOCALPARAMS TO MATCH controller_fsm_v2
    localparam S_IDLE           = 5'd0;
    // localparam S_MENU           = 5'd1; // Already defined
    // localparam S_CALC_SELECT_OP = 5'd6; // Already defined
    localparam S_CONV_OUTPUT_V2 = 5'd24; // Correct value
    localparam S_COUNTDOWN_V2   = 5'd26; // Correct value

    // Scan Counter
    reg [19:0] scan_cnt;
    reg [2:0] digit_sel;

    // Current Display Digit
    reg [3:0] current_digit;
    reg show_dp;  // Decimal point (unused)

    // Scan Logic (Refresh Rate)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 0;
            digit_sel <= 0;
        end else begin
            if (scan_cnt >= 20'd100000) begin  // ~1ms
                scan_cnt <= 0;
                digit_sel <= digit_sel + 1;
            end else begin
                scan_cnt <= scan_cnt + 1;
            end
        end
    end

    // Anode Control (Active Low)
    always @(*) begin
        an = 8'b11111111;  // All Off
        case (digit_sel)
            3'd0: an = 8'b11111110;
            3'd1: an = 8'b11111101;
            3'd2: an = 8'b11111011;
            3'd3: an = 8'b11110111;
            3'd4: an = 8'b11101111;
            3'd5: an = 8'b11011111;
            3'd6: an = 8'b10111111;
            3'd7: an = 8'b01111111;
        endcase
    end

    // Extract Cycle Digits (Expensive div/mod, but standard logic)
    wire [3:0] cycles_digit7 = (conv_cycles / 10000000) % 10;
    wire [3:0] cycles_digit6 = (conv_cycles / 1000000) % 10;
    wire [3:0] cycles_digit5 = (conv_cycles / 100000) % 10;
    wire [3:0] cycles_digit4 = (conv_cycles / 10000) % 10;
    wire [3:0] cycles_digit3 = (conv_cycles / 1000) % 10;
    wire [3:0] cycles_digit2 = (conv_cycles / 100) % 10;
    wire [3:0] cycles_digit1 = (conv_cycles / 10) % 10;
    wire [3:0] cycles_digit0 = conv_cycles % 10;

    // Digit Selection Logic
    always @(*) begin
        current_digit = 4'd0;
        show_dp = 0;

        if (countdown_active) begin
            // 倒计时优先显示（个位显示秒数）
            if (digit_sel == 0)
                current_digit = display_digit;
            else
                current_digit = 4'd15;
        end else begin
            case (state)
                S_MENU: begin
                    // Menu: "----"
                    current_digit = 4'd15;  // '-'
                end

                S_CALC_SELECT_OP: begin
                    // 运算选择界面：第 0 位显示当前选择的运算类型字母
                    // 这里优先使用 FSM 提供的 display_digit（10~14），而不是 op_type，
                    // 这样在还没按确认键锁存 op_type 之前，拨动 S4~S7 也能立即看到变化。
                    if (digit_sel == 0) begin
                        if (display_is_op)
                            current_digit = display_digit; // 10~14 → T/A/B/C/J
                        else
                            current_digit = 4'd15;
                    end else begin
                        current_digit = 4'd15;  // 其它位用 '-'
                    end
                end

                S_CONV_OUTPUT_V2: begin
                    // Result: Cycles
                    case (digit_sel)
                        3'd0: current_digit = cycles_digit0;
                        3'd1: current_digit = cycles_digit1;
                        3'd2: current_digit = cycles_digit2;
                        3'd3: current_digit = cycles_digit3;
                        3'd4: current_digit = cycles_digit4;
                        3'd5: current_digit = cycles_digit5;
                        3'd6: current_digit = cycles_digit6;
                        3'd7: current_digit = cycles_digit7;
                    endcase
                end

                S_COUNTDOWN_V2: begin
                    // Error: Countdown
                    if (digit_sel == 0)
                        current_digit = display_digit;
                    else
                        current_digit = 4'd15;
                end

                default: begin
                    // Default: Show State ID (Debug)
                    if (digit_sel == 0)
                        current_digit = state[3:0];
                    else
                        current_digit = 4'd15;
                end
            endcase
        end
    end

    // ------------------------------------
    // 段码编码（参考当前板子，共阳极）
    // 与旧版 seg_display.v 保持一致
    // seg = {g, f, e, d, c, b, a}
    // ------------------------------------

    // 数字段码
    function [6:0] seg_num;
        input [3:0] n;
        begin
            case (n)
                4'd9: seg_num = 7'b1111011;
                4'd8: seg_num = 7'b1111111;
                4'd7: seg_num = 7'b1110000;
                4'd6: seg_num = 7'b1011111;
                4'd5: seg_num = 7'b1011011;
                4'd4: seg_num = 7'b0110011;
                4'd3: seg_num = 7'b1111001;
                4'd2: seg_num = 7'b1101101;
                4'd1: seg_num = 7'b0110000;
                4'd0: seg_num = 7'b1111110;
                default: seg_num = 7'b0000000;
            endcase
        end
    endfunction

    // 运算字母段码（根据 op_type 编码）
    function [6:0] seg_char;
        input [3:0] op;
        begin
            case (op)
                4'b0001: seg_char = 7'b0000111; // T 转置
                4'b0010: seg_char = 7'b1110111; // A 加法
                4'b0100: seg_char = 7'b0011111; // B 标量乘法
                4'b1000: seg_char = 7'b1001110; // C 矩阵乘法
                4'b1111: seg_char = 7'b0011110; // 卷积：用"J"样式，避免与数字0相同
                default: seg_char = 7'b0000000;
            endcase
        end
    endfunction

    // 最终 7 段输出：
    // 0–9 用 seg_num，10–14 映射到对应运算字母，15 为空
    always @(*) begin
        case (current_digit)
            4'd0,4'd1,4'd2,4'd3,4'd4,
            4'd5,4'd6,4'd7,4'd8,4'd9: begin
                seg = seg_num(current_digit);
            end

            // 10~14 用来显示运算类型字母
            4'd10: seg = seg_char(4'b0001); // T
            4'd11: seg = seg_char(4'b0010); // A
            4'd12: seg = seg_char(4'b0100); // B (标量)
            4'd13: seg = seg_char(4'b1000); // C
            4'd14: seg = seg_char(4'b1111); // 卷积

            // 15：空/关闭，用作占位
            default: seg = 7'b0000000;
        endcase
    end

endmodule
