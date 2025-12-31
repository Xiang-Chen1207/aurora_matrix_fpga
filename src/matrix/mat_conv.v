`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名称: mat_conv (2D卷积运算模块)
// 功能描述: 实现2D卷积运算，常用于图像处理和神经网络
// 输入规格:
//   - 输入图像：10×12（固定，从input_image_rom读取）
//   - 卷积核：3×3（用户输入，72位 = 9×8bit）
//   - 步长(stride)：1
// 输出规格:
//   - 输出矩阵：8×10（= (10-3+1) × (12-3+1)）
//   - 640位 = 80个元素 × 8bit
// 计算公式: output[i][j] = Σ Σ input[i+ki][j+kj] × kernel[ki][kj]
//           其中 ki,kj ∈ {0,1,2}
//////////////////////////////////////////////////////////////////////////////////

module mat_conv (
    //==================== 输入端口 ====================
    input  wire        clk,             // 系统时钟信号，上升沿触发
    input  wire        rst_n,           // 异步复位信号，低电平有效
    input  wire        start,           // 开始计算信号，高电平触发计算
    input  wire [71:0] kernel,          // 3×3卷积核，72位 (9个元素 × 8bit)
                                        // kernel[k] = kernel[(ki*3+kj)*8 +: 8]
                                        // 存储顺序：[0][0], [0][1], [0][2], [1][0], ...

    //==================== 输出端口 ====================
    output reg  [639:0] result,         // 8×10输出矩阵 (80个元素 × 8bit = 640bit)
                                        // result[idx] = result[(i*10+j)*8 +: 8]
    output reg  [31:0] cycle_count,     // 计算周期计数器，用于性能分析
    output reg         done             // 计算完成标志，高电平表示计算完成
);

    //==================== 状态机状态定义 ====================
    // 卷积运算需要9个状态来处理复杂的多级流水线操作
    localparam IDLE       = 4'd0;       // 空闲状态：等待start信号
    localparam INIT       = 4'd1;       // 初始化状态：准备新输出位置的计算
    localparam LOAD_IMG   = 4'd2;       // 加载状态：设置ROM地址
    localparam WAIT_ROM   = 4'd3;       // 等待状态：等待同步ROM数据稳定（关键！）
    localparam CALC       = 4'd4;       // 计算状态：读取ROM数据，选择卷积核元素
    localparam ACCUMULATE = 4'd5;       // 累加状态：执行乘加运算
    localparam STORE      = 4'd6;       // 存储状态：保存累加结果到输出矩阵
    localparam NEXT       = 4'd7;       // 下一个状态：移动到下一输出位置
    localparam DONE       = 4'd8;       // 完成状态：输出完成信号

    //==================== 内部寄存器定义 ====================
    reg [3:0] state;                    // 状态寄存器，4位可表示9个状态
    reg [3:0] out_i, out_j;             // 输出矩阵位置索引 (out_i: 0-7, out_j: 0-9)
    reg [1:0] k_i, k_j;                 // 卷积核位置索引 (k_i, k_j: 0-2)
    reg [15:0] acc;                     // 16位累加器，存储单个输出元素的累加和
    reg [31:0] cycles;                  // 周期计数器，记录计算所用时钟周期

    //==================== ROM接口信号 ====================
    reg  [3:0] rom_x, rom_y;            // ROM地址：rom_x为行(0-9)，rom_y为列(0-11)
    wire [3:0] rom_data;                // ROM输出数据：4位像素值(0-9)

    //==================== 实例化输入图像ROM ====================
    // ROM存储固定的10×12测试图像
    input_image_rom u_image_rom (
        .clk(clk),                      // 时钟信号
        .x(rom_x),                      // 行地址输入
        .y(rom_y),                      // 列地址输入
        .data_out(rom_data)             // 像素值输出（同步输出，需要等待一个时钟周期）
    );

    //==================== 卷积核元素预提取 ====================
    // 将72位扁平化卷积核解析为3×3的二维数组，便于索引访问
    wire [7:0] kernel_elem [0:2][0:2];
    // 第0行卷积核元素
    assign kernel_elem[0][0] = kernel[7:0];     // kernel[0][0] - 左上角
    assign kernel_elem[0][1] = kernel[15:8];    // kernel[0][1] - 上中
    assign kernel_elem[0][2] = kernel[23:16];   // kernel[0][2] - 右上角
    // 第1行卷积核元素
    assign kernel_elem[1][0] = kernel[31:24];   // kernel[1][0] - 左中
    assign kernel_elem[1][1] = kernel[39:32];   // kernel[1][1] - 中心
    assign kernel_elem[1][2] = kernel[47:40];   // kernel[1][2] - 右中
    // 第2行卷积核元素
    assign kernel_elem[2][0] = kernel[55:48];   // kernel[2][0] - 左下角
    assign kernel_elem[2][1] = kernel[63:56];   // kernel[2][1] - 下中
    assign kernel_elem[2][2] = kernel[71:64];   // kernel[2][2] - 右下角

    //==================== 中间计算寄存器 ====================
    reg [7:0] curr_kernel;              // 当前选中的卷积核元素
    reg [3:0] curr_img;                 // 当前读取的图像像素值（实际未使用，可优化）
    reg [15:0] curr_product;            // 当前乘积（实际未使用，可优化）

    //==================== 图像数据读取控制 ====================
    reg [3:0] img_value;                // 存储从ROM读取的像素值
    reg img_valid;                      // 图像数据有效标志（实际未使用，可优化）

    //==================== 主状态机：时序逻辑 ====================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            //---------- 异步复位：初始化所有寄存器 ----------
            state <= IDLE;              // 状态机回到空闲状态
            done <= 1'b0;               // 清除完成标志
            out_i <= 4'd0;              // 输出行索引清零
            out_j <= 4'd0;              // 输出列索引清零
            k_i <= 2'd0;                // 卷积核行索引清零
            k_j <= 2'd0;                // 卷积核列索引清零
            acc <= 16'd0;               // 累加器清零
            cycles <= 32'd0;            // 周期计数器清零
            cycle_count <= 32'd0;       // 输出周期计数清零
            result <= 640'd0;           // 结果矩阵清零
            rom_x <= 4'd0;              // ROM行地址清零
            rom_y <= 4'd0;              // ROM列地址清零
            img_valid <= 1'b0;          // 图像有效标志清零
        end else begin
            case (state)
                //========== IDLE状态：等待开始信号 ==========
                IDLE: begin
                    done <= 1'b0;               // 清除上一次的完成标志
                    if (start) begin            // 检测到start信号
                        state <= INIT;          // 转移到初始化状态
                        cycles <= 32'd0;        // 重置周期计数器
                        result <= 640'd0;       // 清空结果矩阵
                        out_i <= 4'd0;          // 初始化输出行索引
                        out_j <= 4'd0;          // 初始化输出列索引
                    end
                end

                //========== INIT状态：初始化新输出位置的计算 ==========
                // 每计算一个输出元素前，都需要初始化卷积核索引和累加器
                INIT: begin
                    k_i <= 2'd0;                // 卷积核行索引归零
                    k_j <= 2'd0;                // 卷积核列索引归零
                    acc <= 16'd0;               // 累加器清零
                    state <= LOAD_IMG;          // 转移到加载图像状态
                    cycles <= cycles + 1;       // 周期计数加1
                end

                //========== LOAD_IMG状态：设置ROM读取地址 ==========
                // 计算当前需要读取的图像位置：input[out_i + k_i][out_j + k_j]
                LOAD_IMG: begin
                    // ROM地址 = 输出位置 + 卷积核偏移
                    rom_x <= out_i + k_i;       // 图像行地址 = 输出行 + 核行偏移
                    rom_y <= out_j + k_j;       // 图像列地址 = 输出列 + 核列偏移
                    img_valid <= 1'b0;          // 标记数据尚未有效
                    state <= WAIT_ROM;          // 转移到等待ROM状态
                    cycles <= cycles + 1;       // 周期计数加1
                end

                //========== WAIT_ROM状态：等待同步ROM输出稳定 ==========
                // 【关键设计】因为ROM是同步读取的，需要等待一个时钟周期
                // 地址在LOAD_IMG设置，数据在下一个时钟上升沿才有效
                WAIT_ROM: begin
                    img_valid <= 1'b0;          // 数据仍未有效
                    state <= CALC;              // 转移到计算状态
                    cycles <= cycles + 1;       // 周期计数加1
                end

                //========== CALC状态：读取ROM数据并选择卷积核元素 ==========
                CALC: begin
                    img_valid <= 1'b1;          // 此时ROM数据已稳定有效
                    img_value <= rom_data;      // 保存读取的像素值

                    // 根据当前卷积核位置选择对应的核元素
                    // 使用{k_i, k_j}拼接成4位索引进行case匹配
                    case ({k_i, k_j})
                        4'b00_00: curr_kernel <= kernel_elem[0][0];  // 左上角
                        4'b00_01: curr_kernel <= kernel_elem[0][1];  // 上中
                        4'b00_10: curr_kernel <= kernel_elem[0][2];  // 右上角
                        4'b01_00: curr_kernel <= kernel_elem[1][0];  // 左中
                        4'b01_01: curr_kernel <= kernel_elem[1][1];  // 中心
                        4'b01_10: curr_kernel <= kernel_elem[1][2];  // 右中
                        4'b10_00: curr_kernel <= kernel_elem[2][0];  // 左下角
                        4'b10_01: curr_kernel <= kernel_elem[2][1];  // 下中
                        4'b10_10: curr_kernel <= kernel_elem[2][2];  // 右下角
                        default:  curr_kernel <= 8'd0;               // 默认值
                    endcase

                    state <= ACCUMULATE;        // 转移到累加状态
                    cycles <= cycles + 1;       // 周期计数加1
                end

                //========== ACCUMULATE状态：执行乘加运算 ==========
                ACCUMULATE: begin
                    // 累加：acc = acc + 图像像素值 × 卷积核元素
                    // img_value是4位(0-9)，curr_kernel是8位
                    // 乘积最大 = 9 × 255 = 2295，用16位足够
                    acc <= acc + (img_value * curr_kernel);
                    cycles <= cycles + 1;       // 周期计数加1

                    // 移动到下一个卷积核位置
                    if (k_j < 2'd2) begin
                        // 当前行还有更多列
                        k_j <= k_j + 1'b1;      // 列索引加1
                        state <= LOAD_IMG;      // 返回加载图像状态
                    end else if (k_i < 2'd2) begin
                        // 当前行完成，移到下一行
                        k_j <= 2'd0;            // 列索引归零
                        k_i <= k_i + 1'b1;      // 行索引加1
                        state <= LOAD_IMG;      // 返回加载图像状态
                    end else begin
                        // 3×3卷积核遍历完成，准备存储结果
                        state <= STORE;
                    end
                end

                //========== STORE状态：存储累加结果到输出矩阵 ==========
                STORE: begin
                    // 计算输出矩阵的线性索引：idx = out_i × 10 + out_j
                    // 输出矩阵是8×10，共80个元素
                    // 使用case语句展开所有80种情况
                    case (out_i * 10 + out_j)
                        // 第0行输出 (索引0-9)
                        7'd0:  result[7:0]     <= acc[7:0];   // output[0][0]
                        7'd1:  result[15:8]    <= acc[7:0];   // output[0][1]
                        7'd2:  result[23:16]   <= acc[7:0];   // output[0][2]
                        7'd3:  result[31:24]   <= acc[7:0];   // output[0][3]
                        7'd4:  result[39:32]   <= acc[7:0];   // output[0][4]
                        7'd5:  result[47:40]   <= acc[7:0];   // output[0][5]
                        7'd6:  result[55:48]   <= acc[7:0];   // output[0][6]
                        7'd7:  result[63:56]   <= acc[7:0];   // output[0][7]
                        7'd8:  result[71:64]   <= acc[7:0];   // output[0][8]
                        7'd9:  result[79:72]   <= acc[7:0];   // output[0][9]
                        // 第1行输出 (索引10-19)
                        7'd10: result[87:80]   <= acc[7:0];   // output[1][0]
                        7'd11: result[95:88]   <= acc[7:0];   // output[1][1]
                        7'd12: result[103:96]  <= acc[7:0];   // output[1][2]
                        7'd13: result[111:104] <= acc[7:0];   // output[1][3]
                        7'd14: result[119:112] <= acc[7:0];   // output[1][4]
                        7'd15: result[127:120] <= acc[7:0];   // output[1][5]
                        7'd16: result[135:128] <= acc[7:0];   // output[1][6]
                        7'd17: result[143:136] <= acc[7:0];   // output[1][7]
                        7'd18: result[151:144] <= acc[7:0];   // output[1][8]
                        7'd19: result[159:152] <= acc[7:0];   // output[1][9]
                        // 第2行输出 (索引20-29)
                        7'd20: result[167:160] <= acc[7:0];   // output[2][0]
                        7'd21: result[175:168] <= acc[7:0];   // output[2][1]
                        7'd22: result[183:176] <= acc[7:0];   // output[2][2]
                        7'd23: result[191:184] <= acc[7:0];   // output[2][3]
                        7'd24: result[199:192] <= acc[7:0];   // output[2][4]
                        7'd25: result[207:200] <= acc[7:0];   // output[2][5]
                        7'd26: result[215:208] <= acc[7:0];   // output[2][6]
                        7'd27: result[223:216] <= acc[7:0];   // output[2][7]
                        7'd28: result[231:224] <= acc[7:0];   // output[2][8]
                        7'd29: result[239:232] <= acc[7:0];   // output[2][9]
                        // 第3行输出 (索引30-39)
                        7'd30: result[247:240] <= acc[7:0];   // output[3][0]
                        7'd31: result[255:248] <= acc[7:0];   // output[3][1]
                        7'd32: result[263:256] <= acc[7:0];   // output[3][2]
                        7'd33: result[271:264] <= acc[7:0];   // output[3][3]
                        7'd34: result[279:272] <= acc[7:0];   // output[3][4]
                        7'd35: result[287:280] <= acc[7:0];   // output[3][5]
                        7'd36: result[295:288] <= acc[7:0];   // output[3][6]
                        7'd37: result[303:296] <= acc[7:0];   // output[3][7]
                        7'd38: result[311:304] <= acc[7:0];   // output[3][8]
                        7'd39: result[319:312] <= acc[7:0];   // output[3][9]
                        // 第4行输出 (索引40-49)
                        7'd40: result[327:320] <= acc[7:0];   // output[4][0]
                        7'd41: result[335:328] <= acc[7:0];   // output[4][1]
                        7'd42: result[343:336] <= acc[7:0];   // output[4][2]
                        7'd43: result[351:344] <= acc[7:0];   // output[4][3]
                        7'd44: result[359:352] <= acc[7:0];   // output[4][4]
                        7'd45: result[367:360] <= acc[7:0];   // output[4][5]
                        7'd46: result[375:368] <= acc[7:0];   // output[4][6]
                        7'd47: result[383:376] <= acc[7:0];   // output[4][7]
                        7'd48: result[391:384] <= acc[7:0];   // output[4][8]
                        7'd49: result[399:392] <= acc[7:0];   // output[4][9]
                        // 第5行输出 (索引50-59)
                        7'd50: result[407:400] <= acc[7:0];   // output[5][0]
                        7'd51: result[415:408] <= acc[7:0];   // output[5][1]
                        7'd52: result[423:416] <= acc[7:0];   // output[5][2]
                        7'd53: result[431:424] <= acc[7:0];   // output[5][3]
                        7'd54: result[439:432] <= acc[7:0];   // output[5][4]
                        7'd55: result[447:440] <= acc[7:0];   // output[5][5]
                        7'd56: result[455:448] <= acc[7:0];   // output[5][6]
                        7'd57: result[463:456] <= acc[7:0];   // output[5][7]
                        7'd58: result[471:464] <= acc[7:0];   // output[5][8]
                        7'd59: result[479:472] <= acc[7:0];   // output[5][9]
                        // 第6行输出 (索引60-69)
                        7'd60: result[487:480] <= acc[7:0];   // output[6][0]
                        7'd61: result[495:488] <= acc[7:0];   // output[6][1]
                        7'd62: result[503:496] <= acc[7:0];   // output[6][2]
                        7'd63: result[511:504] <= acc[7:0];   // output[6][3]
                        7'd64: result[519:512] <= acc[7:0];   // output[6][4]
                        7'd65: result[527:520] <= acc[7:0];   // output[6][5]
                        7'd66: result[535:528] <= acc[7:0];   // output[6][6]
                        7'd67: result[543:536] <= acc[7:0];   // output[6][7]
                        7'd68: result[551:544] <= acc[7:0];   // output[6][8]
                        7'd69: result[559:552] <= acc[7:0];   // output[6][9]
                        // 第7行输出 (索引70-79)
                        7'd70: result[567:560] <= acc[7:0];   // output[7][0]
                        7'd71: result[575:568] <= acc[7:0];   // output[7][1]
                        7'd72: result[583:576] <= acc[7:0];   // output[7][2]
                        7'd73: result[591:584] <= acc[7:0];   // output[7][3]
                        7'd74: result[599:592] <= acc[7:0];   // output[7][4]
                        7'd75: result[607:600] <= acc[7:0];   // output[7][5]
                        7'd76: result[615:608] <= acc[7:0];   // output[7][6]
                        7'd77: result[623:616] <= acc[7:0];   // output[7][7]
                        7'd78: result[631:624] <= acc[7:0];   // output[7][8]
                        7'd79: result[639:632] <= acc[7:0];   // output[7][9]
                        default: ;  // 默认不操作
                    endcase

                    state <= NEXT;              // 转移到下一个状态
                    cycles <= cycles + 1;       // 周期计数加1
                end

                //========== NEXT状态：移动到下一个输出位置 ==========
                NEXT: begin
                    // 判断是否还有更多输出位置需要计算
                    if (out_j < 4'd9) begin
                        // 当前行还有更多列（输出矩阵宽度为10）
                        out_j <= out_j + 1'b1;  // 列索引加1
                        state <= INIT;          // 返回初始化状态
                    end else if (out_i < 4'd7) begin
                        // 当前行完成，移到下一行（输出矩阵高度为8）
                        out_j <= 4'd0;          // 列索引归零
                        out_i <= out_i + 1'b1;  // 行索引加1
                        state <= INIT;          // 返回初始化状态
                    end else begin
                        // 所有80个输出元素计算完成
                        state <= DONE;
                    end
                    cycles <= cycles + 1;       // 周期计数加1
                end

                //========== DONE状态：输出完成信号 ==========
                DONE: begin
                    done <= 1'b1;               // 设置完成标志
                    cycle_count <= cycles;      // 输出最终周期计数
                    // 握手协议：等待start信号撤销
                    if (!start) begin
                        state <= IDLE;          // 返回空闲状态
                    end
                end

                //========== 默认状态：异常恢复 ==========
                default: state <= IDLE;         // 异常时回到空闲状态
            endcase
        end
    end

endmodule
