module sram 
#(
    SIZE        = 1024  ,
    DATA_WIDTH  = 8     , 
    RD_PORTS    = 1     , 
    WR_PORTS    = 1     , 
    RESETABLE   = 0
) 
(
    input  logic                                  clk          ,
    input  logic                                  rst_n        ,
    //Write Port
    input  logic [WR_PORTS-1:0]                   wr_en        ,
    input  logic [WR_PORTS-1:0][$clog2(SIZE)-1:0] write_address,
    input  logic [WR_PORTS-1:0][  DATA_WIDTH-1:0] new_data     ,
    //Read Port
    input  logic [RD_PORTS-1:0][$clog2(SIZE)-1:0] read_address ,
    output logic [RD_PORTS-1:0][  DATA_WIDTH-1:0] data_out
);

    localparam SEL_BITS = $clog2(SIZE); 
	// #Internal Signals#
	logic [SIZE-1:0][DATA_WIDTH-1:0] Memory_Array;

	//Push the Data out
    always_comb begin : DataOUT
        for (int i = 0; i < RD_PORTS; i++) begin
            data_out[i] = Memory_Array[read_address[i]];
        end
    end

    generate
        if(RESETABLE) begin
            //Create Resetable SRAM
            always_ff @(posedge clk or negedge rst_n) begin : Update
                if(!rst_n) begin
                    for (int i = 0; i <= SIZE-1; i++) begin
                        Memory_Array[i]<='d0;
                    end
                end else begin
                    for (int i = 0; i < WR_PORTS; i++) begin
                        if (wr_en[i]) 
                            Memory_Array[write_address[i]] <= new_data[i];
                    end
                end
            end
        end else begin
            //Create Non-Resetable SRAM
            always_ff @(posedge clk) begin : Update
                for (int i = 0; i < WR_PORTS; i++) begin
                    if (wr_en[i]) 
                        Memory_Array[write_address[i]] <= new_data[i];
                end
            end
        end
    endgenerate
	

endmodule