module valu 
#(
    parameter DATA_WIDTH    = 32,
    parameter MICROOP_WIDTH = 5 ,
    parameter VECTOR_LANES  = 8 
)
(
    input   logic                                           clk             ,
    input   logic                                           rst_n           , 

    input   logic                                           valid_i         ,
    input   logic [DATA_WIDTH-1:0]                          data_a_ex1_i    ,
    input   logic [DATA_WIDTH-1:0]                          data_b_ex1_i    ,
    input   logic [DATA_WIDTH-1:0]                          imm_ex1_i       ,
    input   logic [MICROOP_WIDTH-1:0]                       microop_i       ,
    input   logic                                           mask_i          ,
    input   logic [$clog2(32*VECTOR_LANES):0]               vl_i            ,

    output  logic                                           ready_res_ex1_o ,
    output  logic [DATA_WIDTH-1:0]                          result_ex1_o                 
);
    logic               valid_int_ex1;

    logic [DATA_WIDTH-1:0] data_a_u_ex1 ;
    logic [DATA_WIDTH-1:0] data_b_u_ex1 ;
    logic [DATA_WIDTH-1:0] imm_u_ex1    ;
    logic [DATA_WIDTH-1:0] data_a_s_ex1 ;
    logic [DATA_WIDTH-1:0] data_b_s_ex1 ;
    logic [DATA_WIDTH-1:0] imm_s_ex1    ;
    logic [DATA_WIDTH-1:0] result_int;

    assign data_a_u_ex1 = $unsigned(data_a_ex1_i);
    assign data_b_u_ex1 = $unsigned(data_b_ex1_i);
    assign imm_u_ex1    = $unsigned(imm_ex1_i);

    assign data_a_s_ex1 = $signed(data_a_ex1_i);
    assign data_b_s_ex1 = $signed(data_b_ex1_i);
    assign imm_s_ex1    = $signed(imm_ex1_i);

    always_comb begin
        if(valid_i) begin
            case(microop_i)
                5'b00001 : begin//VADD
                    result_int    = data_a_u_ex1 + data_b_u_ex1; 
                    valid_int_ex1 = 1'b1;
                end
                5'b00010 : begin//VSUB
                    result_int    = data_a_u_ex1 - data_b_u_ex1; 
                    valid_int_ex1 = 1'b1;
                end
                5'b00011 : begin//VAND
                    result_int    = data_a_u_ex1 & data_b_u_ex1; 
                    valid_int_ex1 = 1'b1;
                end
                5'b00100 : begin//VOR
                    result_int    = data_a_u_ex1 | data_b_u_ex1; 
                    valid_int_ex1 = 1'b1;
                end
                5'b00101 : begin//VXOR
                    result_int    = data_a_u_ex1 ^ data_b_u_ex1; 
                    valid_int_ex1 = 1'b1;
                end
                5'b00110 : begin//VSLL
                    result_int    = data_a_u_ex1 << data_b_u_ex1[4:0]; 
                    valid_int_ex1 = 1'b1;
                end
                5'b00111 : begin//VSRL
                    result_int    = data_a_u_ex1 >> data_b_u_ex1[4:0]; 
                    valid_int_ex1 = 1'b1;
                end
                5'b01000 : begin//VSRA
                    result_int    = data_a_s_ex1 >>> data_b_u_ex1[4:0]; 
                    valid_int_ex1 = 1'b1;
                end
                5'b01001 : begin//VSLT
                    result_int    = (data_a_ex1_i < data_b_ex1_i); 
                    valid_int_ex1 = 1'b1;
                end
                5'b01010 : begin//VSLTU
                    result_int    = (data_a_u_ex1 < data_b_u_ex1); 
                    valid_int_ex1 = 1'b1;
                end
                5'b10001 : begin//VADDI
                    result_int    = data_a_u_ex1 + imm_u_ex1;
                    valid_int_ex1 = 1'b1;
                end
                5'b10011 : begin//VANDI
                    result_int    = data_a_u_ex1 & imm_u_ex1;
                    valid_int_ex1 = 1'b1;
                end
                5'b10100 : begin//VORI
                    result_int    = data_a_u_ex1 | imm_u_ex1;
                    valid_int_ex1 = 1'b1;
                end
                5'b10101 : begin//VXORI
                    result_int    = data_a_u_ex1 ^ imm_u_ex1; 
                    valid_int_ex1 = 1'b1;
                end
                5'b10110 : begin//VSLLI
                    result_int    = data_a_u_ex1 << imm_u_ex1[4:0]; 
                    valid_int_ex1 = 1'b1;
                end
                5'b10111 : begin//VSRLI
                    result_int    = data_a_u_ex1 >> imm_u_ex1[4:0]; 
                    valid_int_ex1 = 1'b1;
                end
                5'b11000 : begin//VSRAI
                    result_int    = data_a_s_ex1 >>> imm_u_ex1[4:0]; 
                    valid_int_ex1 = 1'b1;
                end
                default  : begin
                    result_int    = 32'b0;
                    valid_int_ex1 = 1'b0;
                end
            endcase
        end
        else begin
            result_int    = 32'b0;
            valid_int_ex1 = 1'b0;
        end
    end

    assign ready_res_ex1_o = valid_int_ex1;
    assign result_ex1_o    = valid_int_ex1 ? result_int : 32'b0;
endmodule