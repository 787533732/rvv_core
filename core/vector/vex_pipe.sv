module vex_pipe
#(
    parameter DATA_WIDTH         = 32,
    parameter MICROOP_WIDTH      = 5 ,
    parameter VECTOR_LANES       = 8 
)
(
    input   logic                               clk         ,
    input   logic                               rst_n       ,

    input   logic                               valid_i     ,
    output  logic                               ready_o     ,
    input   logic                               mask_i      ,//?
    input   logic [DATA_WIDTH-1:0]              data_a_i    ,
    input   logic [DATA_WIDTH-1:0]              data_b_i    ,
    input   logic [DATA_WIDTH-1:0]              immediate_i ,
    input   logic [MICROOP_WIDTH-1:0]           microop_i   ,
    input   logic [1:0]                         fu_i        ,
    input   logic [$clog2(32*VECTOR_LANES):0]   vl_i        ,
    //Forward Point #1
    output  logic                               frw_a_en_o  ,
    output  logic [DATA_WIDTH-1:0]              frw_a_data_o,
    //Forward Point #2
    output  logic                               frw_b_en_o  ,
    output  logic [DATA_WIDTH-1:0]              frw_b_data_o,
    //write back
    output  logic                               wr_en_o     ,  
    output  logic [DATA_WIDTH-1:0]              wr_data_o        
);

    logic                   ready_res_int_ex1;
    logic [DATA_WIDTH-1:0]  res_int_ex1      ;

    assign valid_int_ex1  = valid_i;
    assign ready_o        = 1'b1;
    valu 
    #(
        .DATA_WIDTH     (DATA_WIDTH     ),
        .MICROOP_WIDTH  (MICROOP_WIDTH  ),
        .VECTOR_LANES   (VECTOR_LANES   )
    )vector_alu
    (
        .clk             (valid_i           ),
        .rst_n           (rst_n             ),
        .valid_i         (valid_int_ex1     ),
        .data_a_ex1_i    (data_a_i          ),
        .data_b_ex1_i    (data_b_i          ),
        .imm_ex1_i       (immediate_i       ),
        .microop_i       (microop_i         ),
        .mask_i          (              ),
        .vl_i            (vl_i              ),

        .ready_res_ex1_o (ready_res_int_ex1 ),
        .result_ex1_o    (res_int_ex1       ) 
    );
    logic [DATA_WIDTH-1:0]  data_ex1;
    logic                   valid_result_wr;
    always_ff @(posedge clk) begin
        if(valid_int_ex1) begin
            data_ex1 <= res_int_ex1;
        end 
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_result_wr     <= 1'b0;
            //mask_wr             <= 1'b1;
        end else begin
            valid_result_wr     <= valid_int_ex1;
            //mask_wr             <= mask_ex4 | (use_reduce_tree_ex4 & VECTOR_LANE_NUM != 0);
        end
    end
    assign wr_en_o        = valid_result_wr;
    assign wr_data_o      = data_ex1;

endmodule