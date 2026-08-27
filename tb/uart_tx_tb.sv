`timescale 1ns/1ps

module uart_tx_tb;

    parameter DATA_WIDTH = 8;
    parameter BAUD_RATE  = 115200;
    parameter CLK_FREQ   = 100_000_000;

    logic clk;
    logic rstn;

    // Interface
    uart_if #(
        .DATA_WIDTH(DATA_WIDTH)
    ) txif();

    // DUT
    uart_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ(CLK_FREQ)
    ) dut (
        .txif(txif),
        .clk(clk),
        .rstn(rstn)
    );

    // 100 MHz -> period = 10 ns
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Stimulus
    initial begin
        rstn       = 0;
        txif.valid = 0;
        txif.data  = 0;

        // Reset
        repeat(5) @(posedge clk);
        rstn = 1;

        // Chờ TX ready
        wait(txif.ready == 1);

        // Gửi 8'hA5 = 1010_0101
        @(posedge clk);
        txif.data  <= 8'hA5;
        txif.valid <= 1;

        @(posedge clk);
        txif.valid <= 0;

        // Chờ truyền xong
        wait(txif.ready == 0);
        wait(txif.ready == 1);

        repeat(20) @(posedge clk);

        $finish;
    end

    // Monitor
    initial begin
        $monitor(
            "Time=%0t | rstn=%b | valid=%b | ready=%b | data=%h | TX=%b | state=%0d",
            $time,
            rstn,
            txif.valid,
            txif.ready,
            txif.data,
            txif.sig,
            dut.state
        );
    end

endmodule