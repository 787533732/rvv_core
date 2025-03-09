module alu 
#(
    parameter R_ADDR         = 6 ,
    parameter ROB_INDEX_BITS = 3
) 
(
    input  logic            clk       ,
    input  logic            rst_n     ,
    // Input Port
    input  logic            valid     ,
    input  to_execution     input_data,
    //Output Port
    output ex_update        fu_update ,
    output logic            busy_fu
);
    localparam DIV_CYCLES = 16;
//---------------------------------------------------------------------------------------
    logic unsigned [32-1 : 0] data_1_u,data_2_u;
    logic signed [32-1 : 0]   data_1_s,data_2_s;
    logic [32-1 : 0]           result_comb;
	logic [4 : 0]                      microoperation;
    logic [DIV_CYCLES:0]               busy_vector;
    logic                              operation_enable;
//---------------------------------------------------------------------------------------
    logic [2*32-1 : 0] result_div, result_mul;
    logic [32-1 : 0]   remainder;
    logic [1:0]         op_type; 
    logic               enable_div, enable_mul;
    logic              div_ready,div_valid, mul_ready, arithmetic_ready, exc_valid;
    logic [5:0]          div_destination;
    logic [2:0]          div_ticket;     
    division 
    #(32,DIV_CYCLES)
    division
    (
        .clk           (clk                     ),
        .rst_n         (rst_n                   ),
        //Inputs                
        .enable        (enable_div              ),
        .op_type       (op_type                 ),
        .destination_i (input_data.destination  ),
        .ticket_i      (input_data.ticket       ),
        .dividend      (input_data.data1        ),
        .divider       (input_data.data2        ),
        //Outputs       
        .ready         (div_ready               ),
        .valid         (div_valid               ),
        .destination_o (div_destination         ),
        .ticket_o      (div_ticket              ),
        .result        (result_div              )
    );

    multiply #(32)
    multiply
    (
        .clk      (clk             ),
        .rst_n    (rst_n           ),
        //Inputs
        .enable   (enable_mul      ),
        
        .data_1   (input_data.data1),
        .data_2   (input_data.data2),
        //Outputs
        .ready    (mul_ready       ),
        .result   (result_mul      )
    );
//---------------------------------------------------------------------------------------
	//create dummy signals
	assign microoperation = input_data.microoperation;
    assign data_1_u = $unsigned(input_data.data1);
    assign data_2_u = $unsigned(input_data.data2);
    assign data_1_s = $signed(input_data.data1);
    assign data_2_s = $signed(input_data.data2);

	//create the output
	assign fu_update.valid_exception = 0; //Exceptions used for debugging atm
	assign fu_update.cause           = 2;					                      //Exceptions used for debugging atm
    assign fu_update.valid           = (valid & input_data.valid & (input_data.data2==0)) ? 1'b1 : (mul_ready | div_valid | arithmetic_ready);
    assign fu_update.destination = div_valid ? div_destination : input_data.destination;
    assign fu_update.ticket      = div_valid ? div_ticket      : input_data.ticket;
    // Push the correct data to the Output
    always_comb begin : Outputs
        case(microoperation)
            5'b00010 : //MUL (lower 32bits)
                fu_update.data = result_mul[31:0]; 
            5'b00011, 5'b00100, 5'b00101 : //MULH/MULHU/MULHSU 
                fu_update.data = result_mul[2*32-1:32];
            5'b00110, 5'b00111 : //DIV/DIVU/REM/REMU
                fu_update.data = (input_data.data2==0) ? 32'hffff_ffff : result_div[31:0];
            5'b01000, 5'b01001 : //REM/REMU
                fu_update.data = (input_data.data2==0) ? input_data.data1 : result_div[31:0];
            default : 
                fu_update.data = div_valid ? result_div[31:0] : result_comb;
        endcase
    end

// Create the Output based on the desired Operation
always_comb begin
    enable_mul = 0;
    enable_div = 0;
    result_comb = 0;
    op_type  = 0;
    exc_valid  = 1;
    arithmetic_ready = 0;
    if(valid & input_data.valid) begin
        case (microoperation)
            5'b00000: begin//ADD
                result_comb = data_1_u + data_2_u;
                exc_valid  = 0;
                arithmetic_ready = 1;
            end
            5'b00001: begin//SUB
                result_comb = data_1_u - data_2_u;
                exc_valid  = 0;
                arithmetic_ready = 1;
            end
            5'b00010: begin//MUL (lower 32bits)
                enable_mul = 1;
                op_type    = 2'b00;
                exc_valid  = 0;
            end
            5'b00011: begin
                //MULH (upper 32bits)
                enable_mul = 1;
                op_type    = 2'b01;
                exc_valid  = 0;
            end
            5'b00100: begin
                //MULHU (upper 32bits)
                enable_mul = 1;
                op_type    = 2'b10;
                exc_valid  = 0;
            end
            5'b00101: begin
                //MULHSU (upper 32bits) (signed*unsigned)
                enable_mul = 1;
                op_type    = 2'b11;
                exc_valid  = 0;
            end
            5'b00110: begin
                //DIV
                enable_div = 1;
                op_type    = 2'b00;
            end
            5'b00111: begin
                //DIVU
                if(input_data.data2==0) begin            //Division by zero
                    enable_div = 0;
                    result_comb = 32'hffff_ffff;//-1
                    arithmetic_ready = 1;
                end else begin
                    enable_div = 1;
                    result_comb = 0;
                end
                enable_mul = 0;
                op_type    = 2'b01;
                exc_valid  = 0;
            end
            5'b01000: begin
                //REM
                if(input_data.data2==0) begin            //Division by zero
                    enable_div = 0;
                    result_comb = input_data.data1;
                end else if(input_data.data1=='b1 && input_data.data2==-1) begin //OverFlow
                    result_comb = 'b0;
                    enable_div = 0;
                end else begin
                    enable_div = 1;
                    result_comb = 0;
                end
                enable_mul = 0;
                op_type  = 2'b10;
                exc_valid  = 0;
            end
            5'b01001: begin
                //REMU
                if(input_data.data2==0) begin            //Division by zero
                    enable_div = 0;
                    result_comb = input_data.data1;
                end else begin
                    enable_div = 1;
                    result_comb = 0;
                end
                op_type  = 2'b11;
                exc_valid  = 0;
            end
            5'b01010: begin//AND/ANDI
                op_type    = 0;
                result_comb = data_1_u & data_2_u;
                exc_valid  = 0;
                arithmetic_ready = 1;
            end
            5'b01011: begin
                //OR/ORI
                op_type    = 0;
                result_comb = data_1_u | data_2_u;
                exc_valid  = 0;
                arithmetic_ready = 1;
            end
            5'b01100: begin //XOR/XORI
                op_type  = 0;
                result_comb = data_1_u ^ data_2_u;
                exc_valid  = 0;
                arithmetic_ready = 1;
            end
        endcase
    end
end


//Create the Busy Output
assign busy_fu = 1'b0;

endmodule