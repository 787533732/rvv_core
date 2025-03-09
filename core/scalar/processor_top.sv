module processor_top 
#(
    parameter int INSTR_BITS         = 32 ,
    parameter int FETCH_WIDTH        = 64 ,
    parameter int DATA_WIDTH         = 32 ,
    parameter int MICROOP_WIDTH      = 5  ,
    parameter int PR_WIDTH           = 6  ,
    parameter int PHYSICAL_REGISTERS = 64 ,
    parameter int IQ_DEPTH           = 6  ,
    parameter int ROB_ENTRIES        = 8  ,
    parameter int RAS_DEPTH          = 8  ,
    parameter int MAX_BRANCH_IF      = 2  ,
    parameter int GSH_HISTORY_BITS   = 12 ,
    parameter int GSH_SIZE           = 256,
    parameter int BTB_SIZE           = 256,
    parameter int CSR_DEPTH          = 64 ,
    parameter int VECTOR_ENABLED     = 1  ,
    parameter int VECTOR_ELEM        = 4  ,
    parameter int VECTOR_ACTIVE_EL   = 4
) (
    input   logic                           clk                ,
    input   logic                           rst_n              ,
    input   logic                           external_interrupt ,
    input   logic                           timer_interrupt    ,
    //output to vector processor
    output  logic                           vector_valid       ,
    input   logic                           vector_ready       ,
    output  to_vector                       vector_instruction ,
    output  logic                           vector_flush_valid ,
    //Input from ICache 
    output  logic [31:0]                    current_pc         ,
    input   logic                           hit_icache         ,
    input   logic                           miss_icache        ,
    input   logic                           partial_access     ,
    input   logic [1:0]                     partial_type       ,
    input   logic [        FETCH_WIDTH-1:0] fetched_data       ,
    // Writeback into DCache (stores)
    output  logic                           cache_wb_valid_o   ,
    output  logic [         31:0]           cache_wb_addr_o    ,
    output  logic [         DATA_WIDTH-1:0] cache_wb_data_o    ,
    output  logic [      MICROOP_WIDTH-1:0] cache_wb_microop_o ,
    // Load for DCache
    output  logic                           cache_load_valid   ,
    output  logic [          31:0]          cache_load_addr    ,
    output  logic [           PR_WIDTH-1:0] cache_load_dest    ,
    output  logic [      MICROOP_WIDTH-1:0] cache_load_microop ,
    output  logic [$clog2(ROB_ENTRIES)-1:0] cache_load_ticket  ,
    //Misc
    input   ex_update                       cache_fu_update    ,
    input   logic                           cache_store_blocked,
    input   logic                           cache_load_blocked ,
    input   logic                           cache_will_block   ,
    output  logic                           ld_st_output_used
);
	localparam ROB_INDEX_BITS = $clog2(ROB_ENTRIES);
	localparam C_NUM          = MAX_BRANCH_IF      ;
    //////////////////////////////////////////////////
    //              Instruction Fetch               //
    //////////////////////////////////////////////////
    fetched_packet dummy_fetched_packet;
    localparam     PACKET_SIZE = $bits(dummy_fetched_packet);
    logic [2*PACKET_SIZE-1 : 0] if_data_out         ;
    logic                       if_valid_o          ;
    logic                       if_ready_in         ;

    logic                       is_branch           ;
    predictor_update            pr_update_o         ;

    logic                       invalid_instruction ;
    logic                       invalid_prediction  ; 
    logic                       is_return           ;          
    logic                       is_jumpl            ;           
    logic [31:0]                old_pc              ;  
    logic                       flush_valid         ;
    logic [31:0]                flush_address       ;

    ifetch 
    #(
        .PACKET_SIZE        (PACKET_SIZE        ),

        .GSH_HISTORY_BITS   (GSH_HISTORY_BITS   ),
        .GSH_SIZE           (GSH_SIZE           ),
        .BTB_SIZE           (BTB_SIZE           ),
        .RAS_DEPTH          (RAS_DEPTH          )
    )instruction_fetch
    (
        .clk                (clk                ),
        .rst_n              (rst_n              ),
        //instruction
        .data_out           (if_data_out        ),
        .valid_o            (if_valid_o         ),
        .ready_in           (if_ready_in        ),
        //Predictor Update Interface
        .is_branch          (is_branch          ),//from decode
        .pr_update          (pr_update_o        ),//from wb
        //Restart Interface
        .invalid_instruction(invalid_instruction),
        .invalid_prediction (invalid_prediction ),
        .is_return_in       (is_return          ),
        .is_jumpl           (is_jumpl           ),
        .old_pc             (old_pc             ),
        //Flush Interface
        .must_flush         (flush_valid        ),//from flush controller
        .correct_address    (flush_address      ),
        //ICache Interface
        .current_pc         (current_pc         ),
        .hit_cache          (hit_icache         ),
        .miss               (miss_icache        ),
        .partial_access     (partial_access     ),
        .partial_type       (partial_type       ),
        .fetched_data       (fetched_data       )    
    );   
    //////////////////////////////////////////////////
    //             Instruction Buffer               //
    //////////////////////////////////////////////////
    //取指译码解耦，以匹配前后端速度差异
    fetched_packet              packet_a, packet_b;
    logic [2*PACKET_SIZE-1:0]   data_if_id_o;
    logic                       id_valid_i  ;
    logic                       id_ready_o  ;

    ibuffer
    #(
        .DW         (2*PACKET_SIZE  ),
        .DEPTH      (4              )         
    )instruction_buffer
    (
        .clk        (clk            ),
        .rst_n      (rst_n          ),

        .valid_flush(flush_valid    ),
        //fetch two instruction
        .data_i     (if_data_out    ),
        .valid_i    (if_valid_o & ~partial_access),
        .ready_o    (if_ready_in    ),
        //output to decode
        .data_o     (data_if_id_o   ),
        .valid_o    (id_valid_i     ),
        .ready_i    (id_ready_o     )
    );
    //divide to two instr
    assign packet_a = data_if_id_o[PACKET_SIZE-1:0];
    assign packet_b = data_if_id_o[2*PACKET_SIZE-1:PACKET_SIZE];

    //////////////////////////////////////////////////
    //             Instruction Decode               //
    //////////////////////////////////////////////////
    predictor_update      pr_update1_o;
    predictor_update      pr_update2_o;
	logic                             id_rr_ready  ;
    logic                             id_valid_1   ;
	logic                             id_valid_2   ;
	decoded_instr                     id_decoded_1 ;
	decoded_instr                     id_decoded_2 ;
    logic [1:0]                     output1_branch_id;
    logic [1:0]                     output2_branch_id;
    logic [$clog2(C_NUM)-1:0]         flush_rat_id ;
    logic [ROB_INDEX_BITS-1:0]        flush_rob_ticket;
    idecode 
    #(
        .ROB_INDEX_BITS     (ROB_INDEX_BITS         ),
        .MAX_BRANCH_IF      (MAX_BRANCH_IF          )
    )instruction_decode
    (
        .clk                (clk                    ),
        .rst_n              (rst_n                  ),
        //Port towards IF
        .valid_i            (id_valid_i             ),
        .ready_o            (id_ready_o             ),
        .taken_branch_1     (packet_a.taken_branch  ),
        .pc_in_1            (packet_a.pc            ),
        .instruction_in_1   (packet_a.data          ),
        .taken_branch_2     (packet_b.taken_branch  ),
        .pc_in_2            (packet_b.pc            ),
        .instruction_in_2   (packet_b.data          ),
        //Output Port towards IF (Redirection Ports)
        .is_branch          (is_branch              ),//one of instr is branch
        .invalid_instruction(invalid_instruction    ),
        .invalid_prediction (invalid_prediction     ),//misPredicted taken on non-branch instruction
        .is_return          (is_return              ),
        .is_jumpl           (is_jumpl               ),
        .old_pc             (old_pc                 ),
        //Port towards RR (instruction queue)
        .ready_i            (id_rr_ready            ), //must indicate at least 2 free slots in queue
        .valid_o            (id_valid_1             ), //indicates first push
        .output1            (id_decoded_1           ),
        .output1_branch_id  (output1_branch_id      ),
        .valid_o_2          (id_valid_2             ), //indicates second push
        .output2            (id_decoded_2           ),
        .output2_branch_id  (output2_branch_id      ),
        //Predictor Update Port
        .pr_update1         (pr_update1_o           ),//from wb
        .pr_update2         (pr_update2_o           ),
        //Flush Port
        .must_flush         (flush_valid            ),//to if&rr
        .delayed_flush      (),//useless
        .correct_address    (flush_address          ),//to if
        .rob_ticket         (flush_rob_ticket       ),//to rob
        .flush_rat_id       (flush_rat_id           )//to rr
    );

    //////////////////////////////////////////////////
    //           ID/RR PIPELINE REGISTER            //
    //////////////////////////////////////////////////
    localparam DECODE_OUTPUT_SIZE = 2*$bits(id_decoded_1) + 6;

    logic                          id_ir_valid_o;
    logic                          rr_ready;
    logic [DECODE_OUTPUT_SIZE-1:0] id_ir_data;
    logic [DECODE_OUTPUT_SIZE-1:0] id_ir_data_o;
    assign id_ir_data = {output2_branch_id,output1_branch_id,id_valid_1,id_valid_2,id_decoded_2,id_decoded_1};

    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1               ),
        .DATA_WIDTH         (DECODE_OUTPUT_SIZE ),
        .GATING_FRIENDLY    (1'b1               )
    )u_id_rr
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (id_valid_1         ),
        .ready_out          (id_rr_ready        ),
        .data_in            (id_ir_data         ),

        .valid_out          (id_ir_valid_o      ),
        .ready_in           (rr_ready           ),
        .data_out           (id_ir_data_o       )
    );
	decoded_instr id_decoded_1_o;
	decoded_instr id_decoded_2_o;
    logic [1:0] branch_id1,branch_id2;
    localparam DECODED_SIZE = $bits(id_decoded_1);
    assign id_decoded_1_o = id_ir_data_o[0 +: DECODED_SIZE];
    assign id_decoded_2_o = id_ir_data_o[DECODED_SIZE +: DECODED_SIZE];
    assign id_valid_2_o   = id_ir_data_o[DECODE_OUTPUT_SIZE-6];
    assign id_valid_1_o   = id_ir_data_o[DECODE_OUTPUT_SIZE-5];
    assign branch_id1     = id_ir_data_o[DECODE_OUTPUT_SIZE-3:DECODE_OUTPUT_SIZE-4];
    assign branch_id2     = id_ir_data_o[DECODE_OUTPUT_SIZE-1:DECODE_OUTPUT_SIZE-2]; 
    //////////////////////////////////////////////////
    //              Register Renaming               //
    //////////////////////////////////////////////////
    writeback_toARF retired_instruction_o, retired_instruction_o_2;
    logic iq_ready1;
    logic iq_ready2;
    logic rr_valid_1;
    logic rr_valid_2;      
    renamed_instr rr_instruction_1;
    renamed_instr rr_instruction_2;      

    to_issue        rob_status           ;
	new_entries     new_rob_requests     ;
    new_entries     rob_requests     ;
    rr 
    #( 
        .P_REGISTERS     (PHYSICAL_REGISTERS),
        .L_REGISTERS     (32                ),
        .ROB_INDEX_BITS  (ROB_INDEX_BITS    ),
        .C_NUM           (2                 ),
        .VECTOR_ENABLED  (VECTOR_ENABLED    )
    )register_renaming
    (
        .clk                (clk  ),
        .rst_n              (rst_n),
        //Port towards ID
        .ready_o            (rr_ready                    ),
        .valid_i_1          (id_ir_valid_o & id_valid_1_o),
        .branch_id1         (branch_id1),
        .instruction_1      (id_decoded_1_o              ),
        .valid_i_2          (id_ir_valid_o & id_valid_2_o),
        .instruction_2      (id_decoded_2_o              ),
        .branch_id2         (branch_id2),
        //Port towards IS
        .ready_i            (iq_ready1 & iq_ready2       ),
        .valid_o_1          (rr_valid_1                  ),
        .instruction_o_1    (rr_instruction_1            ),
        .valid_o_2          (rr_valid_2                  ),
        .instruction_o_2    (rr_instruction_2            ),
        //Port towards ROB
        .rob_status         (rob_status                  ),
        .rob_requests       (new_rob_requests            ),
        //Commit Port
        .commit_1           (retired_instruction_o       ),
        .commit_2           (retired_instruction_o_2     ),
        //Flush Port
        .flush_valid        (flush_valid                 ),
        .pr_update          (pr_update_o                 ),//from wb
        .flush_rat_id       (flush_rat_id                ) 
    ); 
    always_comb begin
        if(~new_rob_requests.valid_request_1 & new_rob_requests.valid_request_2) begin
            rob_requests.valid_request_1     = new_rob_requests.valid_request_2;                         
            rob_requests.valid_dest_1        = new_rob_requests.valid_dest_2;                           
            rob_requests.csr_store_pending_1 = new_rob_requests.csr_store_pending_2;                      
            rob_requests.lreg_1              = new_rob_requests.lreg_2;                               
            rob_requests.preg_1              = new_rob_requests.preg_2;                               
            rob_requests.ppreg_1             = new_rob_requests.ppreg_2;                                 
            rob_requests.microoperation_1    = new_rob_requests.microoperation_2;                       
            rob_requests.pc_1                = new_rob_requests.pc_2;                                   
            rob_requests.csr_1               = new_rob_requests.csr_2; 

            rob_requests.valid_request_2     = new_rob_requests.valid_request_1;                         
            rob_requests.valid_dest_2        = new_rob_requests.valid_dest_1;                           
            rob_requests.csr_store_pending_2 = new_rob_requests.csr_store_pending_1;                      
            rob_requests.lreg_2              = new_rob_requests.lreg_1;                               
            rob_requests.preg_2              = new_rob_requests.preg_1;                               
            rob_requests.ppreg_2             = new_rob_requests.ppreg_1;                                 
            rob_requests.microoperation_2    = new_rob_requests.microoperation_1;                       
            rob_requests.pc_2                = new_rob_requests.pc_1;                                   
            rob_requests.csr_2               = new_rob_requests.csr_1;                                
        end
        else begin
            rob_requests.valid_request_1     = new_rob_requests.valid_request_1;                         
            rob_requests.valid_dest_1        = new_rob_requests.valid_dest_1;                           
            rob_requests.csr_store_pending_1 = new_rob_requests.csr_store_pending_1;                      
            rob_requests.lreg_1              = new_rob_requests.lreg_1;                               
            rob_requests.preg_1              = new_rob_requests.preg_1;                               
            rob_requests.ppreg_1             = new_rob_requests.ppreg_1;                                 
            rob_requests.microoperation_1    = new_rob_requests.microoperation_1;                       
            rob_requests.pc_1                = new_rob_requests.pc_1;                                   
            rob_requests.csr_1               = new_rob_requests.csr_1; 

            rob_requests.valid_request_2     = new_rob_requests.valid_request_2;                         
            rob_requests.valid_dest_2        = new_rob_requests.valid_dest_2;                           
            rob_requests.csr_store_pending_2 = new_rob_requests.csr_store_pending_2;                      
            rob_requests.lreg_2              = new_rob_requests.lreg_2;                               
            rob_requests.preg_2              = new_rob_requests.preg_2;                               
            rob_requests.ppreg_2             = new_rob_requests.ppreg_2;                                 
            rob_requests.microoperation_2    = new_rob_requests.microoperation_2;                       
            rob_requests.pc_2                = new_rob_requests.pc_2;                                   
            rob_requests.csr_2               = new_rob_requests.csr_2;   
        end
    end
 
    localparam IQ_SIZE = $bits(rr_instruction_1);

    //////////////////////////////////////////////////
    //                  Issue Queue                 //
    //////////////////////////////////////////////////
    logic iq_valid_1;
    logic iq_valid_2; 
    logic issue_1;
    logic issue_2;
    renamed_instr iq_instruction_1;
    renamed_instr iq_instruction_2;
    
    fifo_dual_ported 
    #(
        .DW                 (IQ_SIZE),
        .DEPTH              (IQ_DEPTH)
    )issue_queue
    (
        .clk        (clk             ),
        .rst        (!rst_n          ),
        
        .valid_flush(flush_valid),
              
        .push_1     (rr_valid_1      ),
        .ready_1    (iq_ready1       ),
        .push_data_1(rr_instruction_1),
    
        .push_2     (rr_valid_2      ),
        .ready_2    (iq_ready2       ),
        .push_data_2(rr_instruction_2),
        
        .pop_data_1 (iq_instruction_1),
        .valid_1    (iq_valid_1      ),
        .pop_1      (issue_1         ),
        
        .pop_data_2 (iq_instruction_2),
        .valid_2    (iq_valid_2      ),
        .pop_2      (issue_2         )
    );
    //////////////////////////////////////////////////
    //                  Issue Logic                 //
    //////////////////////////////////////////////////
    to_execution [1:0]  t_execution;
    ex_update [3:0]     fu_update1;
    ex_update [3:0]     fu_update2;
    ex_update [3:0]     fu_update1_o;
    ex_update [3:0]     fu_update2_o;
    logic [3:0]             busy_fu;
    logic                   flush_ready       ;
    logic [ROB_ENTRIES-1:0] flush_vector      ;
    logic [ROB_ENTRIES-1:0] flush_vector_o    ;
    logic [3:0][ROB_INDEX_BITS-1:0] read_addr_rob;
    logic [3:0][31:0]               data_out_rob;
    issue
    #(
        .REGFILE_ADDR_WIDTH   (6    ),
        .DEPTH                (4    ),
        .ROB_INDEX_BITS       ($clog2(ROB_ENTRIES)),
        .SCOREBOARD_SIZE      (PHYSICAL_REGISTERS)
    )issue_logic
    (
        .clk             (clk  ),
        .rst_n           (rst_n),
        //toward rr                     
        .issue_1         (issue_1           ),
        .iq_instr1_valid (iq_valid_1 & ~flush_valid),
        .iq_instr1       (iq_instruction_1  ),
        .issue_2         (issue_2           ),
        .iq_instr2_valid (iq_valid_2 & ~flush_valid),
        .iq_instr2       (iq_instruction_2  ),  
        //Retired Instruction
        .writeback_1     (retired_instruction_o  ),
        .writeback_2     (retired_instruction_o_2),
        //Flush Interface
        .pr_update       (pr_update_o              ),//useless
        .flush_valid     (flush_ready           ),
        .flush_vector_inv(flush_vector_o),
        //Busy Signals from Functional Units
        .busy_fu         (busy_fu       ),
        //Outputs from Functional Units
        .fu_update1      (fu_update1_o),//wb bypass
        .fu_update2      (fu_update2_o),//wb bypass
        .fu_update_frw1  (fu_update1),//ex bypass
        .fu_update_frw2  (fu_update2),//ex bypass
        //Forward Port from ROB
        .read_addr_rob   (read_addr_rob),
        .data_out_rob    (data_out_rob ),
        //toward ex
        .t_execution        (t_execution),
        .vector_valid       (vector_valid      ),	
        .vector_ready       (vector_ready      ),	
        .vector_instruction (vector_instruction)    
    ); 
    //////////////////////////////////////////////////
    //            IS/EX PIPELINE REGISTER           //
    //////////////////////////////////////////////////
	localparam TO_EX_DW  = $bits(t_execution[0]);
	localparam ISSUED_DW = 2*TO_EX_DW + $bits(rob_requests);

	logic [ISSUED_DW-1:0] issued_data_merged  ;
	logic [ISSUED_DW-1:0] issued_data_merged_o;
	to_execution[1 : 0]   t_execution_o;
	//new_rob_requests打一拍同步
    //Load/Store指令交给EX0处理
/*
	assign issued_data_merged = ((t_execution[1].functional_unit==00)|(t_execution[1].functional_unit==01)&t_execution[1].valid) 
                                ? {new_rob_requests, t_execution[0] , t_execution[1]} :
                                  {new_rob_requests, t_execution[1] , t_execution[0]};*/
	assign issued_data_merged = ((t_execution[1].valid & ((t_execution[1].functional_unit==00) | (t_execution[1].functional_unit==01))) | (t_execution[1].valid & t_execution[1].is_vector))
                                ? {rob_requests, t_execution[0] , t_execution[1]} :
                                  {rob_requests, t_execution[1] , t_execution[0]};
    //assign vector_valid       = (t_execution[0].valid & t_execution[0].is_vector) | (t_execution[1].valid & t_execution[1].is_vector); 
    //assign vector_instruction = (t_execution[0].valid & t_execution[0].is_vector) ? t_execution[0] : t_execution[1];
    assign vector_flush_valid = flush_valid;

    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1               ),
        .DATA_WIDTH         (ISSUED_DW          ),
        .GATING_FRIENDLY    (1'b1               )
    )u_is_ex
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (1'b1),
        .ready_out          (),
        .data_in            (issued_data_merged),

        .valid_out          (),
        .ready_in           (1'b1),
        .data_out           (issued_data_merged_o)
    );

    //////////////////////////////////////////////////
    //                Execute-Stage                 //
    //////////////////////////////////////////////////
    logic                      cache_store_valid  ;
    logic [31:0]               cache_store_address;
    logic [31:0]               cache_store_data   ;
    logic [ROB_INDEX_BITS-1:0] cache_store_ticket ;
	logic [31:0]               cache_frw_address;
	logic [31:0]               cache_frw_data;
	logic [ MICROOP_WIDTH-1:0] cache_frw_microop;
	logic                      cache_frw_valid;
	logic                      cache_frw_stall;
    predictor_update  pr_update1;
    predictor_update  pr_update2;
    csr_update        csr_update;
    writeback_toARF retired_instruction, retired_instruction_2;
    assign t_execution_o[0]   = issued_data_merged_o[0+:TO_EX_DW];
    assign t_execution_o[1]   = issued_data_merged_o[TO_EX_DW+:TO_EX_DW];
    ex
    #(
        .FU_NUMBER                  (4 ),
        .R_ADDR                     (6 ),
        .MICROOP_WIDTH              (5 ),
        .ROB_INDEX_BITS             (3 ),
        .CSR_DEPTH                  (64),
        .EX0                        (1 )
    )u0_execute_stage
    (
        .clk                        (clk  ),
        .rst_n                      (rst_n),
        .external_interrupt         (external_interrupt),
        .timer_interrupt            (timer_interrupt),

        .t_execution                (t_execution_o[0]),
        .cache_fu_update            (cache_fu_update),
        .cache_load_blocked         (cache_load_blocked),
        .cache_writeback_valid      (cache_wb_valid_o),

        .frw_address                (cache_frw_address      ),
        .frw_microop                (cache_frw_microop      ),
        .frw_data                   (cache_frw_data         ),
        .frw_valid                  (cache_frw_valid        ),
        .frw_stall                  (cache_frw_stall        ),

        .store_valid                (cache_store_valid      ),
        .store_address              (cache_store_address    ),
        .store_data                 (cache_store_data       ),
        .store_microop              (                       ),
        .store_ticket               (cache_store_ticket     ),

        .cache_load_valid           (cache_load_valid   ),
        .cache_load_addr            (cache_load_addr    ),
        .cache_load_dest            (cache_load_dest    ),
        .cache_load_microop         (cache_load_microop ),
        .cache_load_ticket          (cache_load_ticket  ),

        .output_used                (ld_st_output_used),
        .busy_fu                    (busy_fu[1:0]),//0:lsu 1:alu
        .fu_update                  (fu_update1),
        .pr_update                  (pr_update1),
        .csr_update                 (csr_update),

        .rob_data_1                 (retired_instruction  ),
        .rob_data_2                 (retired_instruction_2),
        .commit_1                   (retired_instruction_o  ),  
        .commit_2                   (retired_instruction_o_2)
    );
    ex
    #(
        .FU_NUMBER                  (4 ),
        .R_ADDR                     (6 ),
        .MICROOP_WIDTH              (5 ),
        .ROB_INDEX_BITS             (3 ),
        .CSR_DEPTH                  (64),
        .EX0                        (0 )
    )u1_execute_stage
    (
        .clk                        (clk  ),
        .rst_n                      (rst_n),
        .external_interrupt         (),
        .timer_interrupt            (),

        .t_execution                (t_execution_o[1]),
        .cache_fu_update            (),
        .cache_load_blocked         (),
        .cache_writeback_valid      (),

        .frw_address                (),
        .frw_microop                (),
        .frw_data                   (),
        .frw_valid                  (),
        .frw_stall                  (),

        .store_valid                (),
        .store_address              (),
        .store_data                 (),
        .store_microop              (),
        .store_ticket               (),
        
        .cache_load_valid           (),
        .cache_load_addr            (),
        .cache_load_dest            (),
        .cache_load_microop         (),
        .cache_load_ticket          (),

        .output_used                (),
        .busy_fu                    (busy_fu[3:2]),//0:alu 1:useless
        .fu_update                  (fu_update2),
        .pr_update                  (pr_update2),
        .csr_update                 (csr_update),

        .rob_data_1                 (),
        .rob_data_2                 (),
        .commit_1                   (),  
        .commit_2                   ()
    );

    //////////////////////////////////////////////////
    //           EX/WB PIPELINE REGISTER            //
    //////////////////////////////////////////////////
	localparam FU_UPDATE_DW = $bits(fu_update1[0])              ;
	localparam EX_MERGED_DW = 4*FU_UPDATE_DW + $bits(pr_update1);
    logic      [EX_MERGED_DW-1:0] data_ex_merged1_i   ;
    logic      [EX_MERGED_DW-1:0] data_ex_merged2_i   ;
    logic      [EX_MERGED_DW-1:0] data_ex_merged1_o   ;
    logic      [EX_MERGED_DW-1:0] data_ex_merged2_o   ;
    assign data_ex_merged1_i = {pr_update1,fu_update1[3],fu_update1[2],fu_update1[1],fu_update1[0]};
    assign data_ex_merged2_i = {pr_update2,fu_update2[3],fu_update2[2],fu_update2[1],fu_update2[0]};
    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1               ),
        .DATA_WIDTH         (EX_MERGED_DW       ),
        .GATING_FRIENDLY    (1'b1               )
    )u0_ex_wb
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (1'b1),
        .ready_out          (),
        .data_in            (data_ex_merged1_i),

        .valid_out          (),
        .ready_in           (1'b1),
        .data_out           (data_ex_merged1_o)
    );

    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1               ),
        .DATA_WIDTH         (EX_MERGED_DW       ),
        .GATING_FRIENDLY    (1'b1               )
    )u1_ex_wb
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (1'b1),
        .ready_out          (),
        .data_in            (data_ex_merged2_i),

        .valid_out          (),
        .ready_in           (1'b1),
        .data_out           (data_ex_merged2_o)
    );

	assign fu_update1_o[0] = data_ex_merged1_o[0+:FU_UPDATE_DW];
	assign fu_update1_o[1] = data_ex_merged1_o[FU_UPDATE_DW+:FU_UPDATE_DW];
	assign fu_update1_o[2] = data_ex_merged1_o[2*FU_UPDATE_DW+:FU_UPDATE_DW];
	assign fu_update1_o[3] = data_ex_merged1_o[3*FU_UPDATE_DW+:FU_UPDATE_DW];
	assign pr_update1_o    = data_ex_merged1_o[4*FU_UPDATE_DW+:$bits(pr_update1)];

	assign fu_update2_o[0] = data_ex_merged2_o[0+:FU_UPDATE_DW];
	assign fu_update2_o[1] = data_ex_merged2_o[FU_UPDATE_DW+:FU_UPDATE_DW];
	assign fu_update2_o[2] = data_ex_merged2_o[2*FU_UPDATE_DW+:FU_UPDATE_DW];
	assign fu_update2_o[3] = data_ex_merged2_o[3*FU_UPDATE_DW+:FU_UPDATE_DW];
	assign pr_update2_o    = data_ex_merged2_o[4*FU_UPDATE_DW+:$bits(pr_update2)];

    assign csr_update.is_csr = fu_update1_o[1].is_csr;
    assign csr_update.csr_addr = fu_update1_o[1].csr_addr;
    assign csr_update.csr_wdata = fu_update1_o[1].csr_wdata;
    assign pr_update_o = pr_update1_o.jump_taken ? pr_update1_o : 
                         pr_update2_o.jump_taken ? pr_update2_o : pr_update1_o;
    //////////////////////////////////////////////////
    //              Write Back-Stage                //
    //////////////////////////////////////////////////
    logic                       store_ready;
    logic                       cache_wb_valid     ;
    logic [31:0]                cache_wb_addr      ;
    logic [31:0]                cache_wb_data      ;
    logic [MICROOP_WIDTH-1:0]   cache_wb_microop   ;

    
    rob #(
        .ROB_ENTRIES    (ROB_ENTRIES),
        .FU_NUMBER      (4),
        .ROB_INDEX_BITS (ROB_INDEX_BITS) 
    )u_rob
    (
        .clk                 (clk           ),
        .rst_n               (rst_n         ),

        .read_address        (read_addr_rob ),       
        .data_out            (data_out_rob  ),       
        //Update from EX (Input Interface)
        .update1             (fu_update1_o),
        .update2             (fu_update2_o),
        //Interface with IS
        .new_requests        (rob_requests),
        .t_issue             (rob_status),
        .writeback_1         (retired_instruction  ),
        .writeback_2         (retired_instruction_2),

        .flush_valid         (flush_valid),
        .flush_ticket        (flush_rob_ticket),
        .flush_vector_inv    (flush_vector),
        //Data Cache Interface (Search Interface)       
    
        .cache_addr              (cache_frw_address),
        .cache_microop           (cache_frw_microop),
        .cache_data              (cache_frw_data   ),
        .cache_valid             (cache_frw_valid  ),
        .cache_stall             (cache_frw_stall  ),
        //STORE update from Data Cache (Input Interface) 
        .cache_blocked           (~store_ready),       
        .store_valid             (cache_store_valid     ),
        .store_data              (cache_store_data      ),
        .store_ticket            (cache_store_ticket    ),
        .store_address           (cache_store_address   ),
        //writeback into Cache (Output Interface)
        .cache_writeback_valid   (cache_wb_valid        ),
        .cache_writeback_addr    (cache_wb_addr         ),
        .cache_writeback_data    (cache_wb_data         ),
        .cache_writeback_microop (cache_wb_microop      ) 
    );
    //////////////////////////////////////////////////
    //           WB/RT PIPELINE REGISTER            //
    //////////////////////////////////////////////////
    localparam RETIRED_IS = $bits(retired_instruction);
    localparam RETIRED_ST = $bits(cache_wb_addr)+$bits(cache_wb_data)+$bits(cache_wb_microop)+1;

    logic [2*RETIRED_IS-1:0] retired_merged        ;
    logic [2*RETIRED_IS-1:0] retired_merged_o      ;
    logic [  RETIRED_ST-1:0] retired_merged_store  ;
    logic [  RETIRED_ST-1:0] retired_merged_store_o;

    assign retired_merged       = {cache_wb_valid,cache_wb_microop,cache_wb_data,cache_wb_addr,retired_instruction_2,retired_instruction};
    assign retired_merged_store = {cache_wb_valid,cache_wb_microop,cache_wb_data,cache_wb_addr};

    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1               ),
        .DATA_WIDTH         (2*RETIRED_IS       ),
        .GATING_FRIENDLY    (1'b1               )
    )writeback_retire
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (1'b1),
        .ready_out          (),
        .data_in            (retired_merged),

        .valid_out          (),
        .ready_in           (1'b1),
        .data_out           (retired_merged_o)
    );

    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1      ),
        .DATA_WIDTH         (RETIRED_ST),
        .GATING_FRIENDLY    (1'b1      )
    )retire_store
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (cache_wb_valid),
        .ready_out          (store_ready),
        .data_in            (retired_merged_store),

        .valid_out          (cache_wb_valid_o),
        .ready_in           (~cache_store_blocked),
        .data_out           (retired_merged_store_o)
    );
    assign retired_instruction_o   = retired_merged_o[RETIRED_IS-1 : 0];
    assign retired_instruction_o_2 = retired_merged_o[2*RETIRED_IS-1 : RETIRED_IS];
    assign cache_wb_addr_o         = retired_merged_store_o[31 : 0];
    assign cache_wb_data_o         = retired_merged_store_o[31+DATA_WIDTH : 32];
    assign cache_wb_microop_o      = retired_merged_store_o[31+DATA_WIDTH+MICROOP_WIDTH : 32+DATA_WIDTH];
    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1               ),
        .DATA_WIDTH         (ROB_ENTRIES),
        .GATING_FRIENDLY    (1'b1               )
    )flush
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (flush_valid),
        .ready_out          (),
        .data_in            (flush_vector),

        .valid_out          (flush_ready),
        .ready_in           (1'b1),
        .data_out           (flush_vector_o)
    );

    logic               write_En, write_En_2;
    logic [5:0] 		write_Addr_RF, write_Addr_RF_2;
    logic [31:0] 		write_Data, write_Data_2;
	assign write_En        = retired_instruction_o.valid_commit & retired_instruction_o.valid_write & ~retired_instruction_o.flushed;
	assign write_Addr_RF   = retired_instruction_o.ldst;
	assign write_Data      = retired_instruction_o.data;
	assign write_En_2      = retired_instruction_o_2.valid_commit & retired_instruction_o_2.valid_write & ~retired_instruction_o_2.flushed;
	assign write_Addr_RF_2 = retired_instruction_o_2.ldst;
	assign write_Data_2    = retired_instruction_o_2.data;
    register_file 
    #(
        .DATA_WIDTH (32) , 
        .ADDR_WIDTH (5)  , 
        .SIZE       (32) , 
        .READ_PORTS (2)
    )debug_regfile
    (
    	.clk         (clk  ),
    	.rst_n       (rst_n),
    	// Write Port
    	.write_En    (write_En     ),
    	.write_Addr  (write_Addr_RF[4:0]),
    	.write_Data  (write_Data   ),
    	// Write Port
    	.write_En_2  (write_En_2     ),
    	.write_Addr_2(write_Addr_RF_2[4:0]),
    	.write_Data_2(write_Data_2   ),
    	// Read Port
    	.read_Addr   (),
    	.data_Out    ()   
    );
endmodule  