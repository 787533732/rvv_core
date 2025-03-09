module  vector_top
#(
    parameter VIQ_DEPTH          = 4 ,
    parameter DATA_WIDTH         = 32,
    parameter VECTOR_TICKET_BITS = 4 ,
    parameter VECTOR_LANES       = 8 ,
    parameter MICROOP_WIDTH      = 5 ,  
	parameter VECTOR_REQ_WIDTH   = 256
)
(
    input   logic                   clk                 ,
    input   logic                   rst_n               ,

    input   logic                   vector_flush_valid  , 

    input   logic                   vector_valid        ,
    output  logic                   vector_ready        ,
    input   to_vector               vector_instruction  ,
    //Cache Request Interface
	output logic                    mem_req_valid_o     ,
	output vector_mem_req           mem_req_o           ,
	input  logic                    cache_ready_i       ,
	//Cache Response Interface  
	input  logic                    mem_resp_valid_i    ,
	input  vector_mem_resp          mem_resp_i     
);
    //towards vector_iq
    logic viq_valid_out,ready_i;
    logic vmu_ready,vex_ready;
    to_vector viq_instr_out;
    to_vis vex_instr;
    to_vmu vmu_instr;
    logic is_mem,is_arith,is_reconf;
    logic vmu_valid,vex_valid;
    logic viq_ready_out;
    logic load_instr;
    logic last_producer_wr_en;
    logic do_reconfigure,reconfig_instr,do_operation;
    logic [$clog2(32*VECTOR_LANES)-1:0]vl,maxvl;
    logic [31:0][VECTOR_TICKET_BITS-1:0] last_producer;
    logic [1:0][4:0]                        mem_prb_reg;   
    logic [1:0]                             mem_prb_locked;
    logic [1:0][VECTOR_TICKET_BITS-1:0]     mem_prb_ticket;
    logic [            VECTOR_LANES-1:0]    mem_wrtbck_en;    
    logic [4:0]                             mem_wrtbck_reg;   
    logic [32*VECTOR_LANES-1:0]             mem_wrtbck_data;  
    logic [VECTOR_TICKET_BITS-1:0]          mem_wrtbck_ticket;
	logic [4:0]                             mem_addr_0       ;
	logic [32*VECTOR_LANES-1:0]             mem_data_0       ;
	logic                                   mem_pending_0    ;
	logic [      VECTOR_TICKET_BITS-1:0]    mem_ticket_0     ;
	logic [4:0]                             mem_addr_1       ;
	logic [32*VECTOR_LANES-1:0]             mem_data_1       ;
	logic                                   mem_pending_1    ;
	logic [      VECTOR_TICKET_BITS-1:0]    mem_ticket_1     ;
	logic [4:0]                             mem_addr_2       ;
	logic [32*VECTOR_LANES-1:0]             mem_data_2       ;
	logic                                   mem_pending_2    ;
	logic [      VECTOR_TICKET_BITS-1:0]    mem_ticket_2     ;
	logic                                   unlock_en        ;
	logic [4:0]                             unlock_reg_a     ;
	logic [4:0]                             unlock_reg_b     ;
	logic [VECTOR_TICKET_BITS-1:0]          unlock_ticket    ;
    //logic                               do_operation_last;
    //logic                               do_operation_edge;
assign do_operation   = vector_valid & vector_ready;
/*always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) 
        do_operation_last <= 1'b0;
    else
        do_operation_last <= do_operation;
end
assign do_operation_edge = do_operation & ~do_operation_last;*/
assign reconfig_instr = vector_instruction.reconfigure; 
assign do_reconfigure = reconfig_instr & do_operation;

logic [3:0] next_ticket;
logic [3:0] ticket;
//Next Free Ticket
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            next_ticket <= 1;
        end else begin
            if(do_reconfigure) begin
                next_ticket <= 1;
            end
            else if(do_operation) begin
                next_ticket <= next_ticket +1;
                if (&next_ticket) 
                    next_ticket <= 1;
            end
        end
    end


//update vl/maxvl
    always_ff @(posedge clk or negedge rst_n) begin 
        if(!rst_n) begin
            vl    <= 'b0;
            maxvl <= 'b0;
        end
        else if(do_reconfigure) begin
            vl    <= vector_instruction.vl;
            maxvl <= vector_instruction.maxvl;
        end
    end

localparam VIQ_SIZE = $bits(vector_instruction)+ $bits(next_ticket);
ibuffer                      
#(
    .DW         (VIQ_SIZE),
    .DEPTH      (VIQ_DEPTH)         
)vector_issue_queue
(
    .clk        (clk            ),
    .rst_n      (rst_n          ),

    .valid_flush(flush_valid    ),

    .data_i     ({next_ticket,vector_instruction}),
    .valid_i    (vector_valid),
    .ready_o    (vector_ready),

    .data_o     ({ticket,viq_instr_out}),
    .valid_o    (viq_valid_out      ),
    .ready_i    (ready_in       )
);
    assign load_instr  = is_mem & ((viq_instr_out.microop == 5'b00000) | (viq_instr_out.microop == 5'b00001) | (viq_instr_out.microop == 5'b00010) | (viq_instr_out.microop == 5'b00011));
    assign store_instr = is_mem & ((viq_instr_out.microop == 5'b00100) | (viq_instr_out.microop == 5'b00101) | (viq_instr_out.microop == 5'b00110) | (viq_instr_out.microop == 5'b00111));
    assign is_mem      = viq_valid_out & (viq_instr_out.fu==2'b00);
    assign is_arith    = viq_valid_out & (viq_instr_out.fu==2'b10);
    assign is_reconf   = viq_valid_out & viq_instr_out.reconfigure;
    assign vmu_valid   = is_mem | is_reconf;
    assign vex_valid   = is_mem | is_arith | is_reconf;
    assign ready_in    = (is_mem & vmu_ready & vex_ready) | (is_arith & vex_ready) | viq_instr_out.reconfigure;

    assign vex_instr.valid       = vex_valid;                    
    assign vex_instr.dst         = viq_instr_out.dst;                   
    assign vex_instr.dst_iszero  = (viq_instr_out.dst == 5'b0);                       
    assign vex_instr.src1        = viq_instr_out.src1;                   
    assign vex_instr.src1_iszero = (viq_instr_out.src1 == 5'b0);                           
    assign vex_instr.src2        = viq_instr_out.src2;                   
    assign vex_instr.src2_iszero = (viq_instr_out.src2 == 5'b0);                           
    assign vex_instr.data1       = viq_instr_out.data1;                   
    assign vex_instr.data2       = viq_instr_out.data2;                   
    assign vex_instr.immediate   = viq_instr_out.immediate;                       
    assign vex_instr.reconfigure = viq_instr_out.reconfigure;                           
    assign vex_instr.ticket      = ticket;                   
    assign vex_instr.fu          = viq_instr_out.fu;               
    assign vex_instr.microop     = viq_instr_out.microop;
    assign vex_instr.is_store         = store_instr;                        
    assign vex_instr.lock        = load_instr  ? 2'b11 : //load:lock dst
                                   store_instr ? 2'b01 : 2'b00;//store:lock source          
    assign vex_instr.vl          = vl;               
    assign vex_instr.maxvl       = maxvl;                             

    assign vmu_instr.valid            = vmu_valid;      
    assign vmu_instr.dst              = viq_instr_out.dst;        
    assign vmu_instr.src1             = viq_instr_out.src1;      
    assign vmu_instr.src2             = viq_instr_out.src2;      
    assign vmu_instr.data1            = viq_instr_out.data1;      
    assign vmu_instr.data2            = viq_instr_out.data2;      
    assign vmu_instr.ticket           = ticket;      
    assign vmu_instr.last_ticket_src1 = (last_producer[viq_instr_out.src1] === 0) ? ticket : last_producer[viq_instr_out.src1];                 
    assign vmu_instr.last_ticket_src2 = (last_producer[viq_instr_out.src2] === 0) ? ticket : last_producer[viq_instr_out.src2];                  
    assign vmu_instr.immediate        = viq_instr_out.immediate;          
    assign vmu_instr.microop          = viq_instr_out.microop; 

    assign vmu_instr.reconfigure      = viq_instr_out.reconfigure;              
    assign vmu_instr.vl               = vl;               
    assign vmu_instr.maxvl            = maxvl; 
    assign vmu_instr.vls_width        = viq_instr_out.vls_width;
    // Last producer Tracker (used for mem ops, stores do not udpate vd)
    assign last_producer_wr_en = do_operation & (~is_mem | load_instr);
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            last_producer <= '0;
        end else if(last_producer_wr_en) begin
            last_producer[viq_instr_out.dst] <= next_ticket;
        end
    end

    vmu 
    #(
        .VECTOR_LANES       (VECTOR_LANES       ),   
        .MICROOP_WIDTH      (MICROOP_WIDTH      ),  
        .REQ_DATA_WIDTH     (VECTOR_REQ_WIDTH   ) 
    )
    vector_memory_unit
    (
        .clk                (clk                ),
        .rst_n              (rst_n              ),

        .valid_in           (vmu_valid ), 
        .instr_in           (vmu_instr          ),     
        .ready_o            (vmu_ready          ),

        .rd_addr_0_o        (mem_addr_0   ),       
        .rd_data_0_i        (mem_data_0   ),       
        .rd_pending_0_i     (mem_pending_0),    
        .rd_ticket_0_i      (mem_ticket_0 ),

        .rd_addr_1_o        (mem_addr_1   ),       
        .rd_data_1_i        (mem_data_1   ),       
        .rd_pending_1_i     (mem_pending_1),    
        .rd_ticket_1_i      (mem_ticket_1 ),     
        .rd_addr_2_o        (mem_addr_2   ),       
        .rd_data_2_i        (mem_data_2   ),       
        .rd_pending_2_i     (mem_pending_2),    
        .rd_ticket_2_i      (mem_ticket_2 ),     
/*------------------------Cache Interface----------------------------*/
    //output
        .mem_req_valid_o    (mem_req_valid_o    ),
        .mem_req_o          (mem_req_o          ),    
        .cache_ready_i      (cache_ready_i      ),
        .mem_resp_valid_i   (mem_resp_valid_i   ),    
        .mem_resp_i         (mem_resp_i         ),
    
        .wrtbck_en_o        (mem_wrtbck_en    ),            
        .wrtbck_reg_o       (mem_wrtbck_reg   ),           
        .wrtbck_data_o      (mem_wrtbck_data  ),          
        .wrtbck_ticket_o    (mem_wrtbck_ticket),

        .wrtbck_prb_reg_o   (mem_prb_reg   ),           
        .wrtbck_prb_locked_i(mem_prb_locked),            
        .wrtbck_prb_ticket_i(mem_prb_ticket),

        .unlock_en_o        (unlock_en    ),
        .unlock_reg_a_o     (unlock_reg_a ),
        .unlock_reg_b_o     (unlock_reg_b ),
        .unlock_ticket_o    (unlock_ticket) 
    );

	logic                                  iss_valid    ;
	logic                                  iss_ex_ready ;
	to_vector_exec      [VECTOR_LANES-1:0] iss_to_exec_data;
	to_vector_exec_info                    iss_to_exec_info;
	localparam int EX_VINSTR_DATA_SIZE = $bits(iss_to_exec_data);
	localparam int EX_VINSTR_INFO_SIZE = $bits(iss_to_exec_info);
	to_vector_exec [ VECTOR_LANES-1:0] exec_data_o;
	to_vector_exec_info                exec_info_o;
	logic exec_valid, exec_ready;
    logic [VECTOR_LANES-1:0]                    wb_en    ;
	logic [4:0]                                 wb_addr  ;
	logic [VECTOR_LANES-1:0][DATA_WIDTH-1:0]    wb_data  ;
	logic [VECTOR_TICKET_BITS-1:0]              wb_ticket;

    vis 
    #(
        .VECTOR_LANES       (VECTOR_LANES)
    )vector_issue
    (
        .clk                (clk            ),
        .rst_n              (rst_n          ),

        .valid_in           (vex_valid&vmu_ready    ),
        .instr_in           (vex_instr      ),
        .ready_o            (vex_ready      ),

        .valid_o            (iss_valid        ),
        .data_to_exec       (iss_to_exec_data ),
        .info_to_exec       (iss_to_exec_info ),
        .ready_i            (iss_ex_ready     ),

        .mem_prb_reg_i      (mem_prb_reg      ),
        .mem_prb_locked_o   (mem_prb_locked   ),
        .mem_prb_ticket_o   (mem_prb_ticket   ),

        .mem_addr_0         (mem_addr_0     ),
        .mem_data_0         (mem_data_0     ),
        .mem_pending_0      (mem_pending_0  ),
        .mem_ticket_0       (mem_ticket_0   ),
        .mem_addr_1         (mem_addr_1     ),
        .mem_data_1         (mem_data_1     ),
        .mem_pending_1      (mem_pending_1  ),
        .mem_ticket_1       (mem_ticket_1   ),
        .mem_addr_2         (mem_addr_2     ),
        .mem_data_2         (mem_data_2     ),
        .mem_pending_2      (mem_pending_2  ),
        .mem_ticket_2       (mem_ticket_2   ),
    
        .mem_wr_en          (mem_wrtbck_en    ),
        .mem_wr_ticket      (mem_wrtbck_ticket),
        .mem_wr_addr        (mem_wrtbck_reg   ),
        .mem_wr_data        (mem_wrtbck_data  ),
    
        .unlock_en          (unlock_en    ),
        .unlock_reg_a       (unlock_reg_a ),
        .unlock_reg_b       (unlock_reg_b ),
        .unlock_ticket      (unlock_ticket),
    
        .frw_a_en           (),
        .frw_a_addr         (),
        .frw_a_data         (),
        .frw_a_ticket       (),
        .frw_b_en           (),
        .frw_b_addr         (),
        .frw_b_data         (),
        .frw_b_ticket       (),

        .wr_en              (wb_en    ),
        .wr_addr            (wb_addr  ),
        .wr_data            (wb_data  ),
        .wr_ticket          (wb_ticket)   
    );


    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1               ),
        .DATA_WIDTH         (EX_VINSTR_DATA_SIZE),
        .GATING_FRIENDLY    (1'b1               )
    )vis_vex_data
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (iss_valid),
        .ready_out          (iss_ex_ready),
        .data_in            (iss_to_exec_data),

        .valid_out          (exec_valid),
        .ready_in           (exec_ready),
        .data_out           (exec_data_o)
    );

    pipe_reg 
    #(
        .FULL_THROUGHPUT    (1'b1               ),
        .DATA_WIDTH         (EX_VINSTR_INFO_SIZE),
        .GATING_FRIENDLY    (1'b1               )
    )vis_vex_info
    (
        .clk                (clk                ),
        .rst                (~rst_n             ),

        .valid_in           (iss_valid),
        .ready_out          (),
        .data_in            (iss_to_exec_info),

        .valid_out          (),
        .ready_in           (exec_ready),
        .data_out           (exec_info_o)
    );
    vex
    #(
        .DATA_WIDTH         (DATA_WIDTH         ),
        .MICROOP_WIDTH      (5 ),    
        .VECTOR_TICKET_BITS (VECTOR_TICKET_BITS ),
        .VECTOR_LANES       (VECTOR_LANES       )
    )vector_excution
    (
        .clk         (clk  ),
        .rst_n       (rst_n),
        .flush       (),

        .valid_i     (exec_valid),
        .ready_o     (exec_ready),
        .exec_data_i (exec_data_o),
        .exec_info_i (exec_info_o),


        .wr_en       (wb_en    ),
        .wr_addr     (wb_addr  ),
        .wr_data     (wb_data  ),
        .wr_ticket   (wb_ticket) 
    );

endmodule