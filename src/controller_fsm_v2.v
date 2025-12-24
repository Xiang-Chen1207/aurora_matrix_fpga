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

    // Dump access from storage
    input wire dump_valid,
    input wire [7:0] dump_id,
    input wire [2:0] dump_m,
    input wire [2:0] dump_n,
    input wire [199:0] dump_data,

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
    output wire countdown_active,
    output reg [2:0] output_m,
    output reg [2:0] output_n,

    // 运算控制
    output reg [3:0] op_type,        // 运算类型 (0001/0010/0100/1000/1111=卷积)
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
    output reg [2:0] output_mode, // 0=Matrix, 1=Info, 2=IDs, 3=Summary, 4=ID+Matrix
        output reg [199:0] output_custom_data, // custom payload when output_sel=3
    
    // 新增 Storage Query 接口
    output reg query_start,
    output reg [2:0] query_m,
    output reg [2:0] query_n,

    // Data Source Control (0=Storage, 1=Calc)
    output reg [1:0] output_sel,  // 0=storage read,1=calc result,2=dump slot

    // Dump interface to storage
    output reg dump_en,
    output reg [3:0] dump_index,

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

        // S_GEN_MATRIX 旧定义，复用为自动选择流程
        localparam S_CALC_AUTO      = 5'd31; 

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
    reg retry_countdown_active;   // 维度重选倒计时使能
    reg retry_need_select;        // 触发重新进入矩阵选择
    wire countdown_done;
    wire start_dim_retry;

    assign start_dim_retry = (state == S_CALC_VALIDATE) && mul_dim_invalid && !auto_mode;
    assign countdown_done = retry_countdown_active && (countdown_seconds == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_timer <= 0;
            countdown_seconds <= 10;
            retry_countdown_active <= 0;
            retry_need_select <= 0;
        end else begin
            // 启动手动矩阵乘维度重选倒计时
            if (start_dim_retry) begin
                retry_countdown_active <= 1;
                retry_need_select <= 1;
                countdown_seconds <= (sw[3:0] < 5) ? 4'd5 : sw[3:0];
                tick_timer <= 0;
            end else if (state == S_ERROR && !retry_countdown_active) begin
                // 其他错误场景沿用原倒计时，但不自动回到选择
                retry_countdown_active <= 1;
                retry_need_select <= 0;
                countdown_seconds <= (sw[3:0] < 5) ? 4'd5 : sw[3:0];
                tick_timer <= 0;
            end else if (retry_countdown_active && !countdown_done) begin
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

            // 成功通过校验或返回菜单后清除倒计时
            if ((state == S_CALC_VALIDATE && !mul_dim_invalid && !calc_error) || state == S_MENU) begin
                retry_countdown_active <= 0;
                retry_need_select <= 0;
                countdown_seconds <= 10;
            end
        end
    end

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
    reg [199:0] mat_A_data, mat_B_data;
    reg mat_A_valid, mat_B_valid;

    // Display phases for full dump: 0=summary,1=all matrices,2=done
    reg [1:0] display_phase;
    reg [3:0] dump_idx;
    reg [1:0] display_phase_last;
    reg [3:0] dump_idx_last;
    reg start_output_pulse;

    // Listing for dimension-filtered matrices during operand select
    reg list_active;
    reg [3:0] list_dump_idx;
    reg list_wait_output;
    reg list_done;
    reg [2:0] list_target_m;
    reg [2:0] list_target_n;
    reg list_output_pulse;

    // 自动选择相关寄存器
    reg auto_mode;
    reg [3:0] auto_phase;
    reg [3:0] auto_idx;
    reg [3:0] auto_attempts;
    reg auto_need_b;
    reg auto_have_a;
    reg auto_have_b;
    reg [7:0] auto_id_a;
    reg [7:0] auto_id_b;
    reg [2:0] auto_m_a;
    reg [2:0] auto_n_a;
    reg [2:0] auto_m_b;
    reg [2:0] auto_n_b;
    reg [7:0] auto_scalar;
    reg auto_scalar_ready;
    reg [71:0] auto_kernel;
    reg auto_kernel_ready;
    reg auto_out_pulse;
    reg auto_wait_output;
    reg [15:0] auto_rng;
    reg [3:0] auto_scan_idx; // 顺序扫描索引用于兜底

    // 自动模式最大尝试次数（不超过现有矩阵数，封顶10）
    // 自动模式最多尝试 10 次（允许多次抽空槽以命中有效矩阵）
    wire [3:0] auto_max_attempts = 4'd10;

    // 输出忙标志，避免上一轮 output_done 残留导致结果未输出就跳转
    reg output_busy;
    reg prev_matrix_output_done;

    wire auto_fb = auto_rng[15] ^ auto_rng[13] ^ auto_rng[12] ^ auto_rng[10];
    wire [15:0] auto_rng_next = {auto_rng[14:0], auto_fb};

    // Dimension validation helper
    wire mul_dim_invalid = (op_type == 4'b1000) && (mat_A_cols != mat_B_rows);

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
            display_phase <= 0;
            dump_idx <= 0;
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
                    display_phase <= 0;
                    dump_idx <= 0;
                end
            endcase

            // 维度重选时强制清空缓存以重新读取
            if (start_dim_retry) begin
                mat_A_valid <= 0;
                mat_B_valid <= 0;
            end

            // Display flow control
            if ((state == S_DISPLAY_SELECT && button_posedge) ||
                (state == S_MENU && button_posedge && sw[3:0] == 4'b0100)) begin
                display_phase <= 0;
                dump_idx <= 0;
            end else if (state == S_DISPLAY_SHOW) begin
                if (display_phase == 0 && matrix_output_done) begin
                    display_phase <= 1; // move to dump matrices
                    dump_idx <= 0;
                end else if (display_phase == 1) begin
                    // Advance when current output done or slot invalid
                    if ((matrix_output_done) || (!dump_valid && dump_en)) begin
                        if (dump_idx == 4'd9)
                            display_phase <= 2;
                        else
                            dump_idx <= dump_idx + 1'b1;
                    end
                end
            end
        end
    end

    // Pulse generation for display mode outputs (summary + each matrix)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_phase_last <= 2'b11;
            dump_idx_last <= 4'hf;
            start_output_pulse <= 0;
        end else begin
            start_output_pulse <= 0; // default low

            if (state == S_MENU) begin
                display_phase_last <= 2'b11;
                dump_idx_last <= 4'hf;
            end

            if (state == S_DISPLAY_SHOW) begin
                // Summary phase entry
                if (display_phase == 0 && display_phase_last != 0)
                    start_output_pulse <= 1;
                // First matrix when switching to dump phase
                else if (display_phase == 1 && display_phase_last != 1 && dump_valid)
                    start_output_pulse <= 1;
                // Subsequent matrices when dump_idx advances
                else if (display_phase == 1 && dump_valid && dump_idx != dump_idx_last)
                    start_output_pulse <= 1;

                display_phase_last <= display_phase;
                dump_idx_last <= dump_idx;
            end
        end
    end

    // Dimension-filtered listing control for operand selection
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            list_active <= 0;
            list_dump_idx <= 0;
            list_wait_output <= 0;
            list_done <= 0;
            list_target_m <= 0;
            list_target_n <= 0;
            list_output_pulse <= 0;
        end else begin
            list_output_pulse <= 0;

            if (state != S_CALC_A_LIST && state != S_CALC_B_LIST) begin
                list_active <= 0;
                list_dump_idx <= 0;
                list_wait_output <= 0;
                list_done <= 0;
            end else begin
                if (!list_active) begin
                    list_active <= 1;
                    list_dump_idx <= 0;
                    list_wait_output <= 0;
                    list_done <= 0;
                    if (state == S_CALC_A_LIST) begin
                        list_target_m <= temp_m;
                        list_target_n <= temp_n;
                    end else begin
                        if (op_type == 4'b0010) begin
                            list_target_m <= mat_A_rows;
                            list_target_n <= mat_A_cols;
                        end else begin
                            list_target_m <= temp_m;
                            list_target_n <= temp_n;
                        end
                    end
                end else if (!list_wait_output) begin
                    if (dump_valid && dump_m == list_target_m && dump_n == list_target_n) begin
                        list_output_pulse <= 1;
                        list_wait_output <= 1;
                    end else begin
                        if (list_dump_idx == 4'd9)
                            list_done <= 1;
                        else
                            list_dump_idx <= list_dump_idx + 1'b1;
                    end
                end else if (matrix_output_done) begin
                    list_wait_output <= 0;
                    if (list_dump_idx == 4'd9)
                        list_done <= 1;
                    else
                        list_dump_idx <= list_dump_idx + 1'b1;
                end
            end
        end
    end

    // 自动选择控制逻辑
    reg auto_fail;
    function [3:0] idx_mod10;
        input [15:0] val;
        begin
            if (val[3:0] > 4'd9)
                idx_mod10 = val[3:0] - 4'd10;
            else
                idx_mod10 = val[3:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_busy <= 0;
            prev_matrix_output_done <= 0;
            auto_mode <= 0;
            auto_phase <= 0;
            auto_idx <= 0;
            auto_scan_idx <= 0;
            auto_attempts <= 0;
            auto_need_b <= 0;
            auto_have_a <= 0;
            auto_have_b <= 0;
            auto_id_a <= 0;
            auto_id_b <= 0;
            auto_m_a <= 0;
            auto_n_a <= 0;
            auto_m_b <= 0;
            auto_n_b <= 0;
            auto_scalar <= 0;
            auto_scalar_ready <= 0;
            auto_kernel <= 0;
            auto_kernel_ready <= 0;
            auto_out_pulse <= 0;
            auto_wait_output <= 0;
            auto_rng <= 16'hD123;
            auto_fail <= 0;
        end else begin
            auto_out_pulse <= 0;
            prev_matrix_output_done <= matrix_output_done;

            // 清除输出忙标志
            if (output_busy && matrix_output_done)
                output_busy <= 0;

            // 退出条件
            if (state == S_MENU) begin
                auto_mode <= 0;
            end

            // 进入自动模式初始化
            if (state == S_CALC_SELECT_OP && button_posedge && sw[3] == 1'b0) begin
                auto_mode <= 1;
                auto_phase <= 0;
                auto_attempts <= 0;
                auto_scan_idx <= 0;
                auto_need_b <= (sw[7:4] == 4'b0010) || (sw[7:4] == 4'b1000);
                auto_have_a <= 0;
                auto_have_b <= 0;
                auto_scalar_ready <= 0;
                auto_kernel_ready <= 0;
                auto_wait_output <= 0;
                auto_fail <= 0;
                auto_idx <= idx_mod10(auto_rng_next);
                auto_rng <= auto_rng_next ^ {8'h5A, total_matrix_count};
            end else if (state == S_CALC_AUTO) begin
                auto_rng <= auto_rng_next;

                case (auto_phase)
                    0: begin
                        auto_attempts <= 0;
                        auto_wait_output <= 0;
                        if (op_type == 4'b1111) begin
                            // 随机生成 3x3 卷积核（值 0-9）
                            auto_kernel[7:0]   <= {4'd0, idx_mod10(auto_rng)};
                            auto_kernel[15:8]  <= {4'd0, idx_mod10(auto_rng_next)};
                            auto_kernel[23:16] <= {4'd0, idx_mod10(auto_rng_next ^ 16'h1234)};
                            auto_kernel[31:24] <= {4'd0, idx_mod10(auto_rng_next ^ 16'h2345)};
                            auto_kernel[39:32] <= {4'd0, idx_mod10(auto_rng_next ^ 16'h3456)};
                            auto_kernel[47:40] <= {4'd0, idx_mod10(auto_rng_next ^ 16'h4567)};
                            auto_kernel[55:48] <= {4'd0, idx_mod10(auto_rng_next ^ 16'h5678)};
                            auto_kernel[63:56] <= {4'd0, idx_mod10(auto_rng_next ^ 16'h6789)};
                            auto_kernel[71:64] <= {4'd0, idx_mod10(auto_rng_next ^ 16'h789A)};
                            auto_kernel_ready <= 1;
                            auto_out_pulse <= 1; // 输出卷积核
                            auto_wait_output <= 1;
                            auto_phase <= 7; // 输出完直接去计算
                        end else begin
                            auto_phase <= 1; // 先选 A
                        end
                    end

                    // 选择矩阵 A
                    1: begin
                        if (dump_valid) begin
                            auto_have_a <= 1;
                            auto_id_a <= dump_id;
                            auto_m_a <= dump_m;
                            auto_n_a <= dump_n;
                            auto_out_pulse <= 1;
                            auto_wait_output <= 1;
                            auto_phase <= 2; // 等待输出完成
                        end else if (auto_attempts < auto_max_attempts) begin
                            auto_attempts <= auto_attempts + 1'b1;
                            // 前半段随机，后半段顺序扫描 0..9 兜底
                            if (auto_attempts < (auto_max_attempts >> 1)) begin
                                auto_idx <= idx_mod10(auto_rng_next);
                            end else begin
                                auto_idx <= auto_scan_idx;
                                if (auto_scan_idx == 4'd9)
                                    auto_scan_idx <= 0;
                                else
                                    auto_scan_idx <= auto_scan_idx + 1'b1;
                            end
                        end else begin
                            auto_fail <= 1;
                        end
                    end

                    // 等待 A 输出完成
                    2: begin
                        if (matrix_output_done && auto_wait_output) begin
                            auto_wait_output <= 0;
                            if (auto_need_b) begin
                                auto_phase <= 3;
                                auto_attempts <= 0;
                                auto_idx <= idx_mod10(auto_rng_next);
                            end else if (op_type == 4'b0100) begin
                                // 标量乘法：选择标量并输出
                                auto_scalar <= {4'd0, idx_mod10(auto_rng_next)};
                                auto_scalar_ready <= 1;
                                auto_out_pulse <= 1;
                                auto_wait_output <= 1;
                                auto_phase <= 6; // 等待标量输出
                            end else begin
                                auto_phase <= 8; // 转置直接进入计算
                            end
                        end
                    end

                    // 选择矩阵 B（加法/乘法）
                    3: begin
                        if (dump_valid) begin
                            // 加法: 维度匹配且 B 不能等于 A；乘法: 维度匹配且 B 不能等于 A
                            if ((op_type == 4'b0010 && dump_m == auto_m_a && dump_n == auto_n_a && dump_id != auto_id_a) ||
                                (op_type == 4'b1000 && dump_m == auto_n_a && dump_id != auto_id_a)) begin
                                auto_have_b <= 1;
                                auto_id_b <= dump_id;
                                auto_m_b <= dump_m;
                                auto_n_b <= dump_n;
                                auto_out_pulse <= 1;
                                auto_wait_output <= 1;
                                auto_phase <= 4; // 等待 B 输出完成
                            end else begin
                                auto_attempts <= auto_attempts + 1'b1;
                                if (auto_attempts < (auto_max_attempts >> 1)) begin
                                    auto_idx <= idx_mod10(auto_rng_next);
                                end else begin
                                    auto_idx <= auto_scan_idx;
                                    if (auto_scan_idx == 4'd9)
                                        auto_scan_idx <= 0;
                                    else
                                        auto_scan_idx <= auto_scan_idx + 1'b1;
                                end
                            end
                        end else if (auto_attempts < auto_max_attempts) begin
                            auto_attempts <= auto_attempts + 1'b1;
                            if (auto_attempts < (auto_max_attempts >> 1)) begin
                                auto_idx <= idx_mod10(auto_rng_next);
                            end else begin
                                auto_idx <= auto_scan_idx;
                                if (auto_scan_idx == 4'd9)
                                    auto_scan_idx <= 0;
                                else
                                    auto_scan_idx <= auto_scan_idx + 1'b1;
                            end
                        end else begin
                            auto_fail <= 1;
                        end
                    end

                    // 等待 B 输出完成
                    4: begin
                        if (matrix_output_done && auto_wait_output) begin
                            auto_wait_output <= 0;
                            auto_phase <= 8;
                        end
                    end

                    // 等待标量输出完成
                    6: begin
                        if (matrix_output_done && auto_wait_output) begin
                            auto_wait_output <= 0;
                            auto_phase <= 8;
                        end
                    end

                    // 卷积核输出完成
                    7: begin
                        if (matrix_output_done && auto_wait_output) begin
                            auto_wait_output <= 0;
                            auto_phase <= 8;
                        end
                    end

                    // 准备进入计算；若乘法维度不匹配则重选 B 或失败
                    8: begin
                        if (op_type == 4'b1000 && auto_need_b && auto_have_a && auto_have_b && auto_n_a != auto_m_b) begin
                            if (auto_attempts < auto_max_attempts) begin
                                auto_have_b <= 0;
                                auto_wait_output <= 0;
                                auto_attempts <= auto_attempts + 1'b1;
                                auto_idx <= idx_mod10(auto_rng_next);
                                auto_phase <= 3; // 重新挑选 B
                            end else begin
                                auto_fail <= 1; // 超过尝试次数，触发错误
                            end
                        end else begin
                            auto_phase <= 9;
                        end
                    end

                    default: ;
                endcase
            end
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
            end else if (state == S_CALC_AUTO && auto_kernel_ready) begin
                conv_kernel <= auto_kernel;
            end else if (state == S_MENU) begin
                kernel_elem_cnt <= 0;
            end
        end
    end

    // 下一状态逻辑
    always @(*) begin
        next_state = state;

        // 倒计时超时优先返回主菜单
        if (countdown_done)
            next_state = S_MENU;
        else begin
        case (state)
            S_IDLE: next_state = S_MENU;

            S_MENU: begin
                if (button_posedge) begin
                    case (sw[3:0])
                        4'b0001: next_state = S_INPUT_MATRIX;
                        4'b0010: next_state = S_GEN_INPUT_M;  // 模式2：生成
                        4'b0100: next_state = S_DISPLAY_SHOW;  // 直接进入显示，无需第二次确认
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
            S_DISPLAY_SHOW: begin
                if (display_phase == 0) begin
                    if (matrix_output_done) next_state = S_DISPLAY_SHOW; // proceed to dump phase
                end else if (display_phase == 1) begin
                    if (display_phase == 1 && dump_idx == 4'd9 && (matrix_output_done || (!dump_valid && dump_en)))
                        next_state = S_MENU;
                end else if (display_phase == 2) begin
                    next_state = S_MENU;
                end
            end

            // --- 计算准备 ---
            S_CALC_SELECT_OP: begin
                if (button_posedge) begin
                    if (sw[3] == 1'b0) begin
                        next_state = S_CALC_AUTO; // 自动模式
                    end else begin
                        case (sw[7:4])
                            4'b1111: next_state = S_CONV_INPUT; // 卷积特殊流程（改为 1111）
                            default: next_state = S_CALC_SHOW_INFO; 
                        endcase
                    end
                end
            end

            // 显示存储信息
            S_CALC_SHOW_INFO: if (matrix_output_done) next_state = S_CALC_A_M;

            // 选择 A (2步)
            S_CALC_A_M: if (id_received) next_state = S_CALC_A_N;
            S_CALC_A_N: if (id_received) next_state = S_CALC_A_LIST;
            S_CALC_A_LIST: if (list_done) next_state = S_CALC_A_ID;
            S_CALC_A_ID: if (id_received) next_state = S_CALC_WAIT_A;
            S_CALC_WAIT_A: begin
                if (rd_error) next_state = S_ERROR;
                else if (rd_valid) begin
                    if (auto_mode) begin
                        if (auto_need_b)
                            next_state = S_CALC_WAIT_B;
                        else if (op_type == 4'b0100)
                            next_state = S_CALC_COMPUTE; // 自动标量
                        else
                            next_state = S_CALC_COMPUTE; // 自动转置
                    end else begin
                        case (op_type)
                            4'b0001: next_state = S_CALC_COMPUTE; // 转置
                            4'b0010: next_state = S_CALC_B_LIST;  // 加法，直接用A的维度选B
                            4'b0100: next_state = S_CALC_SEL_SCALAR; // 标量
                            default: next_state = S_CALC_B_M; // 矩阵乘需要单独输入B维度
                        endcase
                    end
                end
            end

            // 选择 B (2步)
            S_CALC_B_M: if (id_received) next_state = S_CALC_B_N;
            S_CALC_B_N: if (id_received) next_state = S_CALC_B_LIST;
            S_CALC_B_LIST: if (list_done) next_state = S_CALC_B_ID;
            S_CALC_B_ID: if (id_received) next_state = S_CALC_WAIT_B;
            S_CALC_WAIT_B: if (rd_error) next_state = S_ERROR;
                          else if (rd_valid) next_state = S_CALC_VALIDATE;

            // 标量
            S_CALC_SEL_SCALAR: if (button_posedge) next_state = S_CALC_COMPUTE;

            S_CALC_VALIDATE: if (start_dim_retry) next_state = S_COUNTDOWN;
                             else if (calc_error) next_state = S_ERROR;
                             else next_state = S_CALC_COMPUTE;

            S_CALC_COMPUTE: if (calc_done) next_state = S_CALC_OUTPUT;
                           else if (calc_error) next_state = S_ERROR;
            // 使用输出完成的上升沿避免旧的done残留；仅在看到新的完成脉冲时离开
            S_CALC_OUTPUT: if (matrix_output_done && !prev_matrix_output_done) next_state = S_MENU;

            // 卷积
            S_CONV_INPUT: if (kernel_elem_cnt >= 9 && button_posedge) next_state = S_CONV_COMPUTE;
            S_CONV_COMPUTE: if (conv_done) next_state = S_CONV_OUTPUT;
            S_CONV_OUTPUT: if (matrix_output_done && !prev_matrix_output_done) next_state = S_MENU;

            // 自动模式
            S_CALC_AUTO: begin
                if (auto_fail) next_state = S_ERROR;
                else if (auto_phase == 4'd9) begin
                    if (op_type == 4'b1111)
                        next_state = S_CONV_COMPUTE;
                    else
                        next_state = S_CALC_WAIT_A;
                end
            end

            // 错误/倒计时
            S_ERROR: next_state = S_COUNTDOWN;
            S_COUNTDOWN: begin
                if (retry_need_select)
                    next_state = S_CALC_A_M; // 自动回到选择
                else if (button_posedge)
                    next_state = S_CALC_A_M; // 手动重试
            end

            default: next_state = S_MENU;
        endcase
        end
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
        output_sel = 0; // 0=storage read,1=calc,2=dump,3=custom
        dump_en = 0;
        dump_index = 0;
        output_custom_data = 0;
        output_busy = 0;
        
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
            // 在 S_GEN_INPUT_CNT 状态下, parsed_id 保存用户输入的矩阵个数
            // 规格要求个数不超过 2, 因此在此进行饱和剪裁
            S_GEN_EXECUTE: begin
                start_gen   = 1;
                gen_target_m = temp_m;
                gen_target_n = temp_n;
                // 生成矩阵个数: 默认 1 个, 大于 2 则按 2 处理, 0 视作 1
                if (parsed_id[3:0] == 4'd0)
                    gen_count = 4'd1;
                else if (parsed_id[3:0] > 4'd2)
                    gen_count = 4'd2;
                else
                    gen_count = parsed_id[3:0];
            end

            S_DISPLAY_SHOW: begin
                // Phase handled in sequential regs: phase 0 summary, phase 1 dump matrices
                if (display_phase == 0) begin
                    output_mode = 3'd3; // Summary mode
                    start_output = start_output_pulse; // pulse once when entering summary
                    query_start = 1; // refresh counts and summary bus
                end else if (display_phase == 1) begin
                    dump_en = 1;
                    dump_index = dump_idx;
                    if (dump_valid) begin
                        start_output = start_output_pulse; // pulse per matrix slot
                        output_m = dump_m;
                        output_n = dump_n;
                        output_mode = 3'd4; // ID + Matrix
                        output_sel = 2; // dump slot data
                    end
                end
            end

            S_CALC_SELECT_OP: begin
                display_is_op = 1;
                case (sw[7:4])
                    4'b0001: display_digit = 4'd10;  // T
                    4'b0010: display_digit = 4'd11;  // A
                    4'b0100: display_digit = 4'd12;  // b
                    4'b1000: display_digit = 4'd13;  // C
                    4'b1111: display_digit = 4'd14;  // J
                    default: display_digit = 4'd0;
                endcase
            end
            
            // --- Show Info ---
            S_CALC_SHOW_INFO: begin
                output_mode = 3'd1; // Info List
                start_output = 1;
                query_start = 1; 
            end
            
            // --- Select A ---
            S_CALC_A_LIST: begin
                dump_en = 1;
                dump_index = list_dump_idx;
                output_mode = 3'd4; // ID + Matrix
                if (dump_valid && dump_m == list_target_m && dump_n == list_target_n) begin
                    start_output = list_output_pulse;
                    output_m = dump_m;
                    output_n = dump_n;
                    output_sel = 2; // dump slot data
                end
            end
            S_CALC_WAIT_A: begin
                // 发起一次读取，拿到 rd_valid 后拉低以清除存储端 rd_valid
                if (!rd_valid) begin
                    read_en = 1;
                    read_id = auto_mode ? operand_id_A : parsed_id;
                end
            end

            // --- Select B ---
            S_CALC_B_LIST: begin
                dump_en = 1;
                dump_index = list_dump_idx;
                output_mode = 3'd4; // ID + Matrix
                if (dump_valid && dump_m == list_target_m && dump_n == list_target_n) begin
                    start_output = list_output_pulse;
                    output_m = dump_m;
                    output_n = dump_n;
                    output_sel = 2; // dump slot data
                end
            end
            S_CALC_WAIT_B: begin
                if (!rd_valid) begin
                    read_en = 1;
                    read_id = auto_mode ? operand_id_B : parsed_id;
                end
            end

            S_CALC_COMPUTE: start_calc = 1;
            S_CALC_OUTPUT: begin
                start_output = 1;
                output_is_result = 1;
                output_m = result_rows;
                output_n = result_cols;
                output_sel = 1; // Calc Result
                output_busy = 1; // 标记输出进行中
            end

            S_CONV_COMPUTE: start_calc = 1;
            S_CONV_OUTPUT: begin
                start_output = 1;
                output_is_result = 1;
                output_m = 3'd5;
                output_n = 3'd5;
                output_sel = 1; // Calc/Conv Result
                output_busy = 1; // 标记输出进行中（卷积结果）
            end

            // 自动模式输出（随机选择/展示）
            S_CALC_AUTO: begin
                dump_en = 1;
                dump_index = auto_idx;
                if (op_type == 4'b1111 && auto_kernel_ready) begin
                    // 输出卷积核 3x3
                    output_mode = 3'd0;
                    output_sel = 3; // custom data
                    output_custom_data[71:0] = auto_kernel;
                    output_m = 3'd3;
                    output_n = 3'd3;
                    start_output = auto_out_pulse;
                end else if (op_type == 4'b0100 && auto_scalar_ready && !auto_need_b) begin
                    // 输出标量（作为1x1矩阵）
                    output_mode = 3'd0;
                    output_sel = 3; // custom data
                    output_custom_data[7:0] = auto_scalar;
                    output_m = 3'd1;
                    output_n = 3'd1;
                    start_output = auto_out_pulse;
                end else if (dump_valid) begin
                    // 输出矩阵（带ID）
                    output_mode = 3'd4;
                    output_m = dump_m;
                    output_n = dump_n;
                    output_sel = 2; // dump slot data
                    start_output = auto_out_pulse;
                end
            end

            S_ERROR, S_COUNTDOWN: begin
                error_led = 1;
                display_digit = countdown_seconds;
            end
        endcase

        // 维度重选倒计时期间，保持错误提示与倒计时显示，无论当前状态
        if (retry_countdown_active) begin
            error_led = 1;
            display_digit = countdown_seconds;
            display_is_op = 0;
        end
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
                S_CALC_AUTO: begin
                    if (auto_have_a)
                        operand_id_A <= auto_id_a;
                    if (auto_have_b)
                        operand_id_B <= auto_id_b;
                    if (op_type == 4'b0100 && auto_scalar_ready)
                        scalar_value <= auto_scalar;
                end
            endcase
        end
    end

    assign countdown_active = retry_countdown_active;

endmodule
