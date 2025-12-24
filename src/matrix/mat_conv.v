`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 卷积运算模块
// 功能：实现2D卷积运算
// 输入图像：10×12（从input_image_rom读取）
// 卷积核：3×3（用户输入）
// 步长：1
// 输出：8×10矩阵
// 计算：output[i][j] = Σ input[i+ki][j+kj] * kernel[ki][kj]
//////////////////////////////////////////////////////////////////////////////////
module mat_conv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,           // 开始计算信号
    input  wire [71:0] kernel,          // 3×3卷积核 (9×8bit = 72bit)
                                         // kernel[k] = kernel[(ki*3+kj)*8 +: 8]
    output reg  [639:0] result,         // 8×10输出矩阵 (80×8bit = 640bit)
    output reg  [31:0] cycle_count,     // 计算周期计数
    output reg         done             // 计算完成信号
);

    // 状态定义
    localparam IDLE       = 4'd0;
    localparam INIT       = 4'd1;
    localparam LOAD_IMG   = 4'd2;
    localparam WAIT_ROM   = 4'd3; // wait one cycle for synchronous ROM data
    localparam CALC       = 4'd4;
    localparam ACCUMULATE = 4'd5;
    localparam STORE      = 4'd6;
    localparam NEXT       = 4'd7;
    localparam DONE       = 4'd8;

    reg [3:0] state;
    reg [3:0] out_i, out_j;     // 输出位置 (0-7, 0-9)
    reg [1:0] k_i, k_j;         // 卷积核位置 (0-2, 0-2)
    reg [15:0] acc;             // 累加器
    reg [31:0] cycles;          // 周期计数器

    // ROM接口信号
    reg  [3:0] rom_x, rom_y;
    wire [3:0] rom_data;

    // 实例化输入图像ROM
    input_image_rom u_image_rom (
        .clk(clk),
        .x(rom_x),
        .y(rom_y),
        .data_out(rom_data)
    );

    // 提取卷积核元素
    wire [7:0] kernel_elem [0:2][0:2];
    assign kernel_elem[0][0] = kernel[7:0];
    assign kernel_elem[0][1] = kernel[15:8];
    assign kernel_elem[0][2] = kernel[23:16];
    assign kernel_elem[1][0] = kernel[31:24];
    assign kernel_elem[1][1] = kernel[39:32];
    assign kernel_elem[1][2] = kernel[47:40];
    assign kernel_elem[2][0] = kernel[55:48];
    assign kernel_elem[2][1] = kernel[63:56];
    assign kernel_elem[2][2] = kernel[71:64];

    // 当前卷积核元素
    reg [7:0] curr_kernel;
    reg [3:0] curr_img;
    reg [15:0] curr_product;

    // 存储读取的图像值
    reg [3:0] img_value;
    reg img_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            out_i <= 4'd0;
            out_j <= 4'd0;
            k_i <= 2'd0;
            k_j <= 2'd0;
            acc <= 16'd0;
            cycles <= 32'd0;
            cycle_count <= 32'd0;
            result <= 640'd0;
            rom_x <= 4'd0;
            rom_y <= 4'd0;
            img_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= INIT;
                        cycles <= 32'd0;
                        result <= 640'd0;
                        out_i <= 4'd0;
                        out_j <= 4'd0;
                    end
                end

                INIT: begin
                    // 初始化新的输出位置计算
                    k_i <= 2'd0;
                    k_j <= 2'd0;
                    acc <= 16'd0;
                    state <= LOAD_IMG;
                    cycles <= cycles + 1;
                end

                LOAD_IMG: begin
                    // 设置ROM地址：读取input[out_i + k_i][out_j + k_j]
                    rom_x <= out_i + k_i;
                    rom_y <= out_j + k_j;
                    img_valid <= 1'b0;
                    state <= WAIT_ROM;
                    cycles <= cycles + 1;
                end

                WAIT_ROM: begin
                    // 一拍等待同步ROM输出稳定
                    img_valid <= 1'b0;
                    state <= CALC;
                    cycles <= cycles + 1;
                end

                CALC: begin
                    // 读取ROM数据并选择卷积核元素
                    img_valid <= 1'b1;
                    img_value <= rom_data;

                    case ({k_i, k_j})
                        4'b00_00: curr_kernel <= kernel_elem[0][0];
                        4'b00_01: curr_kernel <= kernel_elem[0][1];
                        4'b00_10: curr_kernel <= kernel_elem[0][2];
                        4'b01_00: curr_kernel <= kernel_elem[1][0];
                        4'b01_01: curr_kernel <= kernel_elem[1][1];
                        4'b01_10: curr_kernel <= kernel_elem[1][2];
                        4'b10_00: curr_kernel <= kernel_elem[2][0];
                        4'b10_01: curr_kernel <= kernel_elem[2][1];
                        4'b10_10: curr_kernel <= kernel_elem[2][2];
                        default:  curr_kernel <= 8'd0;
                    endcase

                    state <= ACCUMULATE;
                    cycles <= cycles + 1;
                end

                ACCUMULATE: begin
                    // 累加：acc += input * kernel
                    acc <= acc + (img_value * curr_kernel);
                    cycles <= cycles + 1;

                    // 移动到下一个卷积核位置
                    if (k_j < 2'd2) begin
                        k_j <= k_j + 1'b1;
                        state <= LOAD_IMG;
                    end else if (k_i < 2'd2) begin
                        k_j <= 2'd0;
                        k_i <= k_i + 1'b1;
                        state <= LOAD_IMG;
                    end else begin
                        // 3×3卷积完成，存储结果
                        state <= STORE;
                    end
                end

                STORE: begin
                    // 存储结果到output[out_i][out_j]
                    // 输出矩阵8×10，索引 = (out_i * 10 + out_j) * 8
                    case (out_i * 10 + out_j)
                        7'd0:  result[7:0]     <= acc[7:0];
                        7'd1:  result[15:8]    <= acc[7:0];
                        7'd2:  result[23:16]   <= acc[7:0];
                        7'd3:  result[31:24]   <= acc[7:0];
                        7'd4:  result[39:32]   <= acc[7:0];
                        7'd5:  result[47:40]   <= acc[7:0];
                        7'd6:  result[55:48]   <= acc[7:0];
                        7'd7:  result[63:56]   <= acc[7:0];
                        7'd8:  result[71:64]   <= acc[7:0];
                        7'd9:  result[79:72]   <= acc[7:0];
                        7'd10: result[87:80]   <= acc[7:0];
                        7'd11: result[95:88]   <= acc[7:0];
                        7'd12: result[103:96]  <= acc[7:0];
                        7'd13: result[111:104] <= acc[7:0];
                        7'd14: result[119:112] <= acc[7:0];
                        7'd15: result[127:120] <= acc[7:0];
                        7'd16: result[135:128] <= acc[7:0];
                        7'd17: result[143:136] <= acc[7:0];
                        7'd18: result[151:144] <= acc[7:0];
                        7'd19: result[159:152] <= acc[7:0];
                        7'd20: result[167:160] <= acc[7:0];
                        7'd21: result[175:168] <= acc[7:0];
                        7'd22: result[183:176] <= acc[7:0];
                        7'd23: result[191:184] <= acc[7:0];
                        7'd24: result[199:192] <= acc[7:0];
                        7'd25: result[207:200] <= acc[7:0];
                        7'd26: result[215:208] <= acc[7:0];
                        7'd27: result[223:216] <= acc[7:0];
                        7'd28: result[231:224] <= acc[7:0];
                        7'd29: result[239:232] <= acc[7:0];
                        7'd30: result[247:240] <= acc[7:0];
                        7'd31: result[255:248] <= acc[7:0];
                        7'd32: result[263:256] <= acc[7:0];
                        7'd33: result[271:264] <= acc[7:0];
                        7'd34: result[279:272] <= acc[7:0];
                        7'd35: result[287:280] <= acc[7:0];
                        7'd36: result[295:288] <= acc[7:0];
                        7'd37: result[303:296] <= acc[7:0];
                        7'd38: result[311:304] <= acc[7:0];
                        7'd39: result[319:312] <= acc[7:0];
                        7'd40: result[327:320] <= acc[7:0];
                        7'd41: result[335:328] <= acc[7:0];
                        7'd42: result[343:336] <= acc[7:0];
                        7'd43: result[351:344] <= acc[7:0];
                        7'd44: result[359:352] <= acc[7:0];
                        7'd45: result[367:360] <= acc[7:0];
                        7'd46: result[375:368] <= acc[7:0];
                        7'd47: result[383:376] <= acc[7:0];
                        7'd48: result[391:384] <= acc[7:0];
                        7'd49: result[399:392] <= acc[7:0];
                        7'd50: result[407:400] <= acc[7:0];
                        7'd51: result[415:408] <= acc[7:0];
                        7'd52: result[423:416] <= acc[7:0];
                        7'd53: result[431:424] <= acc[7:0];
                        7'd54: result[439:432] <= acc[7:0];
                        7'd55: result[447:440] <= acc[7:0];
                        7'd56: result[455:448] <= acc[7:0];
                        7'd57: result[463:456] <= acc[7:0];
                        7'd58: result[471:464] <= acc[7:0];
                        7'd59: result[479:472] <= acc[7:0];
                        7'd60: result[487:480] <= acc[7:0];
                        7'd61: result[495:488] <= acc[7:0];
                        7'd62: result[503:496] <= acc[7:0];
                        7'd63: result[511:504] <= acc[7:0];
                        7'd64: result[519:512] <= acc[7:0];
                        7'd65: result[527:520] <= acc[7:0];
                        7'd66: result[535:528] <= acc[7:0];
                        7'd67: result[543:536] <= acc[7:0];
                        7'd68: result[551:544] <= acc[7:0];
                        7'd69: result[559:552] <= acc[7:0];
                        7'd70: result[567:560] <= acc[7:0];
                        7'd71: result[575:568] <= acc[7:0];
                        7'd72: result[583:576] <= acc[7:0];
                        7'd73: result[591:584] <= acc[7:0];
                        7'd74: result[599:592] <= acc[7:0];
                        7'd75: result[607:600] <= acc[7:0];
                        7'd76: result[615:608] <= acc[7:0];
                        7'd77: result[623:616] <= acc[7:0];
                        7'd78: result[631:624] <= acc[7:0];
                        7'd79: result[639:632] <= acc[7:0];
                        default: ;
                    endcase

                    state <= NEXT;
                    cycles <= cycles + 1;
                end

                NEXT: begin
                    // 移动到下一个输出位置
                    if (out_j < 4'd9) begin
                        out_j <= out_j + 1'b1;
                        state <= INIT;
                    end else if (out_i < 4'd7) begin
                        out_j <= 4'd0;
                        out_i <= out_i + 1'b1;
                        state <= INIT;
                    end else begin
                        // 全部完成
                        state <= DONE;
                    end
                    cycles <= cycles + 1;
                end

                DONE: begin
                    done <= 1'b1;
                    cycle_count <= cycles;
                    if (!start) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
