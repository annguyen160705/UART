module uart_tx #(
    parameter DATA_WIDTH = 8, //8 bits data
    BAUD_RATE = 115200, // UART speed
    CLK_FREQ = 100_000_000, // clk speed

    localparam LB_DATA_WIDTH = $clog2(DATA_WIDTH), // log2(8) = 3
    PULSE_WIDTH = CLK_FREQ / BAUD_RATE, // 100_000_000/115200 = 868 clock
    HALF_PULSE_WIDTH = PULSE_WIDTH / 2, // 868/2 = 434
    LB_PULSE_WIDTH = $clog2(PULSE_WIDTH + HALF_PULSE_WIDTH) // log2(868 + 434) > 10 = 11
) (
    uart_if.tx txif, // o sig, i data, i valid, o ready
    input logic clk,
    input logic rstn
);

typedef enum logic [1:0] {
    STT_WAIT = 2'b00, // Waiting for tx to ready sending the data
    STT_DATA = 2'b01, // Send data
    STT_STOP = 2'b10 // 
} statetype;

statetype state;

logic [DATA_WIDTH-1:0] data_r; // [7:0]
logic sig_r; 
logic ready_r;
logic [LB_DATA_WIDTH-1:0] data_cnt; // [2:0]
logic [LB_PULSE_WIDTH-1:0] clk_cnt; // [10:0] 

always_ff @(posedge clk) begin
    if (!rstn) begin
        state <= STT_WAIT;
        sig_r <= 1; // ILDE state not stop bit
        data_r <= 0;
        ready_r <= 1;
        data_cnt <= 0;
        clk_cnt <= 0;
    end else begin
        case (state)

            STT_WAIT: begin
                if (0 < clk_cnt) begin 
                    clk_cnt <= clk_cnt - 1; 
                end else if (!ready_r) begin 
                    ready_r <= 1; // ready for new data.
                end else if (txif.valid) begin // txif.valid says “I have data”
                    state <= STT_DATA; 
                    sig_r <= 0; //start bit
                    data_r <= txif.data; // data_r = 8'h3C [1 0 1 0 0 1 0 1]
                    ready_r <= 0; // I'm busy now.
                    data_cnt <= 0; // 0 -> 7 (2^3)
                    clk_cnt <= PULSE_WIDTH; // 868 digits
                end
            end

            STT_DATA: begin
                if (0 < clk_cnt) begin // wait for 868 digits
                    clk_cnt <= clk_cnt - 1;
                end else begin
                    sig_r <= data_r[data_cnt]; // sig_r = data[0] ... data[7] every 868 digits (data flipped)
                    clk_cnt <= PULSE_WIDTH; // reset 868 digits

                    if (data_cnt == DATA_WIDTH - 1) begin
                        state <= STT_STOP;
                    end else begin
                        data_cnt <= data_cnt + 1;
                    end
                end
            end

            STT_STOP: begin
                if (0 < clk_cnt) begin // wait for 868 digits
                    clk_cnt <= clk_cnt - 1;
                end else begin
                    state <= STT_WAIT;
                    sig_r <= 1; // stop bit
                    clk_cnt <= PULSE_WIDTH + HALF_PULSE_WIDTH; //1032 digits
                end
            end



            default: begin
                state <= STT_WAIT;
            end
        endcase
    end
end

assign txif.sig = sig_r;
assign txif.ready = ready_r;

endmodule