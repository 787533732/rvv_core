/*
ROB Internal Configuration (per entry): [v|p|v_d|rd|data|v_exc|casue]
* @note:
* Functional Units:
* 00 : Load/Store Unit
* 01 : Floating Point Unit
* 10 : Integer Unit
* 11 : Branches
* @param ADDR_BITS     : # of Address Bits (default 32 bits)
* @param ROB_ENTRIES   : # of entries the ROB can hold
* @param FU_NUMBER     : # of Functional Units that can update ROB at the same cycle
* @param ROB_INDEX_BITS: # ROB's ticket Bits
* @param DATA_WIDTH    : # of Data Bits (default 32 bits)
*/
module rob 
#(
    parameter ROB_ENTRIES    = 64 ,
    parameter FU_NUMBER      = 4 ,
    parameter ROB_INDEX_BITS = $clog2(ROB_ENTRIES)
) 
(
    input  logic                            clk                     ,
    input  logic                            rst_n                   ,
    //Forwarding Port       
    input  logic [3:0][ROB_INDEX_BITS-1:0]  read_address            ,
    output logic [3:0][              31:0]  data_out                ,
    //Update from EX (Input Interface)      
    input  ex_update [FU_NUMBER-1:0]        update1                 ,
    input  ex_update [FU_NUMBER-1:0]        update2                 ,
    //Interface with IS     
    input  new_entries                      new_requests            ,
    output to_issue                         t_issue                 ,
    output writeback_toARF                  writeback_1             ,
    output writeback_toARF                  writeback_2             ,

    //Flush Port
    input  logic                            flush_valid             ,
    input  logic     [ROB_INDEX_BITS-1:0]   flush_ticket            ,
    output logic     [   ROB_ENTRIES-1:0]   flush_vector_inv        ,
    //Data Cache Interface (Search Interface)        
    input  logic     [31:0]                 cache_addr              ,
    input  logic     [4:0]                  cache_microop           ,
    output logic     [31:0]                 cache_data              ,
    output logic                            cache_valid             ,
    output logic                            cache_stall             ,
    //STORE update from Data Cache (Input Interface)   
    input  logic                            cache_blocked           ,     
    input  logic                            store_valid             ,
    input  logic     [31:0]                 store_data              ,
    input  logic     [ROB_INDEX_BITS-1:0]   store_ticket            ,
    input  logic     [31:0]                 store_address           ,
    //writeback into Cache (Output Interface)
    output logic                            cache_writeback_valid   ,
    output logic     [31:0]                 cache_writeback_addr    ,
    output logic     [31:0]                 cache_writeback_data    ,
    output logic     [4:0]                  cache_writeback_microop  
);
    // #Internal Signals#
    rob_entry [   ROB_ENTRIES-1 : 0] rob;
    localparam int ROB_SIZE = $bits(rob);

    logic     [ROB_INDEX_BITS-1 : 0] tail, head, head_plus, tail_actual, tail_plus, flush_ticket_plus, flush_begin, temp;
    logic     [  ROB_INDEX_BITS : 0] counter, counter_actual;
    logic                            can_commit, can_commit_2, will_commit, will_commit_2, can_bypass, valid_1, valid_2, one_found, exact_match;

    logic [ROB_ENTRIES-1 : 0] main_match, secondary_match, match_picked;// difference;
    logic                     input_forward_match, input_forward_sec, microop_ok, input_forward_microop_ok;
    logic [31 : 0]            data_for_c, data_for_c_2;
//---------------------------将ROB的状态返回RR模块----------------------------------------//
    //assign t_issue.ticket    = tail_actual;
    assign t_issue.ticket    = tail;
    //assign t_issue.is_full   = (counter_actual==ROB_ENTRIES);
    //assign t_issue.two_empty = (counter_actual<ROB_ENTRIES-1);
    assign t_issue.is_full   = (counter==ROB_ENTRIES);
    assign t_issue.two_empty = (counter<ROB_ENTRIES-1);
    assign head_plus = head +1;
    always_comb begin
        if(new_requests.valid_request_2) begin
            counter_actual = counter+2;
            tail_actual    = tail+2;
        end
        else if(new_requests.valid_request_1) begin
            counter_actual = counter+1;
            tail_actual    = tail+1;
        end
        else begin
            counter_actual = counter;
            tail_actual    = tail;
        end
        if(will_commit) 
            counter_actual = counter_actual - 1;
        if(will_commit_2) 
            counter_actual = counter_actual - 2;
    end

    logic [6:0][ROB_INDEX_BITS-1:0] upd_positions;
    logic [6:0][31:0]               new_data;
    logic [6:0]                     upd_en;
    logic [ROB_INDEX_BITS-1 : 0]                 cache_forward_addr;
    logic [ROB_ENTRIES-1:0] tail_plus_oh, tail_oh, tail_oh_inverted, main_match_inv, match_picked_inv, flush_wr_en;

    logic [6:0][ROB_INDEX_BITS-1:0] read_addr_rob;
    logic [6:0][31:0]               data_out_rob;
//-----------------unknown----------------------------------//
    //Flushing Calculations
    assign flush_ticket_plus = flush_ticket+1;
    //Get the Entries for Invalidation/Flushing
    //assign flush_wr_en      = diff_wr_en(flush_ticket_plus, head);
    assign flush_wr_en      = diff_wr_en(flush_ticket_plus, tail);
    assign flush_vector_inv = ~flush_wr_en;

    //Pick the Entries for Invalidation (creates an invalidate_en vector)
    function logic[ROB_ENTRIES-1:0] diff_wr_en(int ticket, int pointer);
        int counter, flag;
        logic [ROB_ENTRIES-1:0] result;
        logic [ROB_INDEX_BITS-1:0] i;
        flag    = 0;
        counter = 0;
        result  = 'b0;
        i       = ticket;
        while (counter < ROB_ENTRIES-1) begin
            if (!flag && i!=pointer) begin
                result[i] = 1'b1;
                counter   = counter + 1;
                i         = i + 1;
            end else begin
                if (i==pointer) flag = 1;
                counter = counter + 1;
            end
        end
        return result;
    endfunction
//--------------------------unknown----------------------------------//
    //DATA CACHE SECTION
    //Search in the ROB for the same store Address
    assign input_forward_match = (store_address[31:2] == cache_addr[31:2]) & store_valid;
    assign input_forward_sec   = (store_address[1:0] == cache_addr[1:0]) & store_valid;
    always_comb begin : Compare
        for (int i = 0; i < ROB_ENTRIES; i++) begin
            main_match[i]      = rob[i].valid & rob[i].is_store ? (rob[i].address[31:2] == cache_addr[31:2]) : 1'b0;
            secondary_match[i] = rob[i].valid & rob[i].is_store ? (rob[i].address[1:0] == cache_addr[1:0]) : 1'b0;
        end
    end
    always_comb begin : invertPointers
        for (int i = 0; i < ROB_ENTRIES; i++) begin
            tail_oh_inverted[i] = tail_oh[ROB_ENTRIES-1-i];
            main_match_inv[i]   = main_match[ROB_ENTRIES-1-i];
            match_picked[i]     = match_picked_inv[ROB_ENTRIES-1-i];
        end
    end
    //Grant only one match to Forward the Data
    arbiter #(ROB_ENTRIES)
    arbiter(
        // .request_i      (main_match),
        .request_i      (main_match_inv),
        .priority_i     (tail_oh_inverted),
        .grant_o        (match_picked_inv),
        .anygnt_o       (one_found)
        );
    //Grab the secondary match
    and_or_mux #( .INPUTS   (ROB_ENTRIES),
                  .DW       (1))
    mux_sec ( .data_in  (secondary_match),
              .sel      (match_picked),
              .data_out (exact_match));
    //Encode the Pointer
    always_comb begin : encoder
        cache_forward_addr = 0;
        for (int i = 0; i < ROB_ENTRIES; i++) begin
            if (match_picked[i]) cache_forward_addr = i;
        end
    end
    //Check the Microops for forwarding hazards
    always_comb begin : MicroopOk
        if(cache_microop==5'b00001) begin
            //load==LW
            microop_ok = (rob[cache_forward_addr].microoperation == 5'b00110);
        end else if(cache_microop==5'b00010 | cache_microop==5'b00011) begin
            //load==LH
            microop_ok = (rob[cache_forward_addr].microoperation == 5'b00111 | rob[cache_forward_addr].microoperation == 5'b00110);
        end else if(cache_microop==5'b00100 | cache_microop==5'b00101) begin
            //load==LB
            microop_ok = 1;
        end else begin
            microop_ok = 0;
        end
    end
    always_comb begin : InputMicroopOk
        if(cache_microop==5'b00001) begin
            //load==LW
            input_forward_microop_ok = (rob[store_ticket].microoperation == 5'b00110);
        end else if(cache_microop==5'b00010 | cache_microop==5'b00011) begin
            //load==LH/LHU
            input_forward_microop_ok = (rob[store_ticket].microoperation == 5'b00111 | rob[store_ticket].microoperation == 5'b00110);
        end else if(cache_microop==5'b00100 | cache_microop==5'b00101) begin
            //load==LB/LBU
            input_forward_microop_ok = 1;
        end else begin
            input_forward_microop_ok = 0;
        end
    end
    //Create the Forward Output
    always_comb begin : CreateCacheForwardSignals
        if(input_forward_match) begin
            cache_valid = input_forward_sec & input_forward_microop_ok;
            cache_stall = ~input_forward_sec | ~input_forward_microop_ok;
            cache_data  = store_data;
        end else begin
            cache_valid = one_found & exact_match & microop_ok;
            cache_stall = one_found & ( ~exact_match | ~microop_ok);
            cache_data  = data_out_rob[5];
        end
    end
    //rob的数据存在sram中，控制信息用regfile
    sram 
    #(
        .SIZE           (ROB_ENTRIES    ),
        .DATA_WIDTH     (32             ),
        .RD_PORTS       (7              ),
        .WR_PORTS       (7              ),
        .RESETABLE      (0              )
    )rob_data_ram
    (
        .clk            (clk            ),
        .rst_n          (rst_n          ),

        .wr_en          (upd_en         ),
        .write_address  (upd_positions  ),
        .new_data       (new_data       ),

        .read_address   (read_addr_rob  ),
        .data_out       (data_out_rob   )
    );
    logic [3:0] write_data_selector1,write_data_selector2;

    assign write_data_selector1 = {update1[3].valid,update1[2].valid,{2{1'b0}}};
    assign write_data_selector2 = {update2[3].valid,update2[2].valid,{2{1'b0}}};

    assign upd_en[0]        = update1[0].valid;
    assign upd_positions[0] = update1[0].ticket;
    assign new_data[0]      = update1[0].data;

    assign upd_en[1]        = update1[1].valid;
    assign upd_positions[1] = update1[1].ticket;
    assign new_data[1]      = update1[1].data;

    assign upd_en[2]        = update1[2].valid;
    assign upd_positions[2] = update1[2].ticket;
    assign new_data[2]      = update1[2].data;

    assign upd_en[3]        = update1[3].valid;
    assign upd_positions[3] = update1[3].ticket;
    assign new_data[3]      = update1[3].data;

    assign upd_en[4]        = update2[2].valid;
    assign upd_positions[4] = update2[2].ticket;
    assign new_data[4]      = update2[2].data;

    assign upd_en[5]        = update2[3].valid;
    assign upd_positions[5] = update2[3].ticket;
    assign new_data[5]      = update2[3].data;

    //register new stores
    assign upd_en[6]        = store_valid;
    assign upd_positions[6] = store_ticket;
    assign new_data[6]      = store_data;


    always_comb begin 
        //Forwarding Address for the Data Cache
        read_addr_rob[5] = cache_forward_addr;
        //Address for Commit Data
        read_addr_rob[6] = head_plus;
        read_addr_rob[4] = head;
        for (int i = 0; i < 4; i++) begin//两条指令4个源操作数4个读端口
            read_addr_rob[i] = read_address[i];
            data_out[i]      = data_out_rob[i];
        end
    end

    //Data for Commit
    assign data_for_c   = data_out_rob[4];
    assign data_for_c_2 = data_out_rob[6];
    assign can_commit   = rob[head].is_store ? rob[head].valid & ~rob[head].pending & ~cache_blocked : rob[head].valid & ~rob[head].pending;
    assign will_commit  = (can_commit & ~rob[head].valid_exception) | (rob[head].flushed & rob[head].valid);

    // assign can_commit_2  = (rob[head].is_store | rob[head_plus].is_store) ? 1'b0 : rob[head_plus].valid & ~rob[head_plus].pending & will_commit;
    assign can_commit_2  = (rob[head_plus].is_store) ? 1'b0 : rob[head_plus].valid & ~rob[head_plus].pending & will_commit;
    assign will_commit_2 = (can_commit_2 & ~rob[head_plus].valid_exception) | (rob[head_plus].flushed & rob[head_plus].valid);
    
    //Create writeback_1 Request for the Data Cache
    assign cache_writeback_valid   = can_commit & will_commit & rob[head].is_store & ~rob[head].flushed;
    assign cache_writeback_addr    = rob[head].address;
    assign cache_writeback_data    = data_for_c;
    assign cache_writeback_microop = rob[head].microoperation;
    //Create Commit Request for the RF #1
    assign writeback_1.valid_commit    = will_commit;
    assign writeback_1.valid_write     = (will_commit & rob[head].valid_dest & ~rob[head].flushed);
    assign writeback_1.flushed         = rob[head].flushed;
    assign writeback_1.ldst            = rob[head].lreg;
    assign writeback_1.pdst            = rob[head].preg;
    assign writeback_1.ppdst           = rob[head].ppreg;
    assign writeback_1.data            = data_for_c;
    assign writeback_1.ticket          = head;
    assign writeback_1.pc              = rob[head].pc;
    assign writeback_1.csr_addr        = rob[head].csr_addr;
    assign writeback_1.csr_wdata       = rob[head].csr_wdata;
    assign writeback_1.update_vl_en    = rob[head].update_vl_en;
    assign writeback_1.csr             = rob[head].csr;
    assign writeback_1.valid_exception = rob[head].valid_exception;
    assign writeback_1.cause           = rob[head].cause;          
    assign writeback_1.address         = rob[head].address;        
    //Create Commit Request for the RF #2
    assign writeback_2.valid_commit    = will_commit_2;
    assign writeback_2.valid_write     = (will_commit_2 & rob[head_plus].valid_dest & ~rob[head_plus].flushed);
    assign writeback_2.flushed         = rob[head_plus].flushed;
    assign writeback_2.ldst            = rob[head_plus].lreg;
    assign writeback_2.pdst            = rob[head_plus].preg;
    assign writeback_2.ppdst           = rob[head_plus].ppreg;
    assign writeback_2.data            = data_for_c_2;
    assign writeback_2.ticket          = head_plus;
    assign writeback_2.pc              = rob[head_plus].pc;
    assign writeback_2.csr_addr        = rob[head_plus].csr_addr;
    assign writeback_2.csr_wdata       = rob[head_plus].csr_wdata;
    assign writeback_2.update_vl_en    = rob[head_plus].update_vl_en;
    assign writeback_2.csr             = rob[head_plus].csr;
    assign writeback_2.valid_exception = rob[head_plus].valid_exception;
    assign writeback_2.cause           = rob[head_plus].cause;          
    assign writeback_2.address         = rob[head_plus].address;  
//ROB状态计数器
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            counter <= 'b0;
        else if(will_commit_2) begin
            counter <= counter-2;
            if(new_requests.valid_request_1)
                counter <= counter-1;
            if(new_requests.valid_request_2)
                counter <= counter;
        end
        else if (will_commit) begin
            counter <= counter-1;
            if(new_requests.valid_request_1)
                counter <= counter;
            if(new_requests.valid_request_2)
                counter <= counter+1;
        end
        else begin
            if(new_requests.valid_request_1)
                counter <= counter+1;
            if(new_requests.valid_request_2)
                counter <= counter+2;
        end
    end
    //Convert pointers to OH
    assign tail_oh      = (1 << tail);//instr1
    assign tail_plus    = tail+1;
    assign tail_plus_oh = (1 << tail_plus);//instr2

//根据重命名模块的信息向ROB中写入指令原先的顺序，将pending信号置1。fu执行完将pending置0
    always_ff @(posedge clk) begin
        for(int i = 0; i < ROB_ENTRIES; i++) begin
            if(new_requests.valid_request_2 && tail_plus_oh[i]) begin//two write
                //Register Issue 2
                rob[i].pending         <= new_requests.csr_store_pending_2 | (~new_requests.csr_store_pending_2 & (new_requests.lreg_2 != 0));
                rob[i].valid_dest      <= new_requests.valid_dest_2;
                rob[i].lreg            <= new_requests.lreg_2;
                rob[i].preg            <= new_requests.preg_2;
                rob[i].ppreg           <= new_requests.ppreg_2;
                rob[i].microoperation  <= new_requests.microoperation_2;
                rob[i].valid_exception <= 0;
                rob[i].is_store        <= 0;
                rob[i].pc              <= new_requests.pc_2;
                rob[i].csr             <= new_requests.csr_2;
            end
            else if(new_requests.valid_request_1 &&  tail_oh[i]) begin
                //Register Issue 1
                rob[i].pending         <= new_requests.csr_store_pending_1 | (~new_requests.csr_store_pending_1 & (new_requests.lreg_1 != 0));
                rob[i].valid_dest      <= new_requests.valid_dest_1;
                rob[i].lreg            <= new_requests.lreg_1;
                rob[i].preg            <= new_requests.preg_1;
                rob[i].ppreg           <= new_requests.ppreg_1;
                rob[i].microoperation  <= new_requests.microoperation_1;
                rob[i].valid_exception <= 0;
                rob[i].is_store        <= 0;
                rob[i].pc              <= new_requests.pc_1;
                rob[i].csr             <= new_requests.csr_1;
            end
            else begin
                if(store_valid && i==store_ticket) begin
                    //Register STORE update from Data Cache
                    rob[i].pending  <= 0;
                    rob[i].is_store <= 1;
                    rob[i].address  <= store_address;
                end
                //Register FU Updates from EX
                else begin
                    for (int j = 0; j < FU_NUMBER; j++) begin
                        if(update1[j].valid && i ==update1[j].ticket) begin
                            rob[i].pending         <= 0;
                            rob[i].valid_exception <= update1[j].valid_exception;
                            rob[i].cause           <= update1[j].cause;
                            rob[i].csr_addr        <= update1[j].csr_addr;
                            rob[i].csr_wdata       <= update1[j].csr_wdata;
                            rob[i].update_vl_en    <= update1[j].update_vl_en;
                        end
                        if(update2[j].valid && i ==update2[j].ticket) begin
                            rob[i].pending         <= 0;
                            rob[i].valid_exception <= update2[j].valid_exception;
                            rob[i].cause           <= update2[j].cause;
                            rob[i].csr_addr        <= update2[j].csr_addr;
                            rob[i].csr_wdata       <= update2[j].csr_wdata;
                            rob[i].update_vl_en    <= update2[j].update_vl_en;
                        end
                    end
                end
            end 
        end
    end
    //ROB Validity Bits Management
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for (int i = 0; i < ROB_ENTRIES; i++) begin
                rob[i].valid <= 0;
            end
        end else begin
            for (int i = 0; i < ROB_ENTRIES; i++) begin
                if(new_requests.valid_request_2 && tail_plus_oh[i]) begin
                    rob[i].valid <= 1;
                end else if(new_requests.valid_request_1 && tail_oh[i]) begin
                    rob[i].valid <= 1;
                end else if (will_commit && head==i) begin
                    rob[i].valid <= 0;
                end else if (will_commit_2 && head_plus==i) begin
                    rob[i].valid <= 0;
                end
            end
        end
    end
    //ROB Flush Bit Management
    always_ff @(posedge clk) begin
        for (int i = 0; i < ROB_ENTRIES; i++) begin
            if (flush_valid && flush_wr_en[i]) begin
                rob[i].flushed <= 1'b1;
            end else if(new_requests.valid_request_2 && tail_plus_oh[i]) begin
                rob[i].flushed <= flush_valid;
            end else if(new_requests.valid_request_1 &&  tail_oh[i]) begin
                rob[i].flushed <= flush_valid;
            end
        end
    end
//---------------------------ROB控制信息的更新------------------------------------//
    //读指针的更新
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            head <= 0;
        else if(will_commit_2) 
            head <= head+2;
        else if(will_commit) 
            head <= head+1;
    end
    //写指针的更新
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            tail <= 0;
        else if(new_requests.valid_request_2) 
            tail <= tail+2;
        else if(new_requests.valid_request_1) 
            tail <= tail+1;
    end


logic [19:0] instr;
always_ff @(posedge clk or negedge rst_n) begin 
    if(!rst_n)
        instr <= 'd0;
    else if(will_commit ^ will_commit_2)
        instr <= instr+1;
    else if(will_commit & will_commit_2)
        instr <= instr+2;
end

endmodule
