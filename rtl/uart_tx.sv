`include "uart_if.sv"

module uart_tx #(
    parameter
    DATA_WIDTH = 8,
    BAUD_RATE = 115200,
    CLK_FREQ = 100_000_000,

    localparam
    LB_DATA_WIDTH = $clog2(DATA_WIDTH),
    PULSE_WIDTH = CLK_FREQ / BAUD_RATE,
    LB_PULSE_WIDTH = PULSE_WIDTH / 2
) (
    uart_if.tx txif,
    input logic clk,
    input logic rstn
);

typedef enum logic [1:0] {
    STT_DATA    = 2'b00,
    STT_STOP = 2'b01,
    STT_WAIT = 2'b10
} statetype;

statetype state;

logic [DATA_WIDTH-1:0] data_r;;
logic sig_r;
logic ready_r;
logic [LB_DATA_WIDTH-1:0] data_cnt;
logic [LB_PULSE_WIDTH-1:0] clk_cnt;


    
endmodule