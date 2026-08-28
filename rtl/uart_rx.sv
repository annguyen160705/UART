module uart_rx #(
    parameter DATA_WIDTH = 8,
    BAUD_RATE = 115200,
    CLK_FREQ = 100_000_000,

    localparam LB_DATA_WIDTH    = $clog2(DATA_WIDTH),
    PULSE_WIDTH                 = CLK_FREQ / BAUD_RATE,
    LB_PULSE_WIDTH              = $clog2(PULSE_WIDTH + HALF_PULSE_WIDTH),
    HALF_PULSE_WIDTH            = PULSE_WIDTH / 2
) (
    uart_if.rx rxif,
    input logic clk,
    input logic rstn
);

function majority5(input logic [4:0] val);

    return ($countones(val) >= 3);
    
endfunction

logic [1:0] sampling_cnt;
logic [4:0] sig_q;
logic sig_r;

always_ff @(posedge clk ) begin
    if(!rstn) begin
        sampling_cnt <= 0;
        sig_q <= 5'b11111;
        sig_r <= 1;
    end

    else begin
        if(sampling_cnt == 0) begin
            sig_q <= {rxif.sig, sig_q[4:1]};
        end

        sig_r <= majority5(sig_q);

        sampling_cnt <= sampling_cnt + 1;
    end
end

typedef enum logic [1:0] {
    STT_DATA    = 2'b00,
    STT_STOP = 2'b01,
    STT_WAIT = 2'b10
} statetype;
    
statetype state;

logic [DATA_WIDTH-1:0] data_tmp_r;
logic [LB_DATA_WIDTH-1:0] data_cnt;
logic [LB_PULSE_WIDTH-1:0] clk_cnt;
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
            
            STT_DATA: begin
                if (clk_cnt == 0) begin
                    // Sample one UART data bit
                    data_tmp_r <= {sig_r, data_tmp_r[DATA_WIDTH-1:1]};

                    // Start timing for the next UART bit
                    clk_cnt <= PULSE_WIDTH;

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
                if(clk_cnt == 0 && sig_r) begin
                    state <= STT_WAIT;
                end
                else begin
                    clk_cnt <= clk_cnt - 1;
                end
            end

            STT_WAIT: begin
                if(sig_r == 0) begin
                    clk_cnt <= PULSE_WIDTH + HALF_PULSE_WIDTH;
                    data_cnt <= 0;
                    state <= STT_DATA;
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
        valid_r <= 1;
        data_r <= data_tmp_r;
    end

    else if(valid_r && rxif.ready) begin
        valid_r <= 0;
    end
end


assign rxif.data = data_r;
assign rxif.valid = valid_r;

endmodule
