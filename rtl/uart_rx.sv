module uart_rx #(
    parameter DATA_WIDTH = 8, //8 bits data
    BAUD_RATE = 115200, // UART speed
    CLK_FREQ = 100_000_000, // clk speed

    localparam LB_DATA_WIDTH    = $clog2(DATA_WIDTH), // log2(8) = 3
    PULSE_WIDTH                 = CLK_FREQ / BAUD_RATE, // 100_000_000/115200 = 868 clock
    LB_PULSE_WIDTH              = $clog2(PULSE_WIDTH + HALF_PULSE_WIDTH), // log2(868 + 434) > 10 = 11
    HALF_PULSE_WIDTH            = PULSE_WIDTH / 2  // 868/2 = 434
) (
    uart_if.rx rxif, // i sig, o data, o valid, i ready
    input logic clk,
    input logic rstn
);

function majority5(input logic [4:0] val);

    return ($countones(val) >= 3); // noise filter
    
endfunction

logic [1:0] sampling_cnt; // 0 -> 3 sampling every 4 digits
logic [4:0] sig_q; //sig_q stores the 5 most recent samples of the UART signal
logic sig_r; // sig_r stores the filtered result produced by majority5.

always_ff @(posedge clk ) begin
    if(!rstn) begin
        sampling_cnt <= 0;
        sig_q <= 5'b11111;
        sig_r <= 1;
    end

    else begin
        if(sampling_cnt == 0) begin
            sig_q <= {rxif.sig, sig_q[4:1]}; 
            //first bit is 1 it'll sample [1 1 1 1 1]
        end

        sig_r <= majority5(sig_q); // if there is noise [1 1 1 0 1] it'll count ones and return 1 if ones >= 3

        sampling_cnt <= sampling_cnt + 1; // overflow/wrap-around 0 1 2 3 -> 1[00] 1[01] 2 3
    end
end

typedef enum logic [1:0] {
    STT_WAIT    = 2'b00,
    STT_STOP = 2'b01,
    STT_DATA = 2'b10
} statetype;
    
statetype state;

logic [DATA_WIDTH-1:0] data_tmp_r; // [7:0]
logic [LB_DATA_WIDTH-1:0] data_cnt; // [2:0]
logic [LB_PULSE_WIDTH-1:0] clk_cnt; // [10:0] 
logic rx_done;

always_ff @(posedge clk) begin
    if(!rstn) begin
        state       <= STT_WAIT;
        data_tmp_r  <= 0;
        data_cnt    <= 0;
        clk_cnt     <= 0;
    end

    else begin
        case (state)
        
            STT_WAIT: begin
                if(sig_r == 0) begin
                    clk_cnt <= PULSE_WIDTH + HALF_PULSE_WIDTH; // 1302 digits
                    data_cnt <= 0;
                    state <= STT_DATA;
                end
            end
            
            STT_DATA: begin
                if (clk_cnt == 0) begin
                    // Sample one UART data bit
                    data_tmp_r <= {sig_r, data_tmp_r[DATA_WIDTH-1:1]};
                    //data_tmp_r = 7 -> 6 ... 0 (initial data)
                    // Start timing for the next UART bit
                    clk_cnt <= PULSE_WIDTH; //868

                    // Check whether all data bits have been received
                    if (data_cnt == DATA_WIDTH - 1) begin
                        state <= STT_STOP;
                    end
                    else begin
                        data_cnt <= data_cnt + 1;
                    end
                end
                else begin
                    // Wait until the next sampling point
                    clk_cnt <= clk_cnt - 1;
                end
            end

            STT_STOP: begin
                if(clk_cnt == 0 && sig_r) begin // wait for stop bit from tx if last bit was 1 then we need clk to be 0
                    state <= STT_WAIT;
                end
                else begin
                    clk_cnt <= clk_cnt - 1;
                end
            end

            default: begin
                state <= STT_WAIT;
            end
        endcase
    end
end

assign rx_done = (state == STT_STOP) && (clk_cnt == 0);

logic [DATA_WIDTH-1:0] data_r;
logic valid_r;

always_ff @(posedge clk ) begin
    if (!rstn) begin
        data_r <= 0;
        valid_r <= 0;
    end

    else if (rx_done && !valid_r) begin
        valid_r <= 1; //data is available for CPU / FIFO / User Logic ...
        data_r <= data_tmp_r;
    end

    else if(valid_r && rxif.ready) begin
        valid_r <= 0;
    end
end

/*uart_rx data → CPU / FIFO / logic
uart_rx  valid → CPU / FIFO / logic
uart_rx ← ready  CPU / FIFO / logic*/

assign rxif.data = data_r;
assign rxif.valid = valid_r;

endmodule
