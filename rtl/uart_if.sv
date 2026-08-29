interface uart_if
    #(parameter DATA_WIDTH = 8);

    logic sig;
    logic [DATA_WIDTH-1:0] data;
    logic valid;
    logic ready;
    
    

    modport tx (
        output sig, // UART serial signal goes OUT of uart_tx
        input  data, // data comes INTO uart_tx
        input valid, // valid = 1 → data is available
        output ready // ready = 1 → module is ready to accept data
    );
    
    modport rx (
        input sig, // serial UART signal comes INTO uart_rx
        output data, // received byte comes OUT
        output valid, // uart_rx tells the receiver that data is available
        input  ready //receiver tells uart_rx it can accept data
    );
    
endinterface