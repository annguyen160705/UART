`timescale 1ns/1ps


// -----------------------------------------------------------------------
// uart_tb
//
// Instantiates TWO independent `uart` cores (uart_A and uart_B) and
// cross-wires them: A's TX line drives B's RX line, and B's TX line
// drives A's RX line. Each side sends a byte to the other and the
// testbench checks that the received byte matches what was sent.
// -----------------------------------------------------------------------
module uart_tb;

    localparam DATA_WIDTH = 8;
    localparam BAUD_RATE  = 115200;
    localparam CLK_FREQ   = 100_000_000;
    localparam CLK_PERIOD = 10; // 100 MHz

    logic clk;
    logic rstn;

    // -------------------------------------------------------------
    // Interfaces
    //
    // uart_A_txif / uart_A_rxif belong to uart_A.
    // uart_B_txif / uart_B_rxif belong to uart_B.
    //
    // Cross-wiring is done by driving each core's .sig with the
    // *other* core's transmitted .sig (see assigns below).
    // -------------------------------------------------------------
    uart_if #(.DATA_WIDTH(DATA_WIDTH)) uart_A_txif ();
    uart_if #(.DATA_WIDTH(DATA_WIDTH)) uart_A_rxif ();
    uart_if #(.DATA_WIDTH(DATA_WIDTH)) uart_B_txif ();
    uart_if #(.DATA_WIDTH(DATA_WIDTH)) uart_B_rxif ();

    // Cross-connect the physical serial lines:
    // A transmits -> B receives
    assign uart_B_rxif.sig = uart_A_txif.sig;
    // B transmits -> A receives
    assign uart_A_rxif.sig = uart_B_txif.sig;

    // -------------------------------------------------------------
    // DUTs
    // -------------------------------------------------------------
    uart #(
        .DATA_WIDTH(DATA_WIDTH),
        .BAUD_RATE (BAUD_RATE),
        .CLK_FREQ  (CLK_FREQ)
    ) uart_A (
        .rxif (uart_A_rxif.rx),
        .txif (uart_A_txif.tx),
        .clk  (clk),
        .rstn (rstn)
    );

    uart #(
        .DATA_WIDTH(DATA_WIDTH),
        .BAUD_RATE (BAUD_RATE),
        .CLK_FREQ  (CLK_FREQ)
    ) uart_B (
        .rxif (uart_B_rxif.rx),
        .txif (uart_B_txif.tx),
        .clk  (clk),
        .rstn (rstn)
    );

    // -------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------
    // Reset
    // -------------------------------------------------------------
    initial begin
        rstn = 0;
        repeat (5) @(posedge clk);
        rstn = 1;
    end

    // -------------------------------------------------------------
    // Helper task: send one byte out through a tx interface and
    // wait until it's accepted (ready & valid handshake).
    // -------------------------------------------------------------
    task automatic send_byte(virtual uart_if.tx txif, input [DATA_WIDTH-1:0] b, input string who);
        begin
            @(posedge clk);
            wait (txif.ready == 1'b1);
            txif.data  <= b;
            txif.valid <= 1'b1;
            @(posedge clk);
            txif.valid <= 1'b0;
            $display("[%0t] %s sent byte: 0x%0h", $time, who, b);
        end
    endtask

    // -------------------------------------------------------------
    // Helper task: wait for one received byte on an rx interface,
    // capture it, and acknowledge with ready.
    // -------------------------------------------------------------
    task automatic recv_byte(virtual uart_if.rx rxif, output [DATA_WIDTH-1:0] b, input string who);
        begin
            wait (rxif.valid == 1'b1);
            b = rxif.data;
            $display("[%0t] %s received byte: 0x%0h", $time, who, b);
            @(posedge clk);
            rxif.ready <= 1'b1;
            @(posedge clk);
            rxif.ready <= 1'b0;
        end
    endtask

    // -------------------------------------------------------------
    // Stimulus / checking
    // -------------------------------------------------------------
    logic [DATA_WIDTH-1:0] byte_from_A_to_B = 8'hA5;
    logic [DATA_WIDTH-1:0] byte_from_B_to_A = 8'h3C;
    logic [DATA_WIDTH-1:0] captured_at_B;
    logic [DATA_WIDTH-1:0] captured_at_A;

    int errors = 0;

    initial begin
        // Keep handshake signals de-asserted until driven
        uart_A_txif.valid = 1'b0;
        uart_B_txif.valid = 1'b0;
        uart_A_rxif.ready = 1'b0;
        uart_B_rxif.ready = 1'b0;

        wait (rstn == 1'b1);
        @(posedge clk);

        // Run both directions concurrently: A -> B and B -> A
        fork
            send_byte(uart_A_txif.tx, byte_from_A_to_B, "uart_A");
            recv_byte(uart_B_rxif.rx, captured_at_B,     "uart_B");
        join

        fork
            send_byte(uart_B_txif.tx, byte_from_B_to_A, "uart_B");
            recv_byte(uart_A_rxif.rx, captured_at_A,     "uart_A");
        join

        // -----------------------------------------------------
        // Checks
        // -----------------------------------------------------
        if (captured_at_B !== byte_from_A_to_B) begin
            $display("FAIL: A->B mismatch. Expected 0x%0h, got 0x%0h",
                      byte_from_A_to_B, captured_at_B);
            errors++;
        end else begin
            $display("PASS: A->B byte matched (0x%0h)", captured_at_B);
        end

        if (captured_at_A !== byte_from_B_to_A) begin
            $display("FAIL: B->A mismatch. Expected 0x%0h, got 0x%0h",
                      byte_from_B_to_A, captured_at_A);
            errors++;
        end else begin
            $display("PASS: B->A byte matched (0x%0h)", captured_at_A);
        end

        if (errors == 0)
            $display("\n=== TESTBENCH PASSED: both directions communicated correctly ===");
        else
            $display("\n=== TESTBENCH FAILED: %0d error(s) ===", errors);

        $finish;
    end

    // Safety timeout in case a handshake never completes
    initial begin
        #2_000_000; // 2 ms — generous given ~8.7us/bit at 115200 baud
        $display("ERROR: testbench timed out waiting for communication to complete");
        $finish;
    end

endmodule