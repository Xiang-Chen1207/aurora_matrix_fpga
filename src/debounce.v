// ================================
// 防抖模块
// 修改点：保持按下0有效
// ================================
module debounce (
    input clk,
    input button_in,
    output reg button_out
);
    reg [19:0] count;
    reg button_sync;
    
    always @(posedge clk) begin
        button_sync <= button_in;
        if (button_sync != button_out) begin
            if (count == 20'd999_999) begin  // 10ms @ 100MHz
                button_out <= button_sync;
                count <= 0;
            end else begin
                count <= count + 1;
            end
        end else begin
            count <= 0;
        end
    end
endmodule