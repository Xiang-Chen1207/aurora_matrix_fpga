`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_storage_v2
// Description: 增强版矩阵存储管理模�?
// 功能�?
//   1. 每种规格(m×n)�?多存�?2个矩�?
//   2. 自动编号�?1, 2, ...�?
//   3. 新矩阵覆盖旧矩阵（轮换机制）
//   4. 支持200位数据（8�?/元素�?
//////////////////////////////////////////////////////////////////////////////////

module matrix_storage_v2(
    input wire clk,
    input wire rst_n,

    // 写入接口
    input wire write_en,
    input wire [2:0] wr_m,              // 行数
    input wire [2:0] wr_n,              // 列数
    input wire [199:0] wr_data,         // 矩阵数据 (25×8bit)
    output reg [7:0] wr_id,             // 分配的ID
    output reg wr_done,

    // 读取接口
    input wire read_en,
    input wire [7:0] rd_id,
    output reg [2:0] rd_m,
    output reg [2:0] rd_n,
    output reg [199:0] rd_data,
    output reg rd_valid,
    output reg rd_error,

    // 查询接口
    input wire query_en,
    output reg [3:0] total_count,
    output reg [79:0] matrix_info,       // 10个矩阵的规格信息（每�?8位：ID+m+n�?
    
    // 维度查询接口 (v2.1 Feature)
    input wire [2:0] query_dim_m,
    input wire [2:0] query_dim_n,
    output reg [15:0] match_ids         // 匹配的ID列表 (支持多个ID，每4位一个ID)
);

    // 存储参数
    parameter MAX_MATRICES = 10;

    // 存储数组
    reg [2:0] stored_m [0:MAX_MATRICES-1];
    reg [2:0] stored_n [0:MAX_MATRICES-1];
    reg [199:0] stored_data [0:MAX_MATRICES-1];
    reg [7:0] stored_id [0:MAX_MATRICES-1];
    reg stored_valid [0:MAX_MATRICES-1];

    // ID计数�?
    reg [7:0] next_id;

    // 规格索引计数器（用于轮换�?
    reg [1:0] dim_counter [0:24];

    // 计算规格索引
    function [4:0] get_dim_index;
        input [2:0] m, n;
        begin
            case ({m, n})
                {3'd1, 3'd1}: get_dim_index = 0;
                {3'd1, 3'd2}: get_dim_index = 1;
                {3'd1, 3'd3}: get_dim_index = 2;
                {3'd2, 3'd1}: get_dim_index = 3;
                {3'd2, 3'd2}: get_dim_index = 4;
                {3'd2, 3'd3}: get_dim_index = 5;
                {3'd3, 3'd1}: get_dim_index = 6;
                {3'd3, 3'd2}: get_dim_index = 7;
                {3'd3, 3'd3}: get_dim_index = 8;
                default:      get_dim_index = 9;
            endcase
        end
    endfunction

    integer i;
    integer dim_idx, slot, store_pos;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_id <= 1;
            total_count <= 0;
            wr_done <= 0;
            rd_valid <= 0;
            rd_error <= 0;
            matrix_info <= 0;
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                stored_valid[i] <= 0;
                stored_id[i] <= 0;
                stored_m[i] <= 0;
                stored_n[i] <= 0;
                stored_data[i] <= 0;
            end
            for (i = 0; i < 25; i = i + 1) begin
                dim_counter[i] <= 0;
            end
        end else begin
            // 清除完成信号
            if (!write_en) wr_done <= 0;
            if (!read_en) begin
                rd_valid <= 0;
                rd_error <= 0;
            end

            // 写入逻辑
            if (write_en && !wr_done) begin
                dim_idx = get_dim_index(wr_m, wr_n);
                slot = dim_counter[dim_idx];
                store_pos = dim_idx * 2 + slot;

                if (store_pos < MAX_MATRICES) begin
                    stored_m[store_pos] <= wr_m;
                    stored_n[store_pos] <= wr_n;
                    stored_data[store_pos] <= wr_data;
                    stored_id[store_pos] <= next_id;
                    stored_valid[store_pos] <= 1;

                    wr_id <= next_id;
                    wr_done <= 1;

                    next_id <= next_id + 1;
                    dim_counter[dim_idx] <= (slot == 1) ? 0 : 1;

                    if (!stored_valid[store_pos] && total_count < MAX_MATRICES)
                        total_count <= total_count + 1;
                end
            end

            // 读取逻辑
            if (read_en && !rd_valid && !rd_error) begin
                rd_valid <= 0;
                rd_error <= 1;  // 默认错误，找到后清除

                for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                    if (stored_valid[i] && stored_id[i] == rd_id) begin
                        rd_m <= stored_m[i];
                        rd_n <= stored_n[i];
                        rd_data <= stored_data[i];
                        rd_valid <= 1;
                        rd_error <= 0;
                    end
                end
            end

            // 查询逻辑
            if (query_en) begin
                for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                    if (stored_valid[i]) begin
                        matrix_info[i*8 +: 8] <= {stored_id[i][1:0], stored_m[i], stored_n[i]};
                    end else begin
                        matrix_info[i*8 +: 8] <= 8'd0;
                    end
                end
            end
            
            // 维度匹配逻辑 (始终有效，组合�?�辑或同步更�?)
            // 这里使用同步更新
            begin
                match_ids <= 0;
                // �?单的手写循环展开或�?�辑
                // 由于Verilog循环比较麻烦，且我们知道�?�?2个，且存放在特定slot�?
                // 暂时遍历�?有有效矩�?
                // 这里的�?�辑稍微�?单化：找到匹配的就塞进去
                // 为了�?单，我们每次重置match_ids
                // 使用临时变量方便
            end
        end
    end
    
    // 组合逻辑生成匹配ID列表
    reg [3:0] match_cnt_temp;
    integer k;
    always @(*) begin
        match_ids = 0;
        match_cnt_temp = 0;
        for (k = 0; k < MAX_MATRICES; k = k + 1) begin
            if (stored_valid[k] && stored_m[k] == query_dim_m && stored_n[k] == query_dim_n) begin
                // Found match
                if (match_cnt_temp < 4) begin
                    case(match_cnt_temp)
                        0: match_ids[3:0]   = stored_id[k][3:0];
                        1: match_ids[7:4]   = stored_id[k][3:0];
                        2: match_ids[11:8]  = stored_id[k][3:0];
                        3: match_ids[15:12] = stored_id[k][3:0];
                    endcase
                    match_cnt_temp = match_cnt_temp + 1;
                end
            end
        end
    end

endmodule
