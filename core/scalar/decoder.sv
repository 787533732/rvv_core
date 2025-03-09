module decoder
(
    input  logic                  valid_i            ,
    output logic                  ready_o            ,
    input  logic                  taken_branch_1     ,
    input  logic [31:0]           pc_in_1            ,
    input  logic [31:0]           instruction_in_1   ,
    input  logic                  taken_branch_2     ,
    input  logic [31:0]           pc_in_2            ,
    input  logic [31:0]           instruction_in_2   ,

    output logic                  invalid_instruction,
    output logic                  invalid_prediction ,
    output logic                  is_return_out      ,
    output logic                  is_jumpl_out       ,
    output logic [31:0]           old_pc             ,
    //Output Port towards Flush Controller
    output logic                  valid_transaction  ,
    output logic                  valid_branch_32a   ,
    output logic                  valid_branch_32b   ,
    //Port towards IS (instruction queue)
    input  logic                  ready_i            , //must indicate at least 2 free slots in queue
    output logic                  valid_o            , //indicates first push
    output decoded_instr          output1            ,
    output logic                  valid_o_2          , //indicates second push
    output decoded_instr          output2             
);
    logic  valid;
    logic  must_restart_32a,must_restart_32b;
    logic  is_jumpl_a,is_jumpl_b, is_return_32a, is_return_32b;
    logic  invalid_instruction_a, invalid_instruction_b;

    assign valid  = valid_i & ready_i;//取指模块valid 发射模块ready
    assign ready_o = ready_i;
    
    assign valid_o   = valid & ~must_restart_32a;
    assign valid_o_2 = valid & ~invalid_prediction & ~(is_return_32a && valid_o);
    assign valid_transaction = valid_o;

    decoder_full  decoder_full_a
    (
        .valid          (valid_i         ),
        .PC_in          (pc_in_1         ),
        .instruction_in (instruction_in_1),

        .outputs        (output1         ),
        .valid_branch   (valid_branch_32a),
        .is_jumpl       (is_jumpl_a      ),
        .is_return      (is_return_32a   )
    );

    decoder_full  decoder_full_b
    (
        .valid          (valid_i         ), 
        .PC_in          (pc_in_2         ), 
        .instruction_in (instruction_in_2), 

        .outputs        (output2         ), 
        .valid_branch   (valid_branch_32b), 
        .is_jumpl       (is_jumpl_b      ),
        .is_return      (is_return_32b   )
    );
//----------------------------
    //Restart the Fetch on misPredicted taken on non-branch instruction
    assign invalid_prediction = must_restart_32a | must_restart_32b;
    assign must_restart_32a   = taken_branch_1 & ~valid_branch_32a & output1.is_valid;
    assign must_restart_32b   = taken_branch_2 & ~valid_branch_32b & output2.is_valid;

    always_comb begin
        if(must_restart_32a) begin
            old_pc = pc_in_1;
        end else if(invalid_instruction_a) begin
            old_pc = pc_in_1;
        end else if(must_restart_32b) begin
            old_pc = pc_in_2;
        end else if(invalid_instruction_b) begin
            old_pc = pc_in_2;
        end else if(is_jumpl_out) begin
            old_pc = is_jumpl_a ? pc_in_1+4 : pc_in_2+4;
        end else begin
            old_pc = pc_in_1;
        end
    end

    //at least one instruction is jump/return
    assign is_jumpl_out  = valid & ((is_jumpl_a & valid_o) | (is_jumpl_b & valid_o_2));
    assign is_return_out = valid & ((is_return_32a && valid_o) | (is_return_32b && valid_o_2));
    //Restart due to misaligned - invalid instructions
    assign invalid_instruction   = invalid_instruction_a | invalid_instruction_b;
    assign invalid_instruction_a = valid & (~output1.is_valid);//first valid is from fetch
    assign invalid_instruction_b = valid & (~output2.is_valid);//second valid is from decoder_full


endmodule