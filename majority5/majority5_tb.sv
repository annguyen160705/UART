module majority5_tb;

    logic [4:0] val;
    logic       result;

    // Instantiate the DUT
    majority5 dut (
        .val    (val),
        .result (result)
    );

    initial begin

        // Test 0 ones
        val = 5'b00000;
        #10;
        $display("val = %b, result = %b", val, result);

        // Test 1 one
        val = 5'b10000;
        #10;
        $display("val = %b, result = %b", val, result);

        // Test 2 ones
        val = 5'b11000;
        #10;
        $display("val = %b, result = %b", val, result);

        // Test 3 ones
        val = 5'b11100;
        #10;
        $display("val = %b, result = %b", val, result);

        // Test 4 ones
        val = 5'b11110;
        #10;
        $display("val = %b, result = %b", val, result);

        // Test 5 ones
        val = 5'b11111;
        #10;
        $display("val = %b, result = %b", val, result);

        $finish;
    end

endmodule