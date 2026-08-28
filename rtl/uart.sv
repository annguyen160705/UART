module uart #(
    parameter DATA_WIDTH = 8,
    parameter BAUD_RATE = 115200,
    parameter CLK_FREQ = 100_000_000
) (
    uart_if.rx rxif,
    uart_if.tx txif,
    input logic clk,
    input logic rstn
);

    uart_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .BAUD_RATE (BAUD_RATE),
        .CLK_FREQ (CLK_FREQ)
    ) uart_tx_inst (
        .txif (txif),
        .clk (clk),
        .rstn (rstn)
    );

    uart_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .BAUD_RATE (BAUD_RATE),
        .CLK_FREQ (CLK_FREQ)
    ) uart_rx_inst (
        .rxif (rxif),
        .clk (clk),
        .rstn (rstn)
    );

    
endmodule