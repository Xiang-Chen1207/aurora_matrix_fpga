`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_calc_top_v2
// Description: 完整的矩阵计算器顶层模块
// 功能：UART输入矩阵 → 存储 → 选择运算 → 计算 → UART输出结果
// 支持：转置、加法、标量乘法、矩阵乘法、卷积
//////////////////////////////////////////////////////////////////////////////////

module matrix_calc_top_v2(
    input wire clk,                  // 100MHz系统时钟
    input wire rst,                  // 复位信号（active high）
    input wire [7:0] sw,             // 8位拨码开关
    input wire btn_confirm,          // 确认按钮
    input wire uart_rx,              // UART接收
    output wire uart_tx,             // UART发送
    output wire [7:0] leds,          // LED状态指示
    output wire [6:0] seg,           // 7段数码管
    output wire [7:0] an             // 数码管位选
);

    // ========================================
    // 信号定义
    // ========================================
    wire rst_n = ~rst;

    // UART信号
    wire [7:0] rx_data;
    wire rx_done;
    wire tx_busy;
    wire tx_start;
    wire [7:0] tx_data;

    // 控制状态机信号
    wire [4:0] state;
    wire [3:0] op_type;
    wire error_led;
    wire start_input, start_output, start_store;
    wire read_en;
    wire [7:0] read_id;
    wire start_calc;
    wire [7:0] scalar_value;
    wire [7:0] operand_id_A, operand_id_B;
    wire [71:0] conv_kernel;
    wire [2:0] output_m, output_n;
    wire output_is_result;
    wire [3:0] display_digit;
    wire display_is_op;
    wire countdown_active;

    // 矩阵输入模块信号（200位版本）
    wire [2:0] input_m, input_n;
    wire [199:0] input_data;
    wire matrix_input_ready;
    wire [7:0] input_error;

    // 矩阵输出模块信号
    wire matrix_output_done;

    // 存储模块信号（200位版本）
    wire [7:0] stored_id;
    wire storage_write_done;
    wire [3:0] total_matrix_count;
    wire rd_valid, rd_error;
    wire [2:0] rd_m, rd_n;
    wire [199:0] rd_data;
    wire [159:0] matrix_info;
    wire [99:0] summary_counts;
    wire [15:0] match_ids; // NEW

    // Dump interface wires
    wire dump_en;
    wire [3:0] dump_index;
    wire dump_valid;
    wire [7:0] dump_id;
    wire [2:0] dump_m, dump_n;
    wire [199:0] dump_data;
    
    // Generator Signals // NEW
    wire start_gen;
    wire [3:0] gen_count;
    wire [2:0] gen_target_m, gen_target_n;
    wire [199:0] gen_data;
    wire gen_valid, gen_done;
    wire [2:0] gen_m_out, gen_n_out;
    
    // Output Mode Signals // NEW
    wire [2:0] output_mode;
    wire query_start;
    wire [2:0] query_m, query_n;
    wire [7:0] output_matrix_id;
    wire [199:0] output_custom_data;

    // 计算模块信号
    wire calc_done_internal;
    wire calc_error;
    wire [199:0] calc_result;
    wire [2:0] result_rows, result_cols;
    wire [31:0] conv_cycles;
    wire [639:0] conv_result;
    wire conv_done;

    // 矩阵A和B缓存（用于计算）
    reg [2:0] mat_A_rows, mat_A_cols;
    reg [2:0] mat_B_rows, mat_B_cols;
    reg [199:0] mat_A_data, mat_B_data;
    reg mat_A_valid, mat_B_valid;

    // 按钮消抖信号
    wire btn_debounced;

    // ========================================
    // UART接收模块
    // ========================================
    uart_rx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    // ========================================
    // UART发送模块
    // ========================================
    uart_tx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx(uart_tx),
        .tx_busy(tx_busy)
    );

    // ========================================
    // 按钮消抖
    // ========================================
    debounce u_debounce (
        .clk(clk),
        .button_in(btn_confirm),
        .button_out(btn_debounced)
    );

    // ========================================
    // 矩阵UART输入模块（V2版本-200位）
    // ========================================
    matrix_uart_input_v2 u_matrix_input (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_input),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .matrix_m(input_m),
        .matrix_n(input_n),
        .matrix_data(input_data),
        .matrix_ready(matrix_input_ready),
        .error_code(input_error)
    );
    
    // ========================================
    // 矩阵生成模块
    // ========================================
    matrix_gen u_matrix_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_gen),
        .m(gen_target_m),
        .n(gen_target_n),
        .count(gen_count),
        .gen_m(gen_m_out),
        .gen_n(gen_n_out),
        .gen_data(gen_data),
        .gen_valid(gen_valid),
        .gen_done(gen_done)
    );

    // ========================================
    // 矩阵UART输出模块
    // ========================================
    // 选择输出数据源
    wire [2:0] final_output_m;
    wire [2:0] final_output_n;
    wire [199:0] final_output_data;
    wire is_conv_output;
    // Data mux control signals
    wire [1:0] fsm_src_sel;
    wire [199:0] mux_matrix_data;

    assign is_conv_output = (op_type == 4'b1111) && output_is_result;
    assign final_output_m = output_is_result ? result_rows : rd_m;
    assign final_output_n = output_is_result ? result_cols : rd_n;
    assign output_matrix_id = (fsm_src_sel == 2'b10) ? dump_id : read_id;

    matrix_uart_output_v2 u_matrix_output (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_output),
        .matrix_m(output_m),
        .matrix_n(output_n),
        .matrix_data(mux_matrix_data), // Connected to Mux Output
        .conv_data(conv_result),
        .is_conv_result(is_conv_output),
        .tx_busy(tx_busy),
        
        // New features
        .mode(output_mode),
        .info_data(matrix_info),
        .match_ids(match_ids),
        .total_count(total_matrix_count),
        .summary_counts(summary_counts),
        .matrix_id(output_matrix_id),
        
        .tx_start(tx_start),
        .tx_data(tx_data),
        .output_done(matrix_output_done)
    );

    // ========================================
    // 矩阵存储模块（V2版本-200位）
    // ========================================
    // ========================================
    // 存储写入 MUX (UART Input vs Generator)
    // ========================================
    wire storage_write_en = start_store | gen_valid;
    wire [2:0] storage_wr_m = gen_valid ? gen_m_out : input_m;
    wire [2:0] storage_wr_n = gen_valid ? gen_n_out : input_n;
    wire [199:0] storage_wr_data = gen_valid ? gen_data : input_data;

    matrix_storage_v2 u_storage (
        .clk(clk),
        .rst_n(rst_n),
        // 写入接口
        .write_en(storage_write_en),
        .wr_m(storage_wr_m),
        .wr_n(storage_wr_n),
        .wr_data(storage_wr_data),
        .wr_id(stored_id),
        .wr_done(storage_write_done),
        // 读取接口
        .read_en(read_en),
        .rd_id(read_id),
        .rd_m(rd_m),
        .rd_n(rd_n),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .rd_error(rd_error),
        // 查询接口
        .query_en(query_start), // FSM controls query refresh
        .total_count(total_matrix_count),
        .matrix_info(matrix_info),
        .summary_counts(summary_counts),
        .query_dim_m(query_m),
        .query_dim_n(query_n),
        .match_ids(match_ids),
        // Dump interface
        .dump_en(dump_en),
        .dump_index(dump_index),
        .dump_valid(dump_valid),
        .dump_id(dump_id),
        .dump_m(dump_m),
        .dump_n(dump_n),
        .dump_data(dump_data)
    );

    // ========================================
    // 矩阵A/B缓存逻辑
    // ========================================
    // 状态定义（需与 controller_fsm_v2 中的编码保持一致）
    // controller_fsm_v2.v:
    //   S_MENU        = 5'd1;
    //   S_CALC_WAIT_A = 5'd12;
    //   S_CALC_WAIT_B = 5'd17;
    localparam S_CALC_WAIT_A = 5'd12;
    localparam S_CALC_WAIT_B = 5'd17;
    localparam S_MENU        = 5'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mat_A_valid <= 0;
            mat_B_valid <= 0;
            mat_A_rows <= 0;
            mat_A_cols <= 0;
            mat_A_data <= 0;
            mat_B_rows <= 0;
            mat_B_cols <= 0;
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

    // ========================================
    // 矩阵计算模块
    // ========================================
    matrix_calc_unit u_calc (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_calc),
        .op_type(op_type),
        .rows_A(mat_A_rows),
        .cols_A(mat_A_cols),
        .rows_B(mat_B_rows),
        .cols_B(mat_B_cols),
        .scalar(scalar_value),
        .mat_A(mat_A_data),
        .mat_B(mat_B_data),
        .conv_kernel(conv_kernel),
        .result(calc_result),
        .conv_result(conv_result),
        .result_rows(result_rows),
        .result_cols(result_cols),
        .conv_cycles(conv_cycles),
        .done(calc_done_internal),
        .error(calc_error)
    );

    // 计算完成信号（普通运算或卷积）
    assign conv_done = (op_type == 4'b1111) && calc_done_internal;
    wire calc_done = calc_done_internal;

    // ========================================
    // 主控制状态机
    // ========================================
    controller_fsm_v2 u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .button(btn_debounced),
        .sw(sw),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .matrix_input_ready(matrix_input_ready),
        .input_error(input_error),
        .matrix_output_done(matrix_output_done),
        .storage_write_done(storage_write_done),
        .total_matrix_count(total_matrix_count),
        .rd_valid(rd_valid),
        .rd_error(rd_error),
        .rd_m(rd_m),
        .rd_n(rd_n),
        .rd_data(rd_data),
        .calc_done(calc_done),
        .calc_error(calc_error),
        .calc_result(calc_result),
        .result_rows(result_rows),
        .result_cols(result_cols),
        .conv_done(conv_done),
        .conv_result(conv_result),
        .conv_cycles(conv_cycles),
        // 输出
        .state(state),
        .op_type(op_type),
        .error_led(error_led),
        .start_input(start_input),
        .start_output(start_output),
        .start_store(start_store),
        .read_id(read_id),
        .read_en(read_en),
        .start_calc(start_calc),
        .scalar_value(scalar_value),
        .operand_id_A(operand_id_A),
        .operand_id_B(operand_id_B),
        .conv_kernel(conv_kernel),
        .output_m(output_m),
        .output_n(output_n),
        .output_is_result(output_is_result),
        .display_digit(display_digit),
        .display_is_op(display_is_op),
        .countdown_active(countdown_active),
        
        // Generator & New Features
        .start_gen(start_gen),
        .gen_count(gen_count),
        .gen_target_m(gen_target_m),
        .gen_target_n(gen_target_n),
        .gen_done(gen_done),
        .output_mode(output_mode),
        .query_start(query_start),
        .query_m(query_m),
        .query_n(query_n),
        .output_sel(fsm_src_sel), // Control signal for UART data mux
        .output_custom_data(output_custom_data),
        .dump_en(dump_en),
        .dump_index(dump_index),
        .dump_valid(dump_valid),
        .dump_id(dump_id),
        .dump_m(dump_m),
        .dump_n(dump_n),
        .dump_data(dump_data)
        // .match_ids removed (FSM doesn't use it)
    );

    // ========================================
    // Data Mux Logic (Control/Data Separation)
    // ========================================
    // Select between storage read, calc result, or dump slot data
    assign mux_matrix_data = (fsm_src_sel == 2'b01) ? calc_result[199:0] :
                             (fsm_src_sel == 2'b10) ? dump_data :
                             (fsm_src_sel == 2'b11) ? output_custom_data :
                                                        rd_data[199:0];

    // ========================================
    // 数码管显示
    // ========================================
    seg_display_v2 u_seg_display (
        .clk(clk),
        .rst_n(rst_n),
        .state(state),
        .op_type(op_type),
        .display_digit(display_digit),
        .display_is_op(display_is_op),
        .countdown_active(countdown_active),
        .conv_cycles(conv_cycles),
        .seg(seg),
        .an(an)
    );

    // ========================================
    // LED状态指示（按需求映射）
    // led0: Idle, led1: Menu, led2: Input, led3: Generator, led4: Display,
    // led5: Compute阶段，led6: Store/Select，led7: Error
    wire led_idle     = (state == 5'd0);
    wire led_menu     = (state == 5'd1);
    wire led_input    = (state == 5'd2); // 输入阶段
    wire led_gen      = (state >= 5'd27 && state <= 5'd30); // 生成流程
    wire led_display  = (state == 5'd4) || (state == 5'd5);
    wire led_compute  = (state >= 5'd6 && state <= 5'd24); // 运算相关阶段
    wire led_store    = (state == 5'd3) || (state == 5'd8) || (state == 5'd9) ||
                        (state == 5'd10) || (state == 5'd11) || (state == 5'd12) ||
                        (state == 5'd17);

    assign leds[0] = led_idle;
    assign leds[1] = led_menu;
    assign leds[2] = led_input;
    assign leds[3] = led_gen;
    assign leds[4] = led_display;
    assign leds[5] = led_compute;
    assign leds[6] = led_store;
    assign leds[7] = error_led;

endmodule
