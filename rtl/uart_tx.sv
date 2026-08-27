
module uart_tx #(
    parameter DATA_WIDTH = 8,
    BAUD_RATE = 115200,
    CLK_FREQ = 100_000_000,

    localparam LB_DATA_WIDTH = $clog2(DATA_WIDTH),       // $clog2(8) = 3 bit
    PULSE_WIDTH = CLK_FREQ / BAUD_RATE,       // 100_000_000 / 115200 = 868 clock
    LB_PULSE_WIDTH = $clog2(PULSE_WIDTH),     // $clog2(868) = 10 bit
    HALF_PULSE_WIDTH = PULSE_WIDTH / 2       // 868 / 2 = 434 clock
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

always_ff @(posedge clk ) begin
    if (!rstn) begin
        state <= STT_WAIT;   // Reset FSM về trạng thái chờ
        sig_r <= 1;          // UART idle = 1
        data_r <= 0;         // Xóa dữ liệu đang lưu
        ready_r <= 1;        // Báo TX sẵn sàng nhận dữ liệu
        data_cnt <= 0;       // Reset bộ đếm bit về data[0]
        clk_cnt <= 0;        // Reset bộ đếm baud/timing
    end else begin
        case (state)
            
            STT_DATA: begin
                if (0 < clk_cnt) begin
                    clk_cnt <= clk_cnt - 1;              // Đếm 868 clock để giữ đúng 1 bit UART; không đếm -> truyền quá nhanh
                end else begin
                    sig_r <= data_r[data_cnt];           // Gửi bit hiện tại; không có data_cnt -> không biết đang gửi bit nào
                    clk_cnt <= PULSE_WIDTH;              // Nạp lại 868 clock; không nạp -> bit kế tiếp đổi ngay

                    if (data_cnt == DATA_WIDTH - 1) begin // DATA_WIDTH=8 -> kiểm tra bit cuối data_r[7]
                        state <= STT_STOP;               // Gửi đủ 8 bit -> sang stop bit
                    end else begin
                        data_cnt <= data_cnt + 1;        // Chuyển sang bit tiếp theo 0 -> 7
                    end
                end
            end

            STT_STOP: begin
                if (0 < clk_cnt) begin
                    clk_cnt <= clk_cnt - 1;                     // Giữ stop bit đủ 868 clock; không đếm -> stop bit quá ngắn
                end else begin
                    state <= STT_WAIT;                          // Truyền xong -> về trạng thái chờ
                    sig_r <= 1;                                 // UART idle/stop = 1
                    clk_cnt <= PULSE_WIDTH + HALF_PULSE_WIDTH;  // 868 + 434 = 1302 clock, tạo khoảng nghỉ 1.5 bit
                end
            end

            STT_WAIT: begin
                if (0 < clk_cnt) begin
                    clk_cnt <= clk_cnt - 1;      // Chờ hết khoảng nghỉ; không chờ -> frame kế tiếp quá sát
                end else if (!ready_r) begin
                    ready_r <= 1;                // Báo TX sẵn sàng nhận data mới
                end else if (txif.valid) begin
                    state <= STT_DATA;           // Sau start bit sẽ sang gửi data
                    sig_r <= 0;                  // Start bit UART = 0
                    data_r <= txif.data;         // Lưu 8-bit dữ liệu cần truyền
                    ready_r <= 0;                // TX đang bận
                    data_cnt <= 0;               // Bắt đầu từ data[0] (LSB)
                    clk_cnt <= PULSE_WIDTH;      // Giữ start bit 868 clock
                end
            end

            default: begin
                state <= STT_WAIT; // Nếu state lỗi thì quay về WAIT
           end
        endcase
    end
end

    assign txif.sig = sig_r;
    assign txif.ready = ready_r;
    
endmodule