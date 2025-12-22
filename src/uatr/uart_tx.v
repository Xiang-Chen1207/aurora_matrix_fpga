`timescale 1ns / 1ps
module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire tx_start,
    input wire [7:0] tx_data,
    output reg tx,
    output reg tx_busy
);

    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;
    reg [15:0] baud_cnt;
    reg [3:0] bit_idx;
    reg [9:0] tx_shift;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            baud_cnt <= 0;
            bit_idx <= 0;
            tx_shift <= 10'b1111111111;
            tx <= 1'b1;
            tx_busy <= 0;
        end else begin
            if(tx_start && !tx_busy) begin
                tx_shift <= {1'b1, tx_data, 1'b0};
                tx_busy <= 1;
                baud_cnt <= 0;
                bit_idx <= 0;
            end else if(tx_busy) begin
                if(baud_cnt < BAUD_DIV-1) begin
                    baud_cnt <= baud_cnt + 1;
                end else begin
                    baud_cnt <= 0;
                    tx <= tx_shift[0];
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    bit_idx <= bit_idx + 1;
                    if(bit_idx == 9)
                        tx_busy <= 0;
                end
            end
        end
    end
endmodule
