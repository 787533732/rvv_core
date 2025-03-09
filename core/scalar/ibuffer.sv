module ibuffer
#(
    parameter int   DW          = 64,
    parameter int   DEPTH       = 4
)
(
    input  logic            clk     ,
    input  logic            rst_n   ,
    //Flush Interface
    input  logic          valid_flush,
    // input channel
    input  logic [DW-1:0]   data_i  ,
    input  logic            valid_i ,
    output logic            ready_o ,
    // output channel
    output logic [DW-1:0]   data_o  ,
    output logic            valid_o ,
    input  logic            ready_i
);

    logic  fifo_push;
    logic  fifo_pop;

    assign fifo_push = valid_i & ready_o;
    assign fifo_pop  = valid_o & ready_i;

    fifo 
    #(
        .DW   (DW   ),
        .DEPTH(DEPTH)
    )u_fifo 
    (
        .clk            (clk      ),
        .rst_n          (rst_n    ),
        
        .valid_flush    (valid_flush),
        .push_data      (data_i   ),
        .push           (fifo_push),
        .ready          (ready_o  ),
        
        .pop_data       (data_o   ),
        .valid          (valid_o  ),
        .pop            (fifo_pop )
    );
  
endmodule