interface uart_if;
    #(parameter WIDTH = 8);

    logic sig;
    logic [WIDTH-1:0] data;
    logic valid;
    logic ready;
    

    modport master (
        output sig,
        input  data,
        input valid,
        output ready
    );
    
    modport slave (
        input sig, 
        output data,
        output valid,
        input  ready
    );
    
endinterface