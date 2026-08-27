module uart_rx #(
    parameter DATA_WIDTH = 8,
    BAUD_RATE = 115200,
    CLK_FREQ = 100_000_000,

    localparam LB_DATA_WIDTH    = $clog2(DATA_WIDTH),
    PULSE_WIDTH                 = CLK_FREQ / BAUD_RATE,
    LB_PULSE_WIDTH              = $clog2(PULSE_WIDTH),
    HALF_PULSE_WIDTH            = PULSE_WIDTH / 2
) (
    uart_if.rx rxif,
    input logic clk,
    input logic rstn
);



    
endmodule
