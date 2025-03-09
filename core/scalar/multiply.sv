module multiply 
#(
    parameter DATA_SIZE=32
) 
(
    input  logic                   clk      ,
    input  logic                   rst_n    ,
    //Input Port
    input  logic                   enable   ,
    input  logic [1:0]             op_type  ,

    input  logic [  DATA_SIZE-1:0] data_1   ,
    input  logic [  DATA_SIZE-1:0] data_2   ,
    //Output Port
    output logic                   ready    ,
    output logic [2*DATA_SIZE-1:0] result
);

    always_comb begin
        case(op_type) 
            2'b00 : result = data_1 * data_2;
            2'b01 : result = {{32{data_1[31]}},data_1} * {{32{data_2[31]}},data_2};
            2'b10 : result = {32'b0, data_1} * {32'b0, data_2};
            2'b11 : result = {{32{data_1[31]}},data_1} * {32'b0, data_2};
        endcase
    end
    assign ready = enable; 


endmodule

