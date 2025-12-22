// File: defs.vh
// 矩阵计算工程的全局参数定义
// 使用方法：在.v文件中包含：`include "defs.vh"

// 矩阵维度（行/列）
`define MATRIX_MAX_SIZE           4       // 支持4x4矩阵
`define MATRIX_WIDTH              8       // 矩阵每个元素为8-bit数据

// UART配置
`define UART_BAUD                 115200  // 串口波特率
`define CLK_FREQ                  100_000_000  // FPGA系统时钟100MHz

// ========== 状态机定义 ==========（关键修改）
`define STATE_WIDTH               4       // 状态机状态位宽度
`define STATE_IDLE                4'd0    // 空闲状态
`define STATE_MENU                4'd1    // 菜单显示
`define STATE_INPUT               4'd2    // 用户输入
`define STATE_GENERATE            4'd3    // 生成随机矩阵
`define STATE_DISPLAY             4'd4    // 显示结果
`define STATE_COMPUTE             4'd5    // 计算执行
`define STATE_ERROR               4'd6    // 系统错误
`define STATE_STORE               4'd7    // 存储数据
`define STATE_SELECT              4'd8    // 选择操作数
`define STATE_WAIT                4'd9    // 倒计时等待

// 相关参数定义（可扩展）
`define DEBOUNCE_DELAY            20_000_000   // 按键消抖延迟

// UART相关参数
`define UART_START_BIT            1'b0
`define UART_STOP_BIT             1'b1
`define UART_DATA_BITS            8
`define UART_PARITY_ENABLE        0

// UART控制状态
`define UART_IDLE          2'd0
`define UART_PARSING       2'd1  
`define UART_DISPLAYING    2'd2
`define UART_ERROR         2'd3

// 矩阵存储配置
`define MAX_MATRICES_PER_SIZE 2    // 每种规格最多存储2个矩阵
`define MAX_MATRIX_DIM        5    // 最大矩阵维度5×5

// 操作类型编码
`define OP_TRANSPOSE       4'b0001
`define OP_ADD             4'b0010  
`define OP_SCALAR_MULT     4'b0100
`define OP_MAT_MULT        4'b1000