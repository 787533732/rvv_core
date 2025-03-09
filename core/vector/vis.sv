module vis
#(
    parameter VECTOR_LANES       = 8, 
    parameter VECTOR_TICKET_BITS = 4
)
(
    input   logic                               clk             ,
    input   logic                               rst_n           ,

    input   logic                               valid_in        ,
    input   to_vis                              instr_in        ,
    output  logic                               ready_o         ,      
    //Instruction Out           
    output  logic                               valid_o         ,
    output  to_vector_exec [VECTOR_LANES-1:0]   data_to_exec    ,//dataflow
    output  to_vector_exec_info                 info_to_exec    ,//controlflow
    input   logic                               ready_i         ,
    //VMU访问寄存器锁定状态
    input   logic [1:0][4:0]                    mem_prb_reg_i   ,
    output  logic [1:0]                         mem_prb_locked_o,
    output  logic [1:0][VECTOR_TICKET_BITS-1:0] mem_prb_ticket_o,
    //Memory Unit read ports 访存单元访问VRF
    input   logic [4:0]                         mem_addr_0      ,
    output  logic [VECTOR_LANES*32-1:0]         mem_data_0      ,
    output  logic                               mem_pending_0   ,
    output  logic [VECTOR_TICKET_BITS-1:0]      mem_ticket_0    ,
    input   logic [4:0]                         mem_addr_1      ,
    output  logic [VECTOR_LANES*32-1:0]         mem_data_1      ,
    output  logic                               mem_pending_1   ,
    output  logic [VECTOR_TICKET_BITS-1:0]      mem_ticket_1    ,
    input   logic [4:0]                         mem_addr_2      ,
    output  logic [VECTOR_LANES*32-1:0]         mem_data_2      ,
    output  logic                               mem_pending_2   ,
    output  logic [VECTOR_TICKET_BITS-1:0]      mem_ticket_2    ,
    //Load指令写回
    input   logic [VECTOR_LANES-1:0]            mem_wr_en       ,
    input   logic [VECTOR_TICKET_BITS-1:0]      mem_wr_ticket   ,
    input   logic [4:0]                         mem_wr_addr     ,
    input   logic [VECTOR_LANES*32-1:0]         mem_wr_data     ,
    //向量访存指令会锁定对应的寄存器，执行完成 锁    
    input   logic                               unlock_en       ,
    input   logic [4:0]                         unlock_reg_a    ,
    input   logic [4:0]                         unlock_reg_b    ,
    input   logic [VECTOR_TICKET_BITS-1:0]      unlock_ticket   ,
    //Forward Point #1  
    input   logic [VECTOR_LANES-1:0]            frw_a_en        ,
    input   logic [4:0]                         frw_a_addr      ,
    input   logic [VECTOR_LANES-1:0][31:0]      frw_a_data      ,
    input   logic [VECTOR_TICKET_BITS-1:0]      frw_a_ticket    ,
    //Forward Point #2  
    input   logic [VECTOR_LANES-1:0]            frw_b_en        ,
    input   logic [4:0]                         frw_b_addr      ,
    input   logic [VECTOR_LANES-1:0][31:0]      frw_b_data      ,
    input   logic [VECTOR_TICKET_BITS-1:0]      frw_b_ticket    ,
    //Writeback (Forward Point #3)  
    input   logic [VECTOR_LANES-1:0]            wr_en           ,
    input   logic [4:0]                         wr_addr         ,
    input   logic [VECTOR_LANES-1:0][31:0]      wr_data         ,
    input   logic [VECTOR_TICKET_BITS-1:0]      wr_ticket
);
    logic [VECTOR_LANES-1:0][31:0]          data_1, data_2;
    logic [$clog2(32*VECTOR_LANES):0]       total_remaining_elements;
    logic                                   can_issue,can_issue_m,do_issue;
    logic [VECTOR_LANES-1:0]                can_lock_sources, can_lock_destination;
    logic                                   memory_instr,load_instr;
    logic [VECTOR_LANES-1:0]                issue_masked,issue_m_masked;
    logic [VECTOR_LANES-1:0]                no_hazards, no_hazards_m;
    logic [VECTOR_LANES-1:0]                frw_a_src_1, frw_a_src_2;
    logic [VECTOR_LANES-1:0]                frw_b_src_1, frw_b_src_2;
    logic [VECTOR_LANES-1:0]                frw_c_src_1, frw_c_src_2;
    logic [VECTOR_LANES-1:0]                src1_ok, src2_ok, rdst_ok;
    logic [4:0]                             src_1,src_2,dst;
    logic [4:0]                             current_exp_loop;
    logic [4:0]                             max_expansion;
    logic [VECTOR_LANES-1:0]                valid_output;
    logic                                   expansion_finished, maxvl_reached, vl_reached;
    //scoreboard
    logic [31:0][VECTOR_TICKET_BITS-1:0]    pending_ticket;
    logic [31:0][VECTOR_TICKET_BITS-1:0]    locked_ticket;
    logic [31:0][VECTOR_LANES-1:0]          pending, locked;//locked:LOAD/STORE指令的rd将为该寄存器
    logic [    VECTOR_LANES-1:0]            vl_therm;
    logic                                   exec_finished     ;
    logic                                   do_reconfigure    ;
    logic                                   instr_is_rdc      ;



    assign memory_instr   = valid_in ? |instr_in.lock : 1'b0;

    //Check if instr is reconfiguration operation
    assign reconfig_instr = valid_in ? instr_in.reconfigure : 1'b0;


    //Check if the EX is ready to accept (only those that you need to send to)
    assign start_new_instr = do_issue & ~|current_exp_loop;//current_exp_loop==0

    //Do reconfiguration
    assign exec_finished  = ~(|pending) & ~(|locked);
    assign do_reconfigure = valid_in & reconfig_instr & exec_finished;


    //Check if instr expansion finished
    assign total_remaining_elements = instr_in.vl - (current_exp_loop*VECTOR_LANES);
    assign expansion_finished       = maxvl_reached | vl_reached;
    assign maxvl_reached            = (current_exp_loop === (max_expansion-1));
    assign vl_reached               = (((current_exp_loop+1) << $clog2(VECTOR_LANES)) >= instr_in.vl);

    //Check if the EX is ready to accept (only those that you need to send to)
    assign output_ready = ready_i;
    assign vl_therm     = ~('1 << total_remaining_elements);

    assign do_issue = memory_instr ? (valid_in & can_issue_m)     :
                                     (valid_in & output_ready & can_issue);

    logic pop;//issue signal
    assign pop          = valid_in & ready_o;
    assign valid_output = vl_therm & {VECTOR_LANES{do_issue}} & {VECTOR_LANES{~memory_instr}} & {VECTOR_LANES{~reconfig_instr}};

    assign ready_o = reconfig_instr ? exec_finished                                   :
                     memory_instr   ? (can_issue_m & expansion_finished)              :
                     valid_in       ? (can_issue & expansion_finished & output_ready) : 1'b0;

    //Track Instruction Expansion
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            current_exp_loop <= '0;
        end else begin
            if (do_reconfigure | pop) begin
                current_exp_loop <= '0;
            end else if (do_issue) begin
                current_exp_loop <= current_exp_loop +1;
            end
        end
    end

    //Store the max expansion per instruction
    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            max_expansion <= instr_in.maxvl >> $clog2(VECTOR_LANES);
        end else if(do_reconfigure) begin
            max_expansion <= instr_in.maxvl >> $clog2(VECTOR_LANES);
        end
    end

    // Struct containing control flow signals
    assign valid_o              = |valid_output;
    assign info_to_exec.fu      = instr_in.fu;//can move？
    assign info_to_exec.microop = instr_in.microop ;
    assign info_to_exec.ticket  = instr_in.ticket;
    assign info_to_exec.dst     = dst;
    assign info_to_exec.head_uop= start_new_instr;
    assign info_to_exec.end_uop = expansion_finished;
    // We indicate the remaining VL here, so that the info can be used in EX
    assign info_to_exec.vl      = start_new_instr ? instr_in.vl : total_remaining_elements;

    assign instr_is_rdc = (instr_in.fu == 2'b10);//算术运算指令
    always_comb begin
        if (instr_is_rdc) begin//算术运算指令
            if (expansion_finished & ~|current_exp_loop) begin // first & last uop, vl < vector_lanes
                dst   = instr_in.dst[4:0] + current_exp_loop;
                src_1 = instr_in.src1[4:0]       + current_exp_loop;
                src_2 = instr_in.src2[4:0]       + current_exp_loop;
            end else if (expansion_finished) begin// last uop
                dst   = instr_in.dst[4:0];
                src_1 = instr_in.src1[4:0]      ;
                src_2 = instr_in.src2[4:0]      ;
            end else if (start_new_instr) begin// first uop, vl > vector_lanes
                dst   = instr_in.dst[4:0] + current_exp_loop +1;
                src_1 = instr_in.src1[4:0]       + current_exp_loop +1;
                src_2 = instr_in.src2[4:0]       + current_exp_loop +1;
            end else begin// middle uops
                dst   = instr_in.dst[4:0] + current_exp_loop +1;
                src_1 = instr_in.src1[4:0]       + current_exp_loop +1;
                src_2 = instr_in.src2[4:0]       + current_exp_loop +1;
            end
        end else begin//访存指令
            dst   = instr_in.dst[4:0] + current_exp_loop;
            src_1 = instr_in.src1[4:0]       + current_exp_loop;
            src_2 = instr_in.src2[4:0]       + current_exp_loop;
        end
    end

    // Struct containing Data
    generate for (genvar k = 0; k < VECTOR_LANES; k++) begin
        assign data_to_exec[k].valid     = valid_output[k];
        assign data_to_exec[k].immediate = instr_in.immediate;
        //DATA 1 Selection
        assign data_to_exec[k].data1  = ({32{frw_a_src_1[k]}}     & frw_a_data[k]) |
                                        ({32{frw_b_src_1[k]}}     & frw_b_data[k]) |
                                        ({32{frw_c_src_1[k]}}     & wr_data[k])    |
                                        ({32{~pending[src_1][k]}} & data_1[k]);
        //DATA 2 Selection//可以判断source2是否为imm，减少一个端口
        assign data_to_exec[k].data2  = ({32{frw_a_src_2[k]}}     & frw_a_data[k]) |
                                        ({32{frw_b_src_2[k]}}     & frw_b_data[k]) |
                                        ({32{frw_c_src_2[k]}}     & wr_data[k])    |
                                        ({32{~pending[src_2][k]}} & data_2[k]);

        // Reductions mask all the elements for all the uops, except element#0 for the last uop
    /*    assign data_to_exec[k].mask   = (instr_is_rdc & expansion_finished) ? (k == 0)   : // only element#0 of last uop will writeback a result
                                        (instr_is_rdc)                      ?  1'b0      : // no middle uop will write a result
                                        (instr_in.use_mask == 2'b10)        ? mask[k]    : // Use v1’s elements lsb as the mask
                                        (instr_in.use_mask == 2'b11)        ? ~mask[k]   : // Use ~v1’s elements lsb as the mask
                                                                               1'b1;    */   // No masking (== assume masking is 0xFFFF…FFFF)
    end endgenerate

    //Forwarding Logic
    generate for (genvar j = 0; j < VECTOR_LANES; j++) begin
        //Forward Point #1
        assign frw_a_src_1[j] = frw_a_en[j] & (frw_a_addr === src_1) & (frw_a_ticket === pending_ticket[src_1]);
        assign frw_a_src_2[j] = frw_a_en[j] & (frw_a_addr === src_2) & (frw_a_ticket === pending_ticket[src_2]);
        //Forward Point #2
        assign frw_b_src_1[j] = frw_b_en[j] & (frw_b_addr === src_1) & (frw_b_ticket === pending_ticket[src_1]);
        assign frw_b_src_2[j] = frw_b_en[j] & (frw_b_addr === src_2) & (frw_b_ticket === pending_ticket[src_2]);
        //Forward Point #3 (Writeback)
        assign frw_c_src_1[j] = wr_en[j] & (wr_addr === src_1) & (wr_ticket === pending_ticket[src_1]);
        assign frw_c_src_2[j] = wr_en[j] & (wr_addr === src_2) & (wr_ticket === pending_ticket[src_2]);
    end endgenerate

    //Issue Logic -> non-Memory Instructions
    assign can_issue    = &issue_masked;
    assign issue_masked = no_hazards | ~vl_therm;//
    generate for (genvar p = 0; p < VECTOR_LANES; p++) begin
        //src1
        assign src1_ok[p] = ~(|instr_in.data1)                             |
                            (frw_a_src_1[p] | frw_b_src_1[p] | frw_c_src_1[p]) |
                            (~pending[src_1][p]);
        //src2
        assign src2_ok[p] = ~(|instr_in.data2)                             |
                            (frw_a_src_2[p] | frw_b_src_2[p] | frw_c_src_2[p]) |
                            (~pending[src_2][p]);
        //dst
        assign rdst_ok[p]    = ~locked[dst][p];
        assign no_hazards[p] = src1_ok[p] & src2_ok[p] & rdst_ok[p];
    end 
    endgenerate

    //Issue Logic -> Memory Instructions
    assign can_issue_m    = &issue_m_masked;
    assign issue_m_masked = no_hazards_m | ~vl_therm;

    generate for (genvar l = 0; l < VECTOR_LANES; l++) begin: g_iss_logic_mem
        assign can_lock_sources[l]     = instr_in.lock[0] ? (~locked[src_1][l] & ~locked[src_2][l]) : 1'b1;//lock前先检测寄存器是否被lock
        assign can_lock_destination[l] = instr_in.lock[1] ? ~locked[dst][l] : 1'b1;
        assign no_hazards_m[l]         = can_lock_sources[l] & can_lock_destination[l];
    end endgenerate

    //Convert to OH
    logic [VECTOR_LANES-1:0][31:0] wr_addr_oh, mem_wr_addr_oh;
    logic [31:0] dst_oh, src1_oh, src2_oh, unlock_reg_a_oh, unlock_reg_b_oh;
    assign dst_oh          = (1 << dst);
    assign src1_oh         = (1 << src_1);
    assign src2_oh         = (1 << src_2);
    assign unlock_reg_a_oh = (1 << unlock_reg_a);
    assign unlock_reg_b_oh = (1 << unlock_reg_b);

    generate 
        for (genvar m = 0; m < VECTOR_LANES; m++) begin: g_oh_pntrs
            assign wr_addr_oh[m]     = (1 << wr_addr);
            assign mem_wr_addr_oh[m] = (1 << mem_wr_addr);
        end 
    endgenerate

    //Pending status per elem/vreg
    logic  ticket_match_pending    ;
    logic  mem_ticket_match_pending;

    assign mem_ticket_match_pending = (mem_wr_ticket === pending_ticket[mem_wr_addr]);
    assign ticket_match_pending     = (wr_ticket     === pending_ticket[wr_addr]);

//update pending 
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pending <= '0;
        end 
        else begin
            if(do_reconfigure) begin
                pending <= '0;
            end 
            else if (!reconfig_instr) begin//
                for (int k = 0; k < VECTOR_LANES; k++) begin
                    for (int i = 0; i < 32; i++) begin
                        if(do_issue && vl_therm[k] && dst_oh[i] && !instr_in.dst_iszero && !instr_in.is_store/*add*/) begin
                            pending[i][k] <= 1;
                            pending_ticket[i] <= instr_in.ticket;
                        end
                        else if(do_issue && ~vl_therm[k] && dst_oh[i] && !instr_in.dst_iszero) begin
                            pending[i][k] <= 0;
                        end 
                        else if(wr_en[k] && wr_addr_oh[k][i] && ticket_match_pending) begin
                            pending[i][k] <= 0;
                        end 
                        else if (mem_wr_en[k] && mem_wr_addr_oh[k][i] && mem_ticket_match_pending) begin
                            pending[i][k] <= 0;
                        end
                    end
                end
            end
        end
    end

    //Locked status per elem/vreg
    logic ticket_match_locked;
    assign ticket_match_locked = (unlock_ticket === locked_ticket[unlock_reg_a]);
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            locked <= '0;
        end 
        else begin
            for (int k = 0; k < VECTOR_LANES; k++) begin
                for (int i = 0; i < 32; i++) begin
                    if(do_issue && vl_therm[k] && dst_oh[i] && instr_in.lock[1] && !instr_in.dst_iszero) begin
                        locked[i][k]     <= 1;
                        locked_ticket[i] <= instr_in.ticket;
                    end
                    //useless
                    /*else if(do_issue && vl_therm[k] && src1_oh[i] && instr_in.instr_in.lock[0] && !instr_in.src1_iszero) begin // for now mem ops dont use src1
                        locked[i][k]     <= 1;                                                                            // and dont release src1, might change
                        locked_ticket[i] <= instr_in.ticket;
                    end*/
                    else if(do_issue && vl_therm[k] && src2_oh[i] && instr_in.lock[0] && (instr_in.data2[4:0] != 5'd0)) begin
                        locked[i][k]     <= 1;
                        locked_ticket[i] <= instr_in.ticket;
                    end 
                    else if(unlock_en && unlock_reg_a_oh[i] && ticket_match_locked) begin
                        locked[i][k] <= 0;
                    end 
                    else if(unlock_en && unlock_reg_b_oh[i] && ticket_match_locked) begin
                        locked[i][k] <= 0;
                    end
                end
            end
        end
    end

    assign mem_pending_0 = pending[mem_addr_0][0];
    assign mem_ticket_0  = pending_ticket[mem_addr_0];
    assign mem_pending_1 = pending[mem_addr_1][0];
    assign mem_ticket_1  = pending_ticket[mem_addr_1];
    assign mem_pending_2 = pending[mem_addr_2][0];
    assign mem_ticket_2  = pending_ticket[mem_addr_2];

    //查询寄存器锁定状态
    generate
        for (genvar i = 0; i < 2; i++) begin
            assign mem_prb_locked_o[i] = locked[mem_prb_reg_i[i]][0];
            assign mem_prb_ticket_o[i] = locked_ticket[mem_prb_reg_i[i]];
        end
    endgenerate

    //Mask the writebacks
    logic [VECTOR_LANES-1:0] wr_en_masked;
    always_comb begin : WBmask
        for (int i = 0; i < VECTOR_LANES; i++) begin
            wr_en_masked[i] = wr_en[i] & ~locked[wr_addr][i];
        end
    end
        
    vrf
    #(
        .ELEMENTS (VECTOR_LANES)
    )
    vector_regfile
    (
        .clk            (clk        ),
        .rst_n          (rst_n      ),

        .rd_addr_1      (src_1      ),
        .data_out_1     (data_1     ),
        .rd_addr_2      (src_2      ),
        .data_out_2     (data_2     ),
        .mask_src       (),
        .mask           (),

        .el_wr_en       (wr_en_masked),
        .el_wr_addr     (wr_addr),
        .el_wr_data     (wr_data),

        .v_rd_addr_0    (mem_addr_0 ),
        .v_data_out_0   (mem_data_0 ),
        .v_rd_addr_1    (mem_addr_1 ),
        .v_data_out_1   (mem_data_1 ),
        .v_rd_addr_2    (mem_addr_2 ),
        .v_data_out_2   (mem_data_2 ),

        .v_wr_en        (mem_wr_en  ),
        .v_wr_addr      (mem_wr_addr),
        .v_wr_data      (mem_wr_data)
    );
  
  
  
endmodule