interface uart_if
    #(parameter DATA_WIDTH = 8);

    logic sig;
    logic [DATA_WIDTH-1:0] data;
    logic valid;
    logic ready;
    

    modport tx (
        output sig,
        input  data,
        input valid,
        output ready
    );
    
    modport rx (
        input sig, 
        output data,
        output valid,
        input  ready
    );
    
endinterface