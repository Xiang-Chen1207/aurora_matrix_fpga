`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_gen
// Description: Random Matrix Generator using LFSR
// Features:
// - Generates matrices with random elements (0-9)
// - Supports generating 1 or 2 matrices based on user input
// - Uses 16-bit LFSR for pseudo-random number generation
//////////////////////////////////////////////////////////////////////////////////

module matrix_gen(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [2:0] m,
    input wire [2:0] n,
    input wire [3:0] count,  // 1 or 2
    
    output reg [2:0] gen_m,
    output reg [2:0] gen_n,
    output reg [199:0] gen_data,
    output reg gen_valid,
    output reg gen_done
);

    // LFSR for Random Number Generation
    reg [15:0] lfsr;
    wire [15:0] lfsr_next;

    // Xorshift or simple tap feedback
    // Tap for 16-bit: 16, 14, 13, 11 (indices 15, 13, 12, 10)
    wire feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    assign lfsr_next = {lfsr[14:0], feedback};

    // Extra de-correlation: advance LFSR several steps before using the value
    // This reduces adjacency correlation between successive elements.
    function [15:0] advance_lfsr_multi;
        input [15:0] seed;
        integer k;
        reg [15:0] tmp;
        begin
            tmp = seed;
            for (k = 0; k < 4; k = k + 1) begin
                tmp = {tmp[14:0], (tmp[15] ^ tmp[13] ^ tmp[12] ^ tmp[10])};
            end
            advance_lfsr_multi = tmp;
        end
    endfunction

    // One-step + multi-step advance for use per element
    wire [15:0] rng_advance = advance_lfsr_multi(lfsr_next);
    
    // State Machine
    localparam IDLE = 0;
    localparam GENERATING = 1;
    localparam WAIT_STORE = 2; // Pulse valid for current matrix
    localparam PREP_NEXT = 3;  // Clear buffer before next matrix
    localparam DONE = 4;
    
    reg [3:0] state;
    reg [3:0] generated_count; // counts matrices actually handed to storage
    reg [2:0] row_idx;
    reg [2:0] col_idx;

    // 有效维度钳位到 1..5，避免 0 或 >5 导致下溢/越界
    wire [2:0] eff_m = (m == 0) ? 3'd1 : (m > 3'd5 ? 3'd5 : m);
    wire [2:0] eff_n = (n == 0) ? 3'd1 : (n > 3'd5 ? 3'd5 : n);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 16'hACE1; // Non-zero seed
            state <= IDLE;
            gen_valid <= 0;
            gen_done <= 0;
            gen_m <= 0;
            gen_n <= 0;
            gen_data <= 0;
            generated_count <= 0;
            row_idx <= 0;
            col_idx <= 0;
        end else begin
            case (state)
                IDLE: begin
                    gen_done <= 0;
                    gen_valid <= 0;
                    if (start) begin
                        // Reseed using dimensions/count; ensures first matrix not all zeros
                        // If xor accidentally hits 0, fall back to non-zero seed mix.
                        if ((lfsr ^ {5'h1F, eff_m, eff_n, count}) == 16'd0)
                            lfsr <= (16'hACE1 ^ {5'h1F, eff_m, eff_n, count});
                        else
                            lfsr <= (lfsr ^ {5'h1F, eff_m, eff_n, count});
                        state <= GENERATING;
                        generated_count <= 0;
                        row_idx <= 0;
                        col_idx <= 0;
                        gen_m <= eff_m;
                        gen_n <= eff_n;
                        gen_data <= 0;
                    end else begin
                        // Keep LFSR alive in idle to avoid correlation across runs
                        if (lfsr_next == 16'd0)
                            lfsr <= (16'hACE1 ^ {5'h1F, eff_m, eff_n, count});
                        else
                            lfsr <= lfsr_next;
                    end
                end
                
                GENERATING: begin
                    gen_valid <= 0;
                    // Advance LFSR and use the new value for this element to avoid stale/zero first samples
                    // Guard against all-zero state by reseeding if needed.
                    begin : advance_block
                        reg [15:0] next_val;
                        next_val = rng_advance;
                        if (rng_advance == 16'd0)
                            next_val = 16'hACE1 ^ {5'h1F, eff_m, eff_n, count};
                        lfsr <= next_val;
                        gen_data[(row_idx * 5 + col_idx) * 8 +: 8] <= (next_val % 10);
                    end

                    if (col_idx == eff_n - 1) begin
                        col_idx <= 0;
                        if (row_idx == eff_m - 1) begin
                            // Matrix full
                            state <= WAIT_STORE;
                        end else begin
                            row_idx <= row_idx + 1;
                        end
                    end else begin
                        col_idx <= col_idx + 1;
                    end
                end
                
                WAIT_STORE: begin
                    // Pulse write for the filled matrix
                    gen_valid <= 1;

                    if (generated_count + 1 >= count) begin
                        generated_count <= generated_count + 1;
                        state <= DONE;
                    end else begin
                        // Need to generate next matrix
                        generated_count <= generated_count + 1;
                        state <= PREP_NEXT;
                        // Important: deassert valid after one cycle so we don't write same matrix twice
                        // But here we transition to GENERATING which sets valid<=0 immediately.
                        // However, we need to make sure the receiver catches it.
                        // Assuming receiver is fast. Use a handshake if needed?
                        // For now, assume 1 cycle pulse is enough if receiver is always ready in GEN state.
                    end
                end

                PREP_NEXT: begin
                    // Drop valid and clear buffer after storage captured the matrix
                    gen_valid <= 0;
                    gen_data <= 0;
                    row_idx <= 0;
                    col_idx <= 0;
                    state <= GENERATING;
                end
                
                DONE: begin
                    gen_valid <= 0;
                    gen_done <= 1;
                    if (!start) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
