module majority5 (
    input  logic [4:0] val,
    output logic       result
);

    always_comb begin
        case (val)

            5'b00000: result = 1'b0;
            5'b00001: result = 1'b0;
            5'b00010: result = 1'b0;
            5'b00100: result = 1'b0;
            5'b01000: result = 1'b0;
            5'b10000: result = 1'b0;

            5'b00011: result = 1'b0;
            5'b00101: result = 1'b0;
            5'b01001: result = 1'b0;
            5'b10001: result = 1'b0;
            5'b00110: result = 1'b0;
            5'b01010: result = 1'b0;
            5'b10010: result = 1'b0;
            5'b01100: result = 1'b0;
            5'b10100: result = 1'b0;
            5'b11000: result = 1'b0;

            default: result = 1'b1;

        endcase
    end

endmodule