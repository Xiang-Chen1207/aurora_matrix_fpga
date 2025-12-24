`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_storage_v2
// Description: Storage Module
// Function:
//   1. Store up to 10 matrices (any size up to 5x5)
//   2. Auto ID generation
//   3. Per-dimension 2-slot rotation: third matrix of same size overwrites the older one
//   4. Global rotation fallback when storage is full and size is new
//   5. Support 200-bit data
//////////////////////////////////////////////////////////////////////////////////

module matrix_storage_v2(
    input wire clk,
    input wire rst_n,

    // Write Interface
    input wire write_en,
    input wire [2:0] wr_m,              // Rows
    input wire [2:0] wr_n,              // Cols
    input wire [199:0] wr_data,         // Data
    output reg [7:0] wr_id,             // Assigned ID
    output reg wr_done,

    // Read Interface
    input wire read_en,
    input wire [7:0] rd_id,
    output reg [2:0] rd_m,
    output reg [2:0] rd_n,
    output reg [199:0] rd_data,
    output reg rd_valid,
    output reg rd_error,

    // Query Interface
    input wire query_en,
    output reg [3:0] total_count,
    output reg [159:0] matrix_info,      // 10 entries info: per entry {id[7:0], m[2:0], n[2:0], 2'b0}
    output reg [99:0] summary_counts,    // 25 dims * 4-bit count (1..5 x 1..5)
    
    // Dimension Match Interface (v2.1 Feature)
    input wire [2:0] query_dim_m,
    input wire [2:0] query_dim_n,
    output reg [15:0] match_ids,         // Matched ID list

    // Dump-by-index Interface (for full display)
    input wire dump_en,
    input wire [3:0] dump_index,
    output reg dump_valid,
    output reg [7:0] dump_id,
    output reg [2:0] dump_m,
    output reg [2:0] dump_n,
    output reg [199:0] dump_data
);

    // Params
    parameter MAX_MATRICES = 10;

    // Storage
    reg [2:0] stored_m [0:MAX_MATRICES-1];
    reg [2:0] stored_n [0:MAX_MATRICES-1];
    reg [199:0] stored_data [0:MAX_MATRICES-1];
    reg [7:0] stored_id [0:MAX_MATRICES-1];
    reg stored_valid [0:MAX_MATRICES-1];

    // ID Counter
    reg [7:0] next_id;

    // Global write pointer (0..MAX_MATRICES-1), used for fallback overwrite when storage is full
    reg [3:0] write_index;

    // Per-dimension toggle to alternate overwrite between the two slots of the same size
    // dim_idx = (m-1)*5 + (n-1), ranges 0..24 for 1..5 x 1..5
    reg replace_toggle [0:24];

    // Clamp incoming dimensions to 1..5 to avoid invalid sizes propagating
    wire [2:0] eff_wr_m = (wr_m == 0) ? 3'd1 : (wr_m > 3'd5 ? 3'd5 : wr_m);
    wire [2:0] eff_wr_n = (wr_n == 0) ? 3'd1 : (wr_n > 3'd5 ? 3'd5 : wr_n);

    // Dimension index for toggle array
    wire [4:0] dim_idx = (eff_wr_m - 1) * 5 + (eff_wr_n - 1);

    // Combinational search helpers
    reg [1:0] same_cnt;
    reg [3:0] same_idx0;
    reg [3:0] same_idx1;
    reg has_free;
    reg [3:0] free_idx;

    // Write target bookkeeping
    reg [3:0] target_idx;
    reg is_new_slot;
    reg use_existing_id;

    // Dimension counts (1..5 x 1..5 => 25 entries, each up to 10, 4 bits enough for our cap=2)
    reg [3:0] dim_counts [0:24];

    integer i;
    integer j;

    // Scan existing storage to find matches and free slots for current dimension
    always @(*) begin
        same_cnt = 0;
        same_idx0 = 0;
        same_idx1 = 0;
        has_free = 0;
        free_idx = 0;

        for (j = 0; j < MAX_MATRICES; j = j + 1) begin
            if (stored_valid[j] && stored_m[j] == eff_wr_m && stored_n[j] == eff_wr_n) begin
                if (same_cnt == 0) same_idx0 = j[3:0];
                else if (same_cnt == 1) same_idx1 = j[3:0];
                if (same_cnt < 2) same_cnt = same_cnt + 1;
            end
            if (!stored_valid[j] && !has_free) begin
                has_free = 1;
                free_idx = j[3:0];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_id <= 1;
            total_count <= 0;
            wr_done <= 0;
            rd_valid <= 0;
            rd_error <= 0;
            matrix_info <= 0;
            write_index <= 0;
            summary_counts <= 0;
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                stored_valid[i] <= 0;
                stored_id[i] <= 0;
                stored_m[i] <= 0;
                stored_n[i] <= 0;
                stored_data[i] <= 0;
            end
            for (i = 0; i < 25; i = i + 1) begin
                replace_toggle[i] <= 0;
                dim_counts[i] <= 0;
            end
        end else begin
            // Clear signals
            if (!write_en) wr_done <= 0;
            if (!read_en) begin
                rd_valid <= 0;
                rd_error <= 0;
            end

            // Write Logic with per-dimension 2-slot rotation
            if (write_en && !wr_done) begin
                // Determine target slot
                if (same_cnt >= 2) begin
                    // Already have two of this size: overwrite alternately
                    target_idx = replace_toggle[dim_idx] ? same_idx1 : same_idx0;
                    replace_toggle[dim_idx] <= ~replace_toggle[dim_idx];
                    is_new_slot = 0;
                end else if (same_cnt == 1) begin
                    if (has_free) begin
                        target_idx = free_idx;
                        is_new_slot = 1;
                    end else begin
                        target_idx = same_idx0; // no free slot, overwrite the existing one
                        is_new_slot = 0;
                    end
                end else begin
                    if (has_free) begin
                        target_idx = free_idx;
                        is_new_slot = 1;
                    end else begin
                        target_idx = write_index; // fallback global rotation
                        is_new_slot = !stored_valid[write_index];
                    end
                end

                // Decide whether to keep existing ID (overwrite same dimension) or assign new ID
                use_existing_id = (!is_new_slot) && stored_valid[target_idx] &&
                                   (stored_m[target_idx] == eff_wr_m) && (stored_n[target_idx] == eff_wr_n);

                // Perform write
                stored_m[target_idx]    <= eff_wr_m;
                stored_n[target_idx]    <= eff_wr_n;
                stored_data[target_idx] <= wr_data;
                stored_id[target_idx]   <= use_existing_id ? stored_id[target_idx] : next_id;
                stored_valid[target_idx]<= 1;

                wr_id   <= use_existing_id ? stored_id[target_idx] : next_id;
                wr_done <= 1;

                // Advance ID and rotation pointer
                if (!use_existing_id)
                    next_id <= next_id + 1;
                if (is_new_slot && total_count < MAX_MATRICES)
                    total_count <= total_count + 1;

                if (write_index == MAX_MATRICES-1)
                    write_index <= 0;
                else
                    write_index <= write_index + 1;
            end

            // Read Logic
            if (read_en && !rd_valid && !rd_error) begin
                rd_valid <= 0;
                rd_error <= 1;  // Default Error

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

            // Query Logic
            if (query_en) begin
                for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                    if (stored_valid[i]) begin
                        // Pack full 8-bit ID + dims (3b+3b) into 16-bit slot
                        matrix_info[i*16 +: 16] <= {stored_id[i], stored_m[i], stored_n[i], 2'b00};
                    end else begin
                        matrix_info[i*16 +: 16] <= 16'd0;
                    end
                end
            end
        end
    end
    
    // Combinatorial Match Logic
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

    // Dump-by-index combinational access
    always @(*) begin
        if (dump_en && dump_index < MAX_MATRICES) begin
            dump_valid = stored_valid[dump_index];
            dump_id    = stored_id[dump_index];
            dump_m     = stored_m[dump_index];
            dump_n     = stored_n[dump_index];
            dump_data  = stored_data[dump_index];
        end else begin
            dump_valid = 0;
            dump_id    = 0;
            dump_m     = 0;
            dump_n     = 0;
            dump_data  = 0;
        end
    end

    // Summary counts combinational
    integer s;
    integer t;
    reg [3:0] dim_counts_comb [0:24];
    always @(*) begin
        for (s = 0; s < 25; s = s + 1) dim_counts_comb[s] = 0;
        for (t = 0; t < MAX_MATRICES; t = t + 1) begin
            if (stored_valid[t] && stored_m[t] != 0 && stored_n[t] != 0) begin
                dim_counts_comb[(stored_m[t]-1)*5 + (stored_n[t]-1)] = dim_counts_comb[(stored_m[t]-1)*5 + (stored_n[t]-1)] + 1'b1;
            end
        end
        for (s = 0; s < 25; s = s + 1) begin
            summary_counts[s*4 +: 4] = dim_counts_comb[s];
        end
    end

endmodule
