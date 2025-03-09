module ifetch 
#(
    parameter int PACKET_SIZE      = 65  ,
    parameter int GSH_HISTORY_BITS = 12  ,
    parameter int GSH_SIZE         = 256 ,
    parameter int BTB_SIZE         = 256 ,
    parameter int RAS_DEPTH        = 8   
)
(
    input  logic                        clk                 ,
    input  logic                        rst_n               ,
    //Output Interface(towards ibuf)
    output logic [2*PACKET_SIZE-1:0]    data_out            ,
    output logic                        valid_o             ,
    input  logic                        ready_in            ,//ibuffer is not full
    //Flush Interface(from flush controller)
    input  logic                        must_flush          ,
    input  logic [31:0]                 correct_address     ,
    
    input  logic                        is_branch           ,//from decode
    //Predictor Update Interface
    /*
    (If there are two branch instructions, select the result of the jump from the two to update the BPU)    
    (However, this approach will ignore the update of PHT by the non-jump instruction.)
    */
    input  predictor_update             pr_update           ,//from wb
    //Restart Interface
    input  logic                        invalid_instruction ,
    input  logic                        invalid_prediction  ,
    input  logic                        is_return_in        ,   
    input  logic                        is_jumpl            ,
    input  logic [31:0]                 old_pc              ,
    //ICache Interface
    output logic [31:0]                 current_pc          ,
    input  logic                        hit_cache           ,
    input  logic                        miss                ,
    input  logic                        partial_access      ,
    input  logic [1:0]                  partial_type        ,
    input  logic [63:0]                 fetched_data        
);   

    typedef enum logic [ 1:0] {NONE, LOW, HIGH} override_priority;
    override_priority         over_priority      ;

    logic              [63:0] instruction_out;
    logic              [31:0] next_pc      ;
    logic              [31:0] next_pc_2    ;
    logic              [31:0] pc_orig      ;
    logic              [31:0] target_pc    ;
    logic              [31:0] saved_pc     ;
    logic              [31:0] next_pc_saved;
    logic              [31:0] old_pc_saved ;
    logic              [47:0] partial_saved_instr;
    logic              [ 1:0] partial_type_saved ;

    logic                     hit                ;
    logic                     new_entry          ;
    logic                     is_taken           ;
    logic                     is_return          ;
    logic                     is_return_fsm      ;
    logic                     taken_branch_saved ;
    logic                     taken_branch_1     ;
    logic                     half_access        ;
    logic                     taken_branch_2     ;
    fetched_packet packet_a, packet_b;

    assign data_out              = {packet_b,packet_a};
    //icache crossing line
    assign packet_a.pc           = half_access? old_pc_saved : current_pc;
    assign packet_a.data         = instruction_out[31:0];
    assign packet_a.taken_branch = half_access ? taken_branch_saved : taken_branch_1;
    assign packet_b.pc           = half_access ? current_pc : current_pc+4;
    assign packet_b.data         = instruction_out[63:32];
    assign packet_b.taken_branch = half_access ? taken_branch_1 : taken_branch_2;
    assign valid_o = half_access ? hit       & (over_priority==NONE) & ~(is_return_in | is_return_fsm) & ~invalid_prediction & ~must_flush & ~invalid_instruction :
                                   hit_cache & (over_priority==NONE) & ~(is_return_in | is_return_fsm) & ~invalid_prediction & ~must_flush & ~invalid_instruction & ~taken_branch_1;
    //bpu update signal
    assign new_entry = pr_update.valid_jump;
    assign pc_orig   = pr_update.orig_pc;
    assign target_pc = pr_update.jump_address;
    assign is_taken  = pr_update.jump_taken;
    //- Might need to use FSM for is_return_in if it's not constantly supplied from the IF/ID
    assign is_return = (is_return_in | is_return_fsm) & hit;      
    always_ff @(posedge clk or negedge rst_n) begin 
        if(!rst_n) begin
            is_return_fsm <= 0;
        end else begin
            if(!is_return_fsm && is_return_in && !hit) begin
                is_return_fsm <= ~must_flush;
            end else if(is_return_fsm && hit) begin
                is_return_fsm <= 0;
            end
        end
    end

    predictor 
    #(
        .GSH_HISTORY_BITS   (GSH_HISTORY_BITS       ),
        .GSH_SIZE           (GSH_SIZE               ),
        .BTB_SIZE           (BTB_SIZE               ),
        .RAS_DEPTH          (RAS_DEPTH              )
    )u_branch_predictor 
    (
        .clk                (clk                    ),
        .rst_n              (rst_n                  ),
	    //Control Interface 
        .must_flush         (must_flush             ),
        .is_branch          (is_branch              ),
        .branch_resolved    (pr_update.valid_jump   ),
	    //Update Interface  
        .new_entry          (new_entry              ),
        .pc_orig            (pc_orig                ),
        .target_pc          (target_pc              ),
        .is_taken           (is_taken               ),
	    //RAS Interface 
        .is_return          (is_return              ),
        .is_jumpl           (is_jumpl               ),
        .invalidate         (invalid_prediction     ),
        .old_pc             (old_pc                 ),
        //Access Interface  
        .pc_in              (current_pc             ),
        .taken_branch_a     (taken_branch_1         ),
        .next_pc_a          (next_pc                ),
        .taken_branch_b     (taken_branch_2         ),
        .next_pc_b          (next_pc_2              )
    );
    // Create the Output
    assign hit = hit_cache & ~partial_access;
    always_comb begin 
        if(half_access) begin//crossing line
            if(partial_type_saved == 2'b11) begin
                instruction_out = {fetched_data[15:0],partial_saved_instr[15:0]};
            end else if(partial_type_saved == 2'b10) begin
                instruction_out = {fetched_data[31:0],partial_saved_instr[31:0]};
            end else begin
                instruction_out = {fetched_data[47:0],partial_saved_instr[15:0]};
            end
        end else begin
            instruction_out = fetched_data;
        end
    end
    // Two-Cycle Fetch FSM
    always_ff @(posedge clk or negedge rst_n) begin 
        if(!rst_n) begin
            half_access <= 0;
        end else begin
            if(partial_access && !half_access && hit_cache) begin
                half_access <= ~(invalid_prediction | invalid_instruction | is_return_in | must_flush | over_priority!=NONE);
            end else if(taken_branch_1 && !half_access && hit_cache) begin
                half_access <= ~((over_priority!=NONE) | invalid_prediction | invalid_instruction | is_return_in | must_flush);
            end else if(half_access && valid_o && ready_in) begin
                half_access <= 0;
            end else if(half_access && hit_cache) begin
                half_access <= ~((over_priority!=NONE) | invalid_prediction | invalid_instruction | is_return_in | must_flush);
            end
        end
    end
    // Half Instruction Management
    always_ff @(posedge clk) begin
        if(!half_access && hit_cache) begin
            if(partial_access && partial_type == 2'b01) begin
                partial_saved_instr <= {{48{1'b0}},fetched_data[15:0]};
                old_pc_saved        <= current_pc;
                taken_branch_saved  <= 1'b0;
                next_pc_saved       <= current_pc+8;
                partial_type_saved  <= partial_type;
            end else if(taken_branch_1) begin
                partial_saved_instr <= {{32{1'b0}},fetched_data[31:0]};
                old_pc_saved        <= current_pc;
                taken_branch_saved  <= taken_branch_1;
                next_pc_saved       <= next_pc+4;
                partial_type_saved  <= 2'b10;
            end else if(partial_access && partial_type == 2'b10) begin
                partial_saved_instr <= {{32{1'b0}},fetched_data[31:0]};
                old_pc_saved        <= current_pc;
                taken_branch_saved  <= 1'b0;
                next_pc_saved       <= current_pc+8;
                partial_type_saved  <= partial_type;
            end else if(partial_access && partial_type == 2'b11) begin
                partial_saved_instr <= fetched_data[47:0];
                old_pc_saved        <= current_pc;
                taken_branch_saved  <= 1'b0;
                next_pc_saved       <= current_pc+8;
                partial_type_saved  <= partial_type;
            end
        end
    end
    // PC Address Management
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            current_pc <= 0;
        end else begin
            // Normal Operation
            if(hit_cache) begin
                if(over_priority==HIGH) begin
                    current_pc <= saved_pc;
                end else if(must_flush) begin
                    current_pc <= correct_address;
                end else if(over_priority==LOW && is_return_fsm) begin
                    current_pc <= next_pc;
                end else if(over_priority==LOW) begin
                    current_pc <= saved_pc;
                end else if(invalid_prediction) begin
                    current_pc <= old_pc;
                end else if (invalid_instruction) begin
                    current_pc <= old_pc;
                end else if (is_return_in) begin
                    current_pc <= next_pc;
                end else if(partial_access && partial_type== 1 && !half_access) begin
                    current_pc <= current_pc +2;
                end else if(taken_branch_1 && !half_access) begin
                    current_pc <= next_pc;
                end else if (partial_access && partial_type== 2 && !half_access) begin
                    current_pc <= current_pc +4;
                end else if (partial_access && partial_type== 3 && !half_access) begin
                    current_pc <= current_pc +6;
                end else if (ready_in && !half_access) begin
                    current_pc <= taken_branch_2 ? next_pc_2 : next_pc;
                end else if (ready_in && half_access) begin
                    current_pc <= taken_branch_1 ? next_pc : next_pc_saved;
                end
            end
        end
    end
    //Override FSM used to indicate a redirection must happen after cache unblocks
        //Flushing takes priority due to being an older instruction
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            over_priority <= NONE;
        end else begin
            if(must_flush && over_priority!=HIGH && !hit_cache) begin
                over_priority <= HIGH;
                saved_pc      <= correct_address;
            end else if(invalid_prediction && over_priority==NONE && !hit_cache) begin
                over_priority <= LOW;
                saved_pc      <= old_pc;
            end else if(invalid_instruction && over_priority==NONE && !hit_cache) begin
                over_priority <= LOW;
                saved_pc      <= old_pc;
            end else if(is_return_in && over_priority==NONE && !hit_cache) begin
                over_priority <= LOW;
                saved_pc      <= old_pc;
            end else if(hit_cache) begin
                over_priority <= NONE;
            end
        end
    end


    logic [63:0] time_counter, cycle_counter, instr_counter;
// ------------------------------------------------------------------------------------------------ //
    //Time Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            time_counter <= 0;
        end 
        else begin
            time_counter <= cycle_counter+1;
        end
    end
    //Cycle Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cycle_counter <= 0;
        end 
        else begin
            cycle_counter <= cycle_counter +1;
        end
    end
endmodule