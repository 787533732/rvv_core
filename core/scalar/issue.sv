
module issue
#(
    parameter int REGFILE_ADDR_WIDTH  = 6 ,
    parameter int DEPTH               = 4 ,
    parameter int ROB_INDEX_BITS      = 3 ,
    parameter int SCOREBOARD_SIZE     = 64,
	parameter int VECTOR_LANES		  = 8
) 
(
    input   logic                                   clk             	,
    input   logic                                   rst_n           	,
    //toward rr                     	
    output  logic                                   issue_1         	,
    input   logic                                   iq_instr1_valid 	,
    input   renamed_instr                           iq_instr1       	,
    output  logic                                   issue_2         	,
    input   logic                                   iq_instr2_valid 	,
    input   renamed_instr                           iq_instr2       	,  
    //Retired Instruction	
    input  writeback_toARF                          writeback_1     	,
    input  writeback_toARF                          writeback_2     	,
	//Flush Command	
    input  predictor_update                         pr_update       	,
    input  logic                                    flush_valid     	,
    input  logic [(2**ROB_INDEX_BITS)-1:0]   		flush_vector_inv	,
    //Busy Signals from Functional Units
    input  logic [3:0]                              busy_fu         	,//2:alu2 1:alu1 0:lsu
    //Outputs from Functional Units	
    input   ex_update [3:0]                         fu_update1      	,
    input   ex_update [3:0]                         fu_update2      	,
    input   ex_update [3:0]                         fu_update_frw1  	,
    input   ex_update [3:0]                         fu_update_frw2  	,
    //Forward Port from ROB	
    output  logic [3:0] [ROB_INDEX_BITS-1:0]        read_addr_rob   	,
    input   logic [3:0] [31:0]                      data_out_rob    	,
    //toward ex	
    output  to_execution [1:0]                      t_execution     	,
	//toward vector 	
	output	logic									vector_valid		,  
	input	logic									vector_ready		,    
	output	to_vector								vector_instruction				
	//output	logic									vector_flush_valid
); 

	// #Internal Signals#
	scoreboard_entry [SCOREBOARD_SIZE-1 : 0] scoreboard  ;
	logic            [SCOREBOARD_SIZE-1 : 0] flush_vector;
	localparam int SC_SIZE = $bits(scoreboard);
	//Intermediate signals
    logic wr_en_1, wr_en_1_dummy, wr_en_2_dummy, wr_en_2,vis_en_1;
    logic rd_ok_Ia, rd_ok_Ib;     //Rdst checking signals
    logic src1_ok_Ia, src1_ok_Ib; //Rsrc1 checking signals
    logic src2_ok_Ia, src2_ok_Ib; //Rsrc2 checking signals
    logic fu_ok_Ia, fu_ok_Ib;     //Functional Unit checking signals
    logic Ib_dependent_Ia;
    logic valid_dest1, valid_dest2;
    logic [2:0]  instr1_vlmul,instr1_vsew;//vtype [5:3] [2:0]
    logic [6:0]  instr1_vlmax,instr1_vl;
    //Dummy Signals for indexing
    logic       pending_Ia_src1, pending_Ia_src2, pending_Ib_src1, pending_Ib_src2, pendinga_rd, pendingb_rd;
	logic       common_fu;
    logic       in_rob_Ia_src1, in_rob_Ia_src2, in_rob_Ib_src1, in_rob_Ib_src2;
    logic [1:0] fu_Ia_src1, fu_Ia_src2, fu_Ib_src1, fu_Ib_src2;

    //for register file
    logic [3:0][5:0] 	read_Addr_RF;
    logic [3:0][31:0]	data_Out_RF;
    logic               write_En, write_En_2;
    logic [5:0] 		write_Addr_RF, write_Addr_RF_2;
    logic [31:0] 		write_Data, write_Data_2;
    assign read_Addr_RF[0]= iq_instr1.source1;
    assign read_Addr_RF[1]= iq_instr1.source2;
    assign read_Addr_RF[2]= iq_instr2.source1;
    assign read_Addr_RF[3]= iq_instr2.source2;
    //retire from ROB  
	assign write_En        = writeback_1.valid_commit & writeback_1.valid_write & ~writeback_1.flushed;
	assign write_Addr_RF   = writeback_1.pdst;
	assign write_Data      = writeback_1.data;
	assign write_En_2      = writeback_2.valid_commit & writeback_2.valid_write & ~writeback_2.flushed;
	assign write_Addr_RF_2 = writeback_2.pdst;
	assign write_Data_2    = writeback_2.data;

    register_file 
    #(
        .DATA_WIDTH         (32), 
        .ADDR_WIDTH         (6 ), 
        .SIZE               (64), 
        .READ_PORTS         (4)    
    )regfile
    (
    	.clk                (clk  ),
    	.rst_n              (rst_n),
    	// Write Port
    	.write_En           (write_En     ),
    	.write_Addr         (write_Addr_RF),
    	.write_Data         (write_Data   ),
    	// Write Port
    	.write_En_2         (write_En_2     ),
    	.write_Addr_2       (write_Addr_RF_2),
    	.write_Data_2       (write_Data_2   ),
    	// Read Port
    	.read_Addr          (read_Addr_RF),
    	.data_Out           (data_Out_RF)
    );
    assign issue_1 = wr_en_1 | vis_en_1;
    assign issue_2 = wr_en_2;
    //if rd=x0?
    assign valid_dest1  = |iq_instr1.destination;
    assign valid_dest2  = |iq_instr2.destination;
	// forward data from ROB -> Create Addresses
	assign read_addr_rob[0] = scoreboard[iq_instr1.source1].ticket;
	assign read_addr_rob[1] = scoreboard[iq_instr1.source2].ticket;
	assign read_addr_rob[2] = scoreboard[iq_instr2.source1].ticket;
	assign read_addr_rob[3] = scoreboard[iq_instr2.source2].ticket;
	// Data just passing through to the next stage for the 2 Instructions
	assign t_execution[0].pc              = iq_instr1.pc;
	assign t_execution[0].destination     = iq_instr1.destination;
	assign t_execution[0].immediate       = iq_instr1.immediate;
	assign t_execution[0].functional_unit = iq_instr1.functional_unit;
	assign t_execution[0].microoperation  = iq_instr1.microoperation;
	assign t_execution[0].rat_id 		  = iq_instr1.rat_id;
	assign t_execution[0].is_vector       = iq_instr1.is_vector;
	assign t_execution[0].vl_in_source1	  = iq_instr1.vl_in_source1;
	assign t_execution[0].ticket          = iq_instr1.ticket;
	assign t_execution[0].branch_id       = iq_instr1.branch_id;
	assign t_execution[0].csr_addr        = iq_instr1.csr_addr;
	assign t_execution[0].csr_imm         = iq_instr1.csr_imm;
	assign t_execution[0].reconfigure     = iq_instr1.is_vector_cfg;
	assign t_execution[0].dst_iszero      = ~|iq_instr1.destination;

	assign t_execution[1].pc              = iq_instr2.pc;
	assign t_execution[1].destination     = iq_instr2.destination;
	assign t_execution[1].immediate       = iq_instr2.immediate;
	assign t_execution[1].functional_unit = iq_instr2.functional_unit;
	assign t_execution[1].microoperation  = iq_instr2.microoperation;
	assign t_execution[1].rat_id 		  = iq_instr2.rat_id;
	assign t_execution[1].is_vector       = iq_instr2.is_vector;
	assign t_execution[1].vl_in_source1	  = iq_instr2.vl_in_source1;
	assign t_execution[1].ticket          = iq_instr2.ticket;
	assign t_execution[1].branch_id       = iq_instr2.branch_id;
	assign t_execution[1].csr_addr        = iq_instr2.csr_addr;
	assign t_execution[1].csr_imm         = iq_instr2.csr_imm;
	assign t_execution[1].reconfigure     = iq_instr2.is_vector_cfg;
	assign t_execution[1].dst_iszero      = ~|iq_instr2.destination;

    // Conflict Checking Vector Signals
	logic		 vector_wren_1_dummy,vector_wren_2_dummy;
	logic		 vsrc1_ok_Ia,vsrc2_ok_Ia,vsrc1_ok_Ib,vsrc2_ok_Ib;
	logic   	 vector_pending_Ia_src1,vector_pending_Ia_src2;
	logic   	 vector_pending_Ib_src1,vector_pending_Ib_src2;
	logic [31:0] vector_Ia_data1,vector_Ia_data2;
	logic [31:0] vector_Ib_data1,vector_Ib_data2;
	assign vector_pending_Ia_src1 = iq_instr1.is_vector & (iq_instr1.vector_need_rs1 ? pending_Ia_src1 : 1'b0);
	assign vector_pending_Ia_src2 = iq_instr1.is_vector & (iq_instr1.vector_need_rs2 ? pending_Ia_src2 : 1'b0);
	assign vector_pending_Ib_src1 = iq_instr2.is_vector & (iq_instr2.vector_need_rs1 ? pending_Ib_src1 : 1'b0);
	assign vector_pending_Ib_src2 = iq_instr2.is_vector & (iq_instr2.vector_need_rs2 ? pending_Ib_src2 : 1'b0);
	// //提交阶段的前馈
	always_comb begin       
        //Check if Pending
        if(vector_pending_Ia_src1) begin
            if(write_En && (write_Addr_RF == iq_instr1.source1)) begin
                vsrc1_ok_Ia     = 1;
                vector_Ia_data1 = write_Data ;
			end 
			else if(write_En_2 && (write_Addr_RF_2 == iq_instr1.source1))  begin
                vsrc1_ok_Ia     = 1;
                vector_Ia_data1 = write_Data_2;
            end
			else begin
                //Stall
                vsrc1_ok_Ia     = 0;
                vector_Ia_data1 = 'b0;
            end
		end 
		else begin
            //grab Data from Register File
            vsrc1_ok_Ia     = 1;
            vector_Ia_data1 = data_Out_RF[0];
		end
	end
	always_comb begin       
        //Check if Pending
        if(vector_pending_Ia_src2) begin
            if(write_En && (write_Addr_RF == iq_instr1.source2)) begin
                vsrc2_ok_Ia     = 1;
                vector_Ia_data2 = write_Data ;
			end 
			else if(write_En_2 && (write_Addr_RF_2 == iq_instr1.source2))  begin
                vsrc2_ok_Ia     = 1;
                vector_Ia_data2 = write_Data_2;
            end
			else begin
                //Stall
                vsrc2_ok_Ia     = 0;
                vector_Ia_data2 = 'b0;
            end
		end 
		else begin
            //grab Data from Register File
            vsrc2_ok_Ia     = 1;
            vector_Ia_data2 = data_Out_RF[1];
		end
	end
	/*
	always_comb begin       
        //Check if Pending
        if(vector_pending_Ib_src1) begin
            if(write_En && (write_Addr_RF == iq_instr2.source1)) begin
                vsrc1_ok_Ib     = 1;
                vector_Ib_data1 = write_Data ;
			end 
			else if(write_En_2 && (write_Addr_RF_2 == iq_instr2.source1))  begin
                vsrc1_ok_Ib     = 1;
                vector_Ib_data1 = write_Data_2;
            end
			else begin
                //Stall
                vsrc1_ok_Ib     = 0;
                vector_Ib_data1 = 'b0;
            end
		end 
		else begin
            //grab Data from Register File
            vsrc1_ok_Ib     = 1;
            vector_Ib_data1 = data_Out_RF[2];
		end
	end
	always_comb begin       
        //Check if Pending
        if(vector_pending_Ib_src2) begin
            if(write_En && (write_Addr_RF == iq_instr2.source2)) begin
                vsrc2_ok_Ib     = 1;
                vector_Ib_data2 = write_Data ;
			end 
			else if(write_En_2 && (write_Addr_RF_2 == iq_instr2.source2))  begin
                vsrc2_ok_Ib     = 1;
                vector_Ib_data2 = write_Data_2;
            end
			else begin
                //Stall
                vsrc2_ok_Ib     = 0;
                vector_Ib_data2 = 'b0;
            end
		end 
		else begin
            //grab Data from Register File
            vsrc2_ok_Ib     = 1;
            vector_Ib_data2 = data_Out_RF[3];
		end
	end
*/

	assign vector_wren_1_dummy = vsrc1_ok_Ia & vsrc2_ok_Ia;
	//assign vector_wren_2_dummy = vsrc1_ok_Ib & vsrc2_ok_Ib;

	assign vis_en_1 = iq_instr1.is_vector & vector_wren_1_dummy & iq_instr1.is_valid & iq_instr1_valid & vector_ready;//反压
    //assign vis_en_2 = iq_instr2.is_vector & vis_en_1 & vector_wren_2_dummy & iq_instr2.is_valid & iq_instr2_valid & ~Ib_dependent_Ia & ~common_fu;

	assign vector_valid	= vis_en_1;

	assign vector_instruction.valid       = vis_en_1;
	assign vector_instruction.dst		  = iq_instr1.destination;					
	assign vector_instruction.src1		  = iq_instr1.source1;					
	assign vector_instruction.src2		  = iq_instr1.source2;					
	assign vector_instruction.data1		  = vector_Ia_data1;				
	assign vector_instruction.data2		  = vector_Ia_data2;						
	assign vector_instruction.immediate   = iq_instr1.immediate;	
	assign vector_instruction.reconfigure = iq_instr1.is_vector_cfg;
	assign vector_instruction.fu  	      = iq_instr1.functional_unit;
	assign vector_instruction.microop     = iq_instr1.microoperation;
	assign vector_instruction.vl          = instr1_vl;
	assign vector_instruction.maxvl       = instr1_vlmax;
	assign vector_instruction.vls_width   = iq_instr1.vls_width;
    // Create Flush Signals
	always_comb begin
		flush_vector = 'b0;
		for (int i = 1; i < SCOREBOARD_SIZE; i++) begin
			for (int k = 0; k < 2**ROB_INDEX_BITS; k++) begin
				if(scoreboard[i].ticket == k && !flush_vector_inv[k]) begin
					flush_vector[i] = 1;
				end
			end
		end
	end
	// Create Final Issue-Enable signals
	assign t_execution[0].valid = wr_en_1 & (!vis_en_1 | iq_instr1.is_vector_cfg);
	assign t_execution[1].valid = wr_en_2;
	// In-order Issue: Oldest Instr must issue before issuing #2
	assign wr_en_1 = (~iq_instr1.is_vector | iq_instr1.is_vector_cfg) & wr_en_1_dummy & iq_instr1.is_valid & iq_instr1_valid;
    assign wr_en_2 = (~iq_instr2.is_vector | iq_instr2.is_vector_cfg) & wr_en_1 & wr_en_2_dummy & iq_instr2.is_valid & iq_instr2_valid & ~Ib_dependent_Ia & ~common_fu;
	/*assign wr_en_1 = wr_en_1_dummy & iq_instr1.is_valid & iq_instr1_valid & ~iq_instr1.is_vector;
    assign wr_en_2 = wr_en_2_dummy &  wr_en_1 & iq_instr2.is_valid & iq_instr2_valid &
                    ~iq_instr2.is_vector & ~Ib_dependent_Ia & ~common_fu;*/

    // Conflict Checking Signals
	assign wr_en_1_dummy = rd_ok_Ia & src1_ok_Ia & src2_ok_Ia & fu_ok_Ia;
	assign wr_en_2_dummy = rd_ok_Ib & src1_ok_Ib & src2_ok_Ib & fu_ok_Ib;
	//Check if congestion for the same FU
	//只针对访存，CSR，Vector指令
    assign common_fu =  ((iq_instr1.functional_unit == 2'b00) & (iq_instr2.functional_unit == 2'b00)) |
						((iq_instr1.functional_unit == 2'b01) & (iq_instr2.functional_unit == 2'b01)) |
						((iq_instr1.functional_unit == 2'b00) & (iq_instr2.functional_unit == 2'b01)) |
						((iq_instr1.functional_unit == 2'b01) & (iq_instr2.functional_unit == 2'b00)) |
						(iq_instr1.is_vector & iq_instr2.is_vector);
    //Check RAW
    //Depedency occurs when one of the sources is the output of Ia
    assign Ib_dependent_Ia = ((iq_instr2.source1==iq_instr1.destination) 
                            | (iq_instr2.source2==iq_instr1.destination)) & valid_dest1;
	
    //--------------------Issue instr1------------------------//
	// create dummy signals for Instruction 1
	assign pending_Ia_src1 = scoreboard[iq_instr1.source1].pending;
	assign in_rob_Ia_src1  = scoreboard[iq_instr1.source1].in_rob;
	assign fu_Ia_src1      = scoreboard[iq_instr1.source1].fu;

	assign pending_Ia_src2 = scoreboard[iq_instr1.source2].pending;
	assign in_rob_Ia_src2  = scoreboard[iq_instr1.source2].in_rob;
	assign fu_Ia_src2      = scoreboard[iq_instr1.source2].fu;
    // Check FU_1
	assign fu_ok_Ia = (iq_instr1.functional_unit==2'b00) ? ~busy_fu[0] : 1'b1;
	// Check rd_ok_Ia
	assign rd_ok_Ia = ~scoreboard[iq_instr1.destination].pending;
	always_comb begin 
	/*	if(iq_instr1.is_vector_cfg) begin
			src1_ok_Ia           = 1;
			t_execution[0].data1 = {26'b0,iq_instr1.source1};
		end*/
		//Check rs1_1
		if(iq_instr1.source1_pc) begin
			src1_ok_Ia           = 1;
			t_execution[0].data1 = iq_instr1.pc;
		end 
        //Check if Pending
        else if(pending_Ia_src1) begin//从ROB和FU执行或者写回阶段中旁路过来数据
            if(in_rob_Ia_src1 == 1) begin
                //grab Data from ROB
                src1_ok_Ia           = 1;
                t_execution[0].data1 = data_out_rob[0];
            end else if(fu_update_frw1[fu_Ia_src1].valid && fu_update_frw1[fu_Ia_src1].destination==iq_instr1.source1) begin
                //执行阶段的前馈
                src1_ok_Ia           = 1;
                t_execution[0].data1 = fu_update_frw1[fu_Ia_src1].data;
			end else if(fu_update_frw2[fu_Ia_src1].valid && fu_update_frw2[fu_Ia_src1].destination==iq_instr1.source1) begin
                //执行阶段的前馈
                src1_ok_Ia           = 1;
                t_execution[0].data1 = fu_update_frw2[fu_Ia_src1].data;
            end else if(fu_update1[fu_Ia_src1].valid && fu_update1[fu_Ia_src1].destination==iq_instr1.source1) begin
                //写回阶段的前馈
                src1_ok_Ia           = 1;
                t_execution[0].data1 = fu_update1[fu_Ia_src1].data;
            end else if(fu_update2[fu_Ia_src1].valid && fu_update2[fu_Ia_src1].destination==iq_instr1.source1) begin
                //写回阶段的前馈
                src1_ok_Ia           = 1;
                t_execution[0].data1 = fu_update2[fu_Ia_src1].data;
            end else begin
                //Stall
                src1_ok_Ia           = 0;
                t_execution[0].data1 = data_Out_RF[0];
            end
		end else begin
            //grab Data from Register File
            src1_ok_Ia           = 1;
            t_execution[0].data1 = data_Out_RF[0];
		end
	end
	//Check rs2_1
	always_comb begin 
	/*	if(iq_instr1.is_vector_cfg) begin
			src2_ok_Ia           = 1;
			t_execution[0].data2 = {26'b0,iq_instr1.source1};
		end*/
		if(iq_instr1.source2_immediate) begin
			src2_ok_Ia           = 1;
			t_execution[0].data2 = iq_instr1.immediate;
		end 
        else if(pending_Ia_src2) begin
            if(in_rob_Ia_src2 == 1) begin
                //stall
                src2_ok_Ia           = 1;
                t_execution[0].data2 = data_out_rob[1];
            end 
			else if(fu_update_frw1[fu_Ia_src2].valid && (fu_update_frw1[fu_Ia_src2].destination==iq_instr1.source2)) begin
                //执行阶段的前馈
                src2_ok_Ia           = 1;
                t_execution[0].data2 = fu_update_frw1[fu_Ia_src2].data;
            end 
			else if(fu_update_frw2[fu_Ia_src2].valid && (fu_update_frw2[fu_Ia_src2].destination==iq_instr1.source2)) begin
                //执行阶段的前馈
                src2_ok_Ia           = 1;
                t_execution[0].data2 = fu_update_frw2[fu_Ia_src2].data;
            end 
			else if(fu_update1[fu_Ia_src2].valid && (fu_update1[fu_Ia_src2].destination==iq_instr1.source2)) begin
                //写回阶段的前馈
                src2_ok_Ia           = 1;
                t_execution[0].data2 = fu_update1[fu_Ia_src2].data;
            end 
			else if(fu_update2[fu_Ia_src2].valid && fu_update2[fu_Ia_src2].destination==iq_instr1.source2) begin
                //写回阶段的前馈
                src2_ok_Ia           = 1;
                t_execution[0].data2 = fu_update2[fu_Ia_src2].data;
            end 
			else begin
                //Stall
                src2_ok_Ia           = 0;
                t_execution[0].data2 = data_Out_RF[1];
            end
		end 
        else begin
            //grab Data from Register File
            src2_ok_Ia           = 1;
            t_execution[0].data2 = data_Out_RF[1];
		end
	end

	//--------------------Issue instr2------------------------//
	//create dummy signals
	assign pending_Ib_src1 = scoreboard[iq_instr2.source1].pending;
	assign in_rob_Ib_src1  = scoreboard[iq_instr2.source1].in_rob;
	assign fu_Ib_src1      = scoreboard[iq_instr2.source1].fu;

	assign pending_Ib_src2 = scoreboard[iq_instr2.source2].pending;
	assign in_rob_Ib_src2  = scoreboard[iq_instr2.source2].in_rob;
	assign fu_Ib_src2      = scoreboard[iq_instr2.source2].fu;
    // Check FU_2
	assign fu_ok_Ib = (iq_instr2.functional_unit==2'b00) ? ~busy_fu[0] : 1'b1;
	// Check rd_ok_Ib
	assign rd_ok_Ib = ~scoreboard[iq_instr2.destination].pending;
	always_comb begin 
	/*	if(iq_instr2.is_vector_cfg) begin
			src1_ok_Ib           = 1;
			t_execution[1].data1 = {26'b0,iq_instr2.source1};
		end*/
		// Check rs1_2
		if(iq_instr2.source1_pc) begin
			src1_ok_Ib           = 1;
			t_execution[1].data1 = iq_instr2.pc;
		end 
        else if(pending_Ib_src1) begin
			if(in_rob_Ib_src1==1) begin
				//grab Data from ROB
				src1_ok_Ib           = 1;
				t_execution[1].data1 = data_out_rob[2];
			end else if(fu_update_frw1[fu_Ib_src1].valid && fu_update_frw1[fu_Ib_src1].destination==iq_instr2.source1) begin
				//执行阶段的前馈
				src1_ok_Ib           = 1;
				t_execution[1].data1 = fu_update_frw1[fu_Ib_src1].data;
			end else if(fu_update_frw2[fu_Ib_src1].valid && fu_update_frw2[fu_Ib_src1].destination==iq_instr2.source1) begin
				//执行阶段的前馈
				src1_ok_Ib           = 1;
				t_execution[1].data1 = fu_update_frw2[fu_Ib_src1].data;
			end else if(fu_update1[fu_Ib_src1].valid && fu_update1[fu_Ib_src1].destination==iq_instr2.source1) begin
				//写回阶段的前馈
				src1_ok_Ib           = 1;
				t_execution[1].data1 = fu_update1[fu_Ib_src1].data;
			end else if(fu_update2[fu_Ib_src1].valid && fu_update2[fu_Ib_src1].destination==iq_instr2.source1) begin
				//写回阶段的前馈
				src1_ok_Ib           = 1;
				t_execution[1].data1 = fu_update2[fu_Ib_src1].data;
			end else begin
				//Stall
				src1_ok_Ib           = 0;
				t_execution[1].data1 = data_Out_RF[2];
			end
			end else begin
				//grab Data from Register File
				src1_ok_Ib           = 1;
				t_execution[1].data1 = data_Out_RF[2];
			end
		end
    always_comb begin   
	/*	if(iq_instr2.is_vector_cfg) begin
			src2_ok_Ib           = 1;
			t_execution[1].data2 = {26'b0,iq_instr2.source2};
		end */
		// Check rs2_2
		if(iq_instr2.source2_immediate) begin
			src2_ok_Ib           = 1;
			t_execution[1].data2 = iq_instr2.immediate;
		end else if(pending_Ib_src2) begin
            if(in_rob_Ib_src2 == 1) begin
                //grab Data from ROB
                src2_ok_Ib           = 1;
                t_execution[1].data2 = data_out_rob[3];
            end else if(fu_update_frw1[fu_Ib_src2].valid && fu_update_frw1[fu_Ib_src2].destination==iq_instr2.source2) begin
                //执行阶段的前馈
                src2_ok_Ib           = 1;
                t_execution[1].data2 = fu_update_frw1[fu_Ib_src2].data;
			end else if(fu_update_frw2[fu_Ib_src2].valid && fu_update_frw2[fu_Ib_src2].destination==iq_instr2.source2) begin
                //执行阶段的前馈
                src2_ok_Ib           = 1;
                t_execution[1].data2 = fu_update_frw2[fu_Ib_src2].data;
            end else if(fu_update1[fu_Ib_src2].valid && fu_update1[fu_Ib_src2].destination==iq_instr2.source2) begin
                //写回阶段的前馈
                src2_ok_Ib           = 1;
                t_execution[1].data2 = fu_update1[fu_Ib_src2].data;
            end else if(fu_update2[fu_Ib_src2].valid && fu_update2[fu_Ib_src2].destination==iq_instr2.source2) begin
                //写回阶段的前馈
                src2_ok_Ib           = 1;
                t_execution[1].data2 = fu_update2[fu_Ib_src2].data;
            end else begin
                //Stall
                src2_ok_Ib           = 0;
                t_execution[1].data2 = data_Out_RF[3];
            end
		end 
        else begin
            //grab Data from Register File
            src2_ok_Ib           = 1;
            t_execution[1].data2 = data_Out_RF[3];
        end
    end

	//#Update Scoreboard#
	//-----------------------------------------------------------------------------
    logic [SCOREBOARD_SIZE-1:0] instr_1_dest_oh, instr_2_dest_oh, writeback_dst_oh, writeback_dst_oh_2;
    logic [3:0] masked_write_en1,masked_write_en2;
    logic                       writeback_en, writeback_en_2;

    assign instr_1_dest_oh = (1 << iq_instr1.destination);
    assign instr_2_dest_oh = (1 << iq_instr2.destination);
    //?????????????????????????????
    //Mask the Write Bits for the FU Updates with the New Issues
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            if(fu_update1[i].destination == iq_instr2.destination && wr_en_2) begin
                masked_write_en1[i] = 0;
            end 
            else if(fu_update1[i].destination == iq_instr1.destination && wr_en_1) begin
                masked_write_en1[i] = 0;
            end 
            else if(fu_update2[i].destination == iq_instr2.destination && wr_en_2) begin
                masked_write_en2[i] = 0;
            end 
            else if(fu_update2[i].destination == iq_instr1.destination && wr_en_1) begin
                masked_write_en2[i] = 0;
            end 
            else begin
                masked_write_en1[i] = fu_update1[i].valid & (fu_update1[i].ticket==scoreboard[fu_update1[i].destination].ticket);
				masked_write_en2[i] = fu_update2[i].valid & (fu_update2[i].ticket==scoreboard[fu_update2[i].destination].ticket);
			end
        end
    end
	// Update the Scoreboard.inrob Field
	always_ff @(posedge clk) begin
		for (int i = 0; i < SCOREBOARD_SIZE; i++) begin
			if(wr_en_2 && instr_2_dest_oh[i]) begin// Issued 2,the value of rd is caculating in fu...
				scoreboard[i].in_rob  <= 0;
			end 
            else if(wr_en_1 && instr_1_dest_oh[i]) begin// Issued 1,the value of rd is caculating in fu...
				scoreboard[i].in_rob  <= 0;
			end 
            else begin
				for (int j = 0; j < 4; j++) begin//the result is in rob after fu caculate 
					if(masked_write_en1[j] && fu_update1[j].destination==i) begin
	 					scoreboard[i].in_rob <= 1;
					end
				end
				for (int j = 0; j < 4; j++) begin//the result is in rob after fu caculate 
					if(masked_write_en2[j] && fu_update2[j].destination==i) begin
	 					scoreboard[i].in_rob <= 1;
					end
				end
			end
		end
	end
	//Update the Scoreboard.ticket & Scoreboard.fu Fields
	always_ff @(posedge clk) begin
		for (int i = 0; i < SCOREBOARD_SIZE; i++) begin
			if(wr_en_2 && instr_2_dest_oh[i]) begin
				// Issued 2
				scoreboard[i].fu     <= iq_instr2.functional_unit;
				scoreboard[i].ticket <= iq_instr2.ticket;
			end else if (wr_en_1 && instr_1_dest_oh[i]) begin
				// Issued 1
				scoreboard[i].fu     <= iq_instr1.functional_unit;
				scoreboard[i].ticket <= iq_instr1.ticket;
			end
		end
	end

	assign writeback_en     = writeback_1.valid_commit & writeback_1.valid_write & (writeback_1.ticket == scoreboard[writeback_1.pdst].ticket);
	assign writeback_dst_oh = (1 << writeback_1.pdst);

	assign writeback_en_2     = writeback_2.valid_commit & writeback_2.valid_write & (writeback_2.ticket == scoreboard[writeback_2.pdst].ticket);
	assign writeback_dst_oh_2 = (1 << writeback_2.pdst);
	// Update the Scoreboard.pending Field
	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			for (int i = 0; i < SCOREBOARD_SIZE; i++) begin
				scoreboard[i].pending <= 0;
			end
		end else begin
			//x0 is unwrittable -> never pending -> no commit will ever arrive for x0
			scoreboard[0].pending <= 'b0;
			for (int i = 1; i < SCOREBOARD_SIZE; i++) begin
				if (flush_valid && flush_vector[i]) begin//Flush the Entry
					scoreboard[i].pending <= 0;
				end 
                else if(wr_en_2 && instr_2_dest_oh[i]) begin// Issued 2
					scoreboard[i].pending <= valid_dest2;//issue to fu, pending
				end 
                else if(wr_en_1 && instr_1_dest_oh[i]) begin// Issued 1
					scoreboard[i].pending <= valid_dest1;//issue to fu, pending
				end 
                else if(writeback_en && writeback_dst_oh[i]) begin// New writeback_1
					scoreboard[i].pending <= 0;//get the result, clear pending
				end 
                else if(writeback_en_2 && writeback_dst_oh_2[i]) begin// New writeback_1
					scoreboard[i].pending <= 0;//get the result, clear pending
				end
			end
		end
	end

//cacular the vl


	always_comb begin
		case(1'b1)
			iq_instr1.vsetvli : begin
				instr1_vlmul = iq_instr1.csr_addr[2:0];
				instr1_vsew  = iq_instr1.csr_addr[5:3];
			end
			iq_instr1.vsetvl : begin
				instr1_vlmul = iq_instr1.csr_addr[2:0];
				instr1_vsew  = iq_instr1.csr_addr[5:3];
			end
			iq_instr1.vsetivli : begin
				instr1_vlmul = t_execution[0].data2[2:0];
				instr1_vsew  = t_execution[0].data2[5:3];
			end	
			default			: begin
				instr1_vlmul = 3'b000;
				instr1_vsew  = 3'b000;
			end
		endcase
	end
    always_comb begin
        if(instr1_vlmul[2])
			instr1_vlmax = (32*VECTOR_LANES>>(instr1_vsew+3))>>(-instr1_vlmul);
		else
			instr1_vlmax = (32*VECTOR_LANES>>(instr1_vsew+3))<<instr1_vlmul;
    end

    always_comb begin
        case(1'b1)
            iq_instr1.vsetvli, 
            iq_instr1.vsetvl : begin
                if(t_execution[0].data1 <= instr1_vlmax)
                    instr1_vl = t_execution[0].data1;
                else if(t_execution[0].data1 < 2*instr1_vlmax)
                    instr1_vl = t_execution[0].data1>>1;
                else 
                    instr1_vl = instr1_vlmax;
            end 
            iq_instr1.vsetivli : begin
                if(t_execution[0].data2<= instr1_vlmax)
                    instr1_vl = t_execution[0].data2;
                else if(t_execution[0].data2 < 2*instr1_vlmax)
                    instr1_vl = t_execution[0].data2>>1;
                else 
                    instr1_vl = instr1_vlmax;
            end
            default  : instr1_vl = instr1_vl;
        endcase
    end
	assign t_execution[0].vl    = instr1_vl;
	assign t_execution[0].vlmax = instr1_vlmax;



//cacular the vl
    logic [2:0]  instr2_vlmul,instr2_vsew;//vtype [5:3] [2:0]
    logic [6:0]  instr2_vlmax,instr2_vl;

	always_comb begin
		case(1'b1)
			iq_instr2.vsetvli : begin
				instr2_vlmul = iq_instr2.csr_addr[2:0];
				instr2_vsew  = iq_instr2.csr_addr[5:3];
			end
			iq_instr2.vsetvl : begin
				instr2_vlmul = iq_instr2.csr_addr[2:0];
				instr2_vsew  = iq_instr2.csr_addr[5:3];
			end
			iq_instr1.vsetivli : begin
				instr2_vlmul = t_execution[1].data2[2:0];
				instr2_vsew  = t_execution[1].data2[5:3];
			end	
			default			: begin
				instr2_vlmul = 3'b000;
				instr2_vsew  = 3'b000;
			end
		endcase
	end
    always_comb begin
        if(instr2_vlmul[2])
			instr2_vlmax = (32*VECTOR_LANES>>(instr2_vsew+3))>>(-instr2_vlmul);
		else
			instr2_vlmax = (32*VECTOR_LANES>>(instr2_vsew+3))<<instr2_vlmul;
    end

    always_comb begin
        case(1'b1)
            iq_instr2.vsetvli, 
            iq_instr2.vsetvl : begin
                if(t_execution[1].data1 <= instr2_vlmax)
                    instr2_vl = t_execution[1].data1;
                else if(t_execution[1].data1 < 2*instr1_vlmax)
                    instr2_vl = t_execution[1].data1>>1;
                else 
                    instr2_vl = instr2_vlmax;
            end 
            iq_instr2.vsetivli : begin
                if(t_execution[1].data2<= instr2_vlmax)
                    instr2_vl = t_execution[1].data2;
                else if(t_execution[1].data2 < 2*instr2_vlmax)
                    instr2_vl = t_execution[1].data2>>1;
                else 
                    instr2_vl = instr2_vlmax;
            end
            default  : instr2_vl = instr2_vl;
        endcase
    end
	assign t_execution[1].vl    = instr2_vl;
	assign t_execution[1].vlmax = instr2_vlmax;

endmodule