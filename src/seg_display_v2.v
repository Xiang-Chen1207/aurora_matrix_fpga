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

        case (state)
            S_MENU: begin
                // Menu: "----"
                current_digit = 4'd15;  // '-'
            end

            S_CALC_SELECT_OP: begin
                // Select Op: Show T/A/b/C/J
                if (digit_sel == 0) begin
                    case (op_type)
                        4'b0001: current_digit = 4'd10;  // 'T'
                        4'b0010: current_digit = 4'd11;  // 'A'
                        4'b0100: current_digit = 4'd12;  // 'b'
                        4'b1000: current_digit = 4'd13;  // 'C'
                        4'b1001: current_digit = 4'd14;  // 'J'
                        default: current_digit = 4'd15;
                    endcase
                end else begin
                    current_digit = 4'd15;  // '-'
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

    // 7-Segment Decoder (Common Power, Active High Segments)
    // seg = {g, f, e, d, c, b, a}
    always @(*) begin
        case (current_digit)
            4'd0:  seg = 7'b0111111;  // 0
            4'd1:  seg = 7'b0000110;  // 1
            4'd2:  seg = 7'b1011011;  // 2
            4'd3:  seg = 7'b1001111;  // 3
            4'd4:  seg = 7'b1100110;  // 4
            4'd5:  seg = 7'b1101101;  // 5
            4'd6:  seg = 7'b1111101;  // 6
            4'd7:  seg = 7'b0000111;  // 7
            4'd8:  seg = 7'b1111111;  // 8
            4'd9:  seg = 7'b1101111;  // 9
            4'd10: seg = 7'b1111000;  // T
            4'd11: seg = 7'b1110111;  // A
            4'd12: seg = 7'b1111100;  // b
            4'd13: seg = 7'b0111001;  // C
            4'd14: seg = 7'b0111100;  // J
            4'd15: seg = 7'b1000000;  // -
            default: seg = 7'b0000000;
        endcase
    end

endmodule
