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
    
    // State Machine
    localparam IDLE = 0;
    localparam GENERATING = 1;
    localparam WAIT_STORE = 2; // Wait for storage to accept (1 cycle typically enough if valid handled right)
    localparam DONE = 3;
    
    reg [1:0] state;
    reg [3:0] generated_count;
    reg [2:0] row_idx;
    reg [2:0] col_idx;
    
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
            lfsr <= lfsr_next;
            
            case (state)
                IDLE: begin
                    gen_done <= 0;
                    gen_valid <= 0;
                    if (start) begin
                        state <= GENERATING;
                        generated_count <= 0;
                        row_idx <= 0;
                        col_idx <= 0;
                        gen_m <= m;
                        gen_n <= n;
                        gen_data <= 0;
                    end
                end
                
                GENERATING: begin
                    gen_valid <= 0;
                    // Generate one element per clock cycle or all at once?
                    // To be simple and robust, let's fill the register map 
                    // But we can just fill it instantly if we want, but filling 25 elements 
                    // from a single LFSR might need shifting.
                    // Let's do it per element to ensure randomness distribution (though 1 cycle is deterministic).
                    // Actually, for 5x5, we can just grab different slices of LFSR over time.
                    // Let's loop through rows and cols.
                    
                    // Generate a digit 0-9
                    // Simple mod 10 or check range. 
                    // Using lfsr % 10.
                    
                    // Sparse storage indexing: (row * 5 + col)
                    gen_data[(row_idx * 5 + col_idx) * 8 +: 8] <= (lfsr % 10);
                    
                    if (col_idx == n - 1) begin
                        col_idx <= 0;
                        if (row_idx == m - 1) begin
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
                    // Trigger storage write
                    gen_valid <= 1;
                    // Wait one cycle for valid signal to be registered by controller/storage
                    // Actually, if we hold valid high, the FSM/Storage should latch it.
                    // We need to move to next matrix or done.
                    
                    if (generated_count + 1 >= count) begin
                        state <= DONE;
                        generated_count <= generated_count + 1;
                    end else begin
                        // Need to generate next matrix
                        generated_count <= generated_count + 1;
                        row_idx <= 0;
                        col_idx <= 0;
                        gen_data <= 0;
                        state <= GENERATING;
                        // Important: deassert valid after one cycle so we don't write same matrix twice
                        // But here we transition to GENERATING which sets valid<=0 immediately.
                        // However, we need to make sure the receiver catches it.
                        // Assuming receiver is fast. Use a handshake if needed?
                        // For now, assume 1 cycle pulse is enough if receiver is always ready in GEN state.
                    end
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
