`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_system_flow
// Description:
//   System-level testbench for matrix_calc_top_v2.
//   Simulates the flow: UART matrix input -> store -> select transpose op
//   -> select matrix by dim/ID -> compute -> UART output result.
//////////////////////////////////////////////////////////////////////////////////

module tb_system_flow;

    // Clock/Reset
    reg clk;
    reg rst;          // active high

    // Top-level IO
    reg  [7:0] sw;
    reg        btn_confirm;
    reg        uart_rx;
    wire       uart_tx;
    wire [7:0] leds;
    wire [6:0] seg;
    wire [7:0] an;

    // Clock generation: 100 MHz
    localparam CLK_PERIOD = 10; // ns
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Instantiate DUT
    matrix_calc_top_v2 dut (
        .clk(clk),
        .rst(rst),
        .sw(sw),
        .btn_confirm(btn_confirm),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .leds(leds),
        .seg(seg),
        .an(an)
    );

    // UART TX task (driving DUT.uart_rx)
    // Matches uart_rx parameters: CLK_FREQ=100MHz, BAUD_RATE=115200 => BAUD_DIV=868
    localparam integer BAUD_DIV = 868;

    // UART RX monitor (listening to DUT.uart_tx) using the same uart_rx RTL for correct sampling
    reg [7:0] rx_buf [0:1023];
    integer rx_ptr = 0;
    integer rx_total = 0;
    integer k;
    integer match;
    integer last_state;
    integer start_idx;
    wire [7:0] mon_rx_data;
    wire mon_rx_done;

    // Optional expected bytes for auto-check (matrix data is left-aligned to width 4 per element)
    reg [7:0] expected [0:255];
    integer expected_len = 0; // set >0 to enable compare
    initial begin
        expected_len = 18; // transpose of [[1,2],[3,4]] => "1   3   \n2   4   \n"
        expected[0]  = "1"; expected[1]  = " "; expected[2]  = " "; expected[3]  = " ";
        expected[4]  = "3"; expected[5]  = " "; expected[6]  = " "; expected[7]  = " ";
        expected[8]  = 8'h0A; // LF
        expected[9]  = "2"; expected[10] = " "; expected[11] = " "; expected[12] = " ";
        expected[13] = "4"; expected[14] = " "; expected[15] = " "; expected[16] = " ";
        expected[17] = 8'h0A; // LF
    end

    // Use real uart_rx RTL for monitoring uart_tx to avoid sampling drift
    uart_rx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) u_uart_rx_mon (
        .clk(clk),
        .rst_n(~rst),
        .rx(uart_tx),
        .rx_data(mon_rx_data),
        .rx_done(mon_rx_done)
    );

    always @(posedge clk) begin
        if (mon_rx_done) begin
            rx_buf[rx_ptr] <= mon_rx_data;
            rx_ptr <= rx_ptr + 1;
            rx_total <= rx_total + 1;
            $write("[UART_RX] 0x%02h (%c)\n", mon_rx_data, mon_rx_data);
        end
    end

    task uart_send_byte(input [7:0] data);
        integer i;
    begin
        // start bit (low)
        uart_rx <= 1'b0;
        repeat(BAUD_DIV) @(posedge clk);

        // data bits, LSB first
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx <= data[i];
            repeat(BAUD_DIV) @(posedge clk);
        end

        // stop bit (high)
        uart_rx <= 1'b1;
        repeat(BAUD_DIV) @(posedge clk);
    end
    endtask

    task uart_send_string(input [8*128-1:0] str, input integer len);
        integer idx;
    begin
        for (idx = 0; idx < len; idx = idx + 1) begin
            uart_send_byte(str[8*idx +: 8]);
        end
    end
    endtask

    // Helper: pulse confirm button
    task pulse_confirm;
    begin
        // Hold >10ms to pass debounce (counts 1_000_000 cycles @100MHz)
        btn_confirm <= 1'b1;
        repeat(1_200_000) @(posedge clk); // 12ms high
        btn_confirm <= 1'b0;
        repeat(100_000) @(posedge clk);   // 1ms low gap
    end
    endtask

    // Main stimulus
    initial begin
        // Bypass debounce in sim: drive debounced signal directly
        force dut.btn_debounced = btn_confirm;
        // Init
        sw          = 8'h00;
        btn_confirm = 1'b0;
        uart_rx     = 1'b1; // idle high
        rst         = 1'b1;

        // Hold reset
        repeat(20) @(posedge clk);
        rst = 1'b0;
        repeat(50) @(posedge clk);

        // ==========================
        // 1) ???????????? (??1)
        //    ??? UART ????: 2x2 ???? {{1,2},{3,4}}
        // ==========================
        $display("[TB] Enter INPUT mode and send matrix A (2x2)");
        // ?????1
        sw[3:0] = 4'b0001;
        pulse_confirm();

        // ?????????: "2 2 1 2 3 4\n"
        uart_send_byte("2");
        uart_send_byte(" ");
        uart_send_byte("2");
        uart_send_byte(" ");
        uart_send_byte("1");
        uart_send_byte(" ");
        uart_send_byte("2");
        uart_send_byte(" ");
        uart_send_byte("3");
        uart_send_byte(" ");
        uart_send_byte("4");
        // ??????? (LF = 0x0A)????????????????
        uart_send_byte(8'h0A);

        // ??????????????
        repeat(200000) @(posedge clk);

        // ==========================
        // 2) ????????????????????? (T)
        // ==========================
        $display("[TB] Enter CALC mode and select TRANSPOSE");
        sw[3:0] = 4'b1000; // ?????????
        pulse_confirm();

        // ?? S_CALC_SELECT_OP ?????? op_type = 0001 (T)
        sw[7:4] = 4'b0001;
        pulse_confirm();

        // ????????????
        repeat(200000) @(posedge clk);

        // ==========================
        // 3) ?????? A ??????? ID, ??????
        //    ???????????????? ID=1, ??? 2x2
        // ==========================
        $display("[TB] Select operand A (2x2, ID=1) for transpose");

        // ???? A ?? m
        uart_send_byte("2");
        repeat(100000) @(posedge clk);

        // ???? A ?? n
        uart_send_byte("2");
        repeat(100000) @(posedge clk);

        // ??? ID ???????
        repeat(200000) @(posedge clk);

        // ??? ID = 1
        uart_send_byte("1");
        repeat(300000) @(posedge clk);

        // ??????????????
        $display("[TB] Wait for transpose result on uart_tx");
        repeat(1000000) @(posedge clk);
        
        // ???????? UART ???
        $display("\n[TB] UART captured %0d bytes:", rx_total);
        if (rx_total > 0) begin
            $write("[TB] RAW -> ");
            for (k = 0; k < rx_total; k = k + 1) begin
                $write("%c", rx_buf[k]);
            end
            $write("\n");
        end

        // ??????? expected_len>0??
        if (expected_len > 0) begin
            match = 1;
            if (rx_total < expected_len) match = 0;
            else begin
                start_idx = rx_total - expected_len; // compare suffix (ignore info listings)
                for (k = 0; k < expected_len; k = k + 1)
                    if (rx_buf[start_idx + k] !== expected[k]) match = 0;
            end
            if (match) $display("[TB][PASS] UART output matches expected pattern (suffix compare). (rx_total=%0d, expected_len=%0d)", rx_total, expected_len);
            else      $display("[TB][FAIL] UART output mismatch (suffix compare). (rx_total=%0d, expected_len=%0d)", rx_total, expected_len);
        end else begin
            $display("[TB][CHECK] expected_len==0, skip compare (rx_total=%0d)", rx_total);
        end

        $display("[TB] Simulation finished.");
        $finish;
    end

    // ========================================
    // Debug monitors
    // ========================================
    // FSM state changes and key handshakes
    always @(posedge clk) begin
        if (dut.u_fsm.state !== last_state) begin
            $display("[CHK][%0t] state=%0d op=%0h start_in=%b in_ready=%b in_err=%h start_store=%b wr_done=%b start_out=%b start_calc=%b rd_en=%b rd_v=%b rd_err=%b tx_start=%b tx_busy=%b",
                $time, dut.u_fsm.state, dut.u_fsm.op_type,
                dut.u_fsm.start_input, dut.matrix_input_ready, dut.input_error,
                dut.u_fsm.start_store, dut.storage_write_done,
                dut.u_fsm.start_output, dut.u_fsm.start_calc,
                dut.u_fsm.read_en, dut.rd_valid, dut.rd_error,
                dut.tx_start, dut.tx_busy);
            last_state <= dut.u_fsm.state;
        end
    end

    // Button edge monitor
    always @(posedge btn_confirm) $display("[CHK][%0t] btn_confirm posedge", $time);
    always @(negedge btn_confirm) $display("[CHK][%0t] btn_confirm negedge", $time);
    always @(posedge clk) if (dut.u_fsm.button_posedge) $display("[CHK][%0t] button_posedge seen inside FSM", $time);

    // UART TX start pulses from DUT
    always @(posedge clk) begin
        if (dut.tx_start) begin
            $display("[CHK][%0t] tx_start data=0x%02h", $time, dut.tx_data);
            $display("[CHK][%0t] output_m=%0d output_n=%0d output_is_result=%b", $time, dut.output_m, dut.output_n, dut.output_is_result);
        end
    end

    // Storage write / read events
    always @(posedge clk) begin
        if (dut.start_store)
            $display("[CHK][%0t] write_en m=%0d n=%0d", $time, dut.input_m, dut.input_n);
        if (dut.read_en)
            $display("[CHK][%0t] read_en id=%0d", $time, dut.read_id);
        if (dut.rd_valid)
            $display("[CHK][%0t] rd_valid m=%0d n=%0d", $time, dut.rd_m, dut.rd_n);
        // Dump calc_result and rd_data when�������̬��������λ��������
        if (dut.u_fsm.state == 5'd21 && dut.tx_start) begin
            $display("[CHK][%0t] calc_result bytes: [%02h %02h %02h %02h] rd_data bytes: [%02h %02h %02h %02h]", $time,
                dut.u_calc.result[7:0], dut.u_calc.result[15:8], dut.u_calc.result[23:16], dut.u_calc.result[31:24],
                dut.rd_data[7:0], dut.rd_data[15:8], dut.rd_data[23:16], dut.rd_data[31:24]);
        end
    end

endmodule
