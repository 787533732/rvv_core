module vex
#(
    parameter DATA_WIDTH         = 32,
    parameter MICROOP_WIDTH      = 5 ,    
    parameter VECTOR_TICKET_BITS = 4 ,
    parameter VECTOR_LANES       = 8 
)
(
    input   logic                                       clk         ,
    input   logic                                       rst_n       ,
    input   logic                                       flush       ,
    //Issue Interface
    input   logic                                       valid_i     ,
    output  logic                                       ready_o     ,
    input   to_vector_exec       [VECTOR_LANES-1:0]     exec_data_i ,
    input   to_vector_exec_info                         exec_info_i ,

    output  logic [VECTOR_LANES-1:0]                    wr_en       ,
    output  logic [4:0]                                 wr_addr     ,
    output  logic [VECTOR_LANES-1:0][DATA_WIDTH-1:0]    wr_data     ,
    output  logic [VECTOR_TICKET_BITS-1:0]              wr_ticket     
);

    logic [VECTOR_LANES-1:0] ready;
    logic [VECTOR_LANES-1:0] vex_pipe_valid;
    assign ready_o = &ready;

genvar k;
generate
    for(k = 0;k < VECTOR_LANES;k++) begin
        assign vex_pipe_valid[k] = valid_i & exec_data_i[k].valid;
        vex_pipe 
        #(
            .DATA_WIDTH         (DATA_WIDTH   ),
            .MICROOP_WIDTH      (MICROOP_WIDTH),
            .VECTOR_LANES       (VECTOR_LANES )
        )u_vex_pipe
        (
            .clk                (clk  ),
            .rst_n              (rst_n),

            .valid_i            (vex_pipe_valid[k]),
            .ready_o            (ready[k]       ),
            .mask_i             (),
            .data_a_i           (exec_data_i[k].data1),
            .data_b_i           (exec_data_i[k].data2),
            .immediate_i        (exec_data_i[k].immediate),
            .microop_i          (exec_info_i.microop),
            .fu_i               (exec_info_i.fu),
            .vl_i               (exec_info_i.vl),

            .frw_a_en_o         (),
            .frw_a_data_o       (),
            .frw_b_en_o         (),
            .frw_b_data_o       (),

            .wr_en_o            (wr_en[k]           ),
            .wr_data_o          (wr_data[k]         ) 
        );
    end
endgenerate


    logic   [4:0]                       dst_wr;
    logic   [VECTOR_TICKET_BITS-1:0]    ticket_wr;

    always_ff @(posedge clk) begin
        if(valid_i) begin
            dst_wr     <= exec_info_i.dst;
            ticket_wr  <= exec_info_i.ticket;
        end
    end

    // Writeback Signals
    assign wr_addr      = dst_wr;
    assign wr_ticket    = ticket_wr;

endmodule