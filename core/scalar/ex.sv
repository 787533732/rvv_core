/*
* Functional Units:
* 00 : Load/Store IQ
* 01 : CSR        IQ
* 10 : ALU        IQ
* 11 : Branches   IQ
*/
module ex
#(
    parameter FU_NUMBER      = 4 ,
    parameter R_ADDR         = 6 ,
    parameter MICROOP_WIDTH  = 5 ,
    parameter ROB_INDEX_BITS = 3 ,
    parameter CSR_DEPTH      = 64,
    parameter EX0            = 0 
)
(
    input   logic                        clk                    ,
    input   logic                        rst_n                  ,
    input   logic                        external_interrupt     ,
    input   logic                        timer_interrupt     ,

    input   to_execution                 t_execution            ,
    input   ex_update                    cache_fu_update        ,
    input   logic                        cache_load_blocked     ,
    //Input Interface from ROB (commited stores)
    input   logic                        cache_writeback_valid  ,
    //Forward Interface
    output  logic [31:0]                 frw_address            ,
    output  logic [ MICROOP_WIDTH-1:0]   frw_microop            ,
    input   logic [31:0]                 frw_data               ,
    input   logic                        frw_valid              ,
    input   logic                        frw_stall              ,
    //Output Interface to ROB (for stores)
    output  logic                        store_valid            ,
    output  logic [31:0]                 store_address          ,
    output  logic [31:0]                 store_data             ,
    output  logic [ MICROOP_WIDTH-1:0]   store_microop          ,
    output  logic [ROB_INDEX_BITS-1:0]   store_ticket           ,
    //Output Interface to DCache (for loads)
    output  logic                        cache_load_valid       ,
    output  logic [31:0]                 cache_load_addr        ,
    output  logic [        R_ADDR-1:0]   cache_load_dest        ,
    output  logic [ MICROOP_WIDTH-1:0]   cache_load_microop     ,
    output  logic [ROB_INDEX_BITS-1:0]   cache_load_ticket      ,

    output  logic                        output_used            ,
    output  logic [1:0]                  busy_fu                ,
    output  ex_update [3:0]              fu_update              ,
    output  predictor_update             pr_update              ,
    //CSR Bypass
    input   csr_update                   csr_update             ,
    //ROB Bypass
    input   writeback_toARF              rob_data_1             ,
    input   writeback_toARF              rob_data_2             ,
    //Committed Instrs                  
    input   writeback_toARF              commit_1               ,
    input   writeback_toARF              commit_2  
);
    writeback_toARF commit;
    writeback_toARF rob_data;
    exception_entry exception;
    always_comb begin
        if(commit_1.valid_commit & ~commit_2.valid_commit)
            commit = commit_1;
        else if(~commit_1.valid_commit & commit_2.valid_commit)
            commit = commit_2;
        else if(commit_1.valid_commit & commit_2.valid_commit) begin
            if(commit_2.csr)
                commit = commit_2;
            else
                commit = commit_1;
        end
        else
            commit = commit_1;
    end
    always_comb begin
        if(rob_data_1.valid_commit & ~rob_data_2.valid_commit)
            rob_data = rob_data_1;
        else if(~rob_data_1.valid_commit & rob_data_2.valid_commit)
            rob_data = rob_data_2;
        else if(rob_data_1.valid_commit & rob_data_2.valid_commit) begin
            if(rob_data_2.csr)
                rob_data = rob_data_2;
            else
                rob_data = rob_data_1;
        end
        else
            rob_data = rob_data_1;
    end
    always_comb begin
        if(commit_1.valid_exception) begin
            exception.valid_exception =  commit_1.valid_exception;
            exception.exception       =  commit_1.cause          ;
            exception.exception_addr  =  commit_1.address;
            exception.exception_pc    =  commit_1.pc  ;
        end
        else if(commit_2.valid_exception) begin
            exception.valid_exception =  commit_2.valid_exception;
            exception.exception       =  commit_2.cause          ;
            exception.exception_addr  =  commit_2.address ;
            exception.exception_pc    =  commit_2.pc   ;
        end
        else begin
            exception.valid_exception =  commit_1.valid_exception;
            exception.exception       =  commit_1.cause          ;
            exception.exception_addr  =  commit_1.address ;
            exception.exception_pc    =  commit_1.pc   ;
        end
    end
    //Create the Selectors
    logic               lsu_valid;
    logic               alu_valid;
    logic               bru_valid;
    logic               csr_branch;
    logic [31:0]        csr_branch_pc;
    logic [1:0]         fu_selector;
    logic [3:0]         valid;

    logic               valid_ret, dual_ret;
	assign valid_ret = commit_1.valid_commit;
	assign dual_ret  = commit_1.valid_commit && commit_2.valid_commit;

	logic                         csr_wr_en  ;
	logic [31:0] csr_data, csr_wr_data;
	logic [$clog2(CSR_DEPTH)-1:0] csr_address;

    assign fu_selector = t_execution.functional_unit;

    //Create the Validity Bits for the FUs
    always_comb begin
        for (int i = 0; i < FU_NUMBER; i++) begin
            if(i==fu_selector) begin
                valid[i] = t_execution.valid;
            end else begin
                valid[i] = 0;
            end
        end
    end
    assign lsu_valid = ~t_execution.is_vector & valid[0];
    assign csr_valid = valid[1];
    assign alu_valid = ~t_execution.is_vector & valid[2];
    assign bru_valid = ~t_execution.is_vector & valid[3];

    generate if(EX0) begin : lsu_csr
        lsu 
        #(
            .ROB_TICKET         (ROB_INDEX_BITS)
        )load_store_unit
        (
            .clk                  (clk  ),
            .rst_n                (rst_n),

            .valid                (lsu_valid),
            .input_data           (t_execution),
            .cache_fu_update      (cache_fu_update),
            .cache_load_blocked   (cache_load_blocked),

            .frw_address          (frw_address),
            .frw_microop          (frw_microop),
            .frw_data             (frw_data   ),
            .frw_valid            (frw_valid  ),
            .frw_stall            (frw_stall  ),

            .cache_writeback_valid(cache_writeback_valid),

            .store_valid          (store_valid          ),
            .store_address        (store_address        ),
            .store_data           (store_data           ),
            .store_microop        (store_microop        ),
            .store_ticket         (store_ticket         ),


            .cache_load_valid     (cache_load_valid     ),
            .cache_load_addr      (cache_load_addr      ),
            .cache_load_dest      (cache_load_dest      ),
            .cache_load_microop   (cache_load_microop   ),
            .cache_load_ticket    (cache_load_ticket    ),

            .output_used          (output_used),
            .fu_update            (fu_update[0]),
            .busy_fu              (busy_fu[0])
        );
        csr csr_ctrl
        (
            .clk                (clk    ),
            .rst_n              (rst_n  ),
            .external_interrupt (external_interrupt),
            .timer_interrupt    (timer_interrupt),

            .valid              (csr_valid),         
            .input_data         (t_execution), 
            .writeback          (commit), 
            .rob_bypass         (rob_data),
            .exception_i        (exception),
            .csr_update         (csr_update),

            .fu_update          (fu_update[1]),
            .csr_branch_pc      (csr_branch_pc),
            .csr_branch         (csr_branch)        
        );
    end
    endgenerate
    
    alu 
    #(
        .R_ADDR             (6),
        .ROB_INDEX_BITS     (3)
    )u_alu
    (
        .clk                (clk  ),
        .rst_n              (rst_n),
        // Input Port
        .valid              (alu_valid      ),
        .input_data         (t_execution    ),
        //Output Port
        .fu_update          (fu_update[2]   ),
        .busy_fu            (busy_fu[1]     ) 
    );

    bru 
    #(
        .CSR_ADDR_WIDTH ($clog2(CSR_DEPTH)),
        .EX0            (EX0)
    )branch_resolve_unit
    (
    	.clk                (clk  ),
    	.rst_n              (rst_n),
    	//Input Port
    	.valid              (bru_valid ),
    	.input_data         (t_execution    ),
        .csr_branch_pc	    (csr_branch_pc),
        .csr_branch         (csr_branch),
    	//Output Port
    	.fu_update          (fu_update[3]   ),
	    .pr_update          (pr_update),

		.csr_address        (csr_address    ),
		.csr_data           (csr_data       ),
		.csr_wr_en          (csr_wr_en      ),
		.csr_wr_data        (csr_wr_data    )
    );

    


endmodule