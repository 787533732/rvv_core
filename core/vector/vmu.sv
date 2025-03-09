module vmu
#(
    parameter VECTOR_LANES       = 8    ,
    parameter ADDR_WIDTH         = 32   ,
    parameter MICROOP_WIDTH      = 5    ,
    parameter REQ_DATA_WIDTH     = 256  ,
    parameter VECTOR_TICKET_BITS = 4
)
(
    input   logic                               clk                 ,         
    input   logic                               rst_n               ,

    input   logic                               valid_in            ,
    input   to_vmu                              instr_in            ,          
    output  logic                               ready_o             ,
    //RF Interface - Loads
    //for indexed stride
    output logic [4:0]                          rd_addr_0_o        ,
    input  logic [32*VECTOR_LANES-1:0]          rd_data_0_i        ,
    input  logic                                rd_pending_0_i     ,
    input  logic [VECTOR_TICKET_BITS-1:0]       rd_ticket_0_i      ,
    //RF Interface - Stores
    output logic [4:0]                          rd_addr_1_o        ,
    input  logic [32*VECTOR_LANES-1:0]          rd_data_1_i        ,
    input  logic                                rd_pending_1_i     ,
    input  logic [VECTOR_TICKET_BITS-1:0]       rd_ticket_1_i      ,
    //for indexed stride
    output logic [4:0]                          rd_addr_2_o        ,
    input  logic [32*VECTOR_LANES-1:0]          rd_data_2_i        ,
    input  logic                                rd_pending_2_i     ,
    input  logic [VECTOR_TICKET_BITS-1:0]       rd_ticket_2_i      ,
/*------------------------Cache Interface----------------------------*/
    //output
    output  logic                               mem_req_valid_o     ,
    output  vector_mem_req                      mem_req_o           ,    
    input   logic                               cache_ready_i       ,
    input   logic                               mem_resp_valid_i    ,    
    input   vector_mem_resp                     mem_resp_i          ,
    //RF Writeback Interface
    output logic [VECTOR_LANES-1:0]             wrtbck_en_o         ,
    output logic [4:0]                          wrtbck_reg_o        ,
    output logic [32*VECTOR_LANES-1:0]          wrtbck_data_o       ,
    output logic [VECTOR_TICKET_BITS-1:0]       wrtbck_ticket_o     ,
    //RF Writeback Probing Interface
    output  logic [1:0][4:0]                    wrtbck_prb_reg_o    ,
    input   logic [1:0]                         wrtbck_prb_locked_i ,
    input   logic [1:0][VECTOR_TICKET_BITS-1:0] wrtbck_prb_ticket_i ,
    //Unlock Interface
    output logic                                unlock_en_o        ,
    output logic [4:0]                          unlock_reg_a_o     ,
    output logic [4:0]                          unlock_reg_b_o     ,
    output logic [      VECTOR_TICKET_BITS-1:0] unlock_ticket_o 
);
    //=======================================================
    // WIRES
    //=======================================================
    logic                                   load_unlock_en    ;
    logic [4:0]                             load_unlock_reg_a ;
    logic [4:0]                             load_unlock_reg_b ;
    logic [VECTOR_TICKET_BITS-1:0]          load_unlock_ticket;
    logic [31:0]                            load_start_addr   ;
    logic [31:0]                            load_end_addr     ;
    logic [31:0]                            load_req_addr     ;
    logic [MICROOP_WIDTH-1:0]               load_req_microop  ;
    logic [$clog2(REQ_DATA_WIDTH/8):0]      load_req_size     ;
    logic [$clog2(VECTOR_LANES):0]          load_req_ticket   ;
    logic                                   ld_can_inteleave  ;
    logic [VECTOR_LANES-1:0]                ld_wb_en          ;
    logic [4:0]                             ld_wb_reg         ;
    logic [32*VECTOR_LANES-1:0]             ld_wb_data        ;
    logic [      VECTOR_TICKET_BITS-1:0]    ld_wb_ticket      ;

    logic                                   store_unlock_en    ;
    logic [4:0]                             store_unlock_reg_a ;
    logic [4:0]                             store_unlock_reg_b ;
    logic [VECTOR_TICKET_BITS-1:0]          store_unlock_ticket;
    logic [31:0]                            store_start_addr   ;
    logic [31:0]                            store_end_addr     ;
    logic [31:0]                            store_req_addr     ;
    logic [MICROOP_WIDTH-1:0]               store_req_microop  ;
    logic [$clog2(REQ_DATA_WIDTH/8):0]      store_req_size     ;
    logic [REQ_DATA_WIDTH-1:0]              store_req_data     ;
    logic                                   st_can_interleave  ;
    logic [1:0]                             wb_grant    ;
    logic [1:0]                             wb_request  ;
    logic [2:0]                             is_busy     ;
    logic [1:0]                             tail        ;
    logic                                   is_load,is_store,is_reconf;
    logic                                   push_load,push_store;
    logic                                   load_ready,store_ready,fifo_ready;
    logic                                   ld_request; 
    logic                                   st_request;
    logic                                   ld_grant;   
    logic                                   st_grant; 
    logic                                   pop;
    logic [1:0]                             pop_data;
    assign is_load   = ~instr_in.reconfigure & (instr_in.microop == 5'b00000);
    assign is_store  = ~instr_in.reconfigure & ~is_load;
    assign is_reconf = instr_in.reconfigure;

    //Pick the Outputs
    assign unlock_en_o     = load_unlock_en; /*| store_unlock_en */

    assign unlock_reg_a_o  = /*load_unlock_en ? */load_unlock_reg_a; /*  :
                                              store_unlock_reg_a;*/

    assign unlock_reg_b_o  = /*load_unlock_en ? */load_unlock_reg_b; /*  :
                                              store_unlock_reg_b;*/

    assign unlock_ticket_o = /*load_unlock_en ? */load_unlock_ticket; /* :
                                              store_unlock_ticket;*/

    always_comb begin
        if(is_reconf) begin //reconfiguration must happen simultaneously
            push_load  = valid_in & load_ready & store_ready;//& toepl_ready;
            push_store = valid_in & load_ready & store_ready;//& toepl_ready;
            //push_toepl = valid_in & load_ready & store_ready & toepl_ready;
        end 
        else begin
            push_load  = valid_in & is_load  & load_ready & fifo_ready;
            push_store = valid_in & is_store & store_ready & fifo_ready;
            //push_toepl = valid_in & is_toepl & toepl_ready & fifo_ready;
        end
    end

    vmu_ld_eng
    #(
        .REQ_DATA_WIDTH         (REQ_DATA_WIDTH     ),//D-Cache Cacheline
        .ADDR_WIDTH             (32 ),
        .VECTOR_LANES           (VECTOR_LANES       ),
        .VECTOR_TICKET_BITS     (VECTOR_TICKET_BITS ),
        .MICROOP_WIDTH          (MICROOP_WIDTH      )  
    )load_engine
    (
        .clk                    (clk                ),
        .rst_n                  (rst_n              ),

        .valid_in               (push_load          ),
        .instr_in               (instr_in           ),
        .ready_o                (load_ready         ),

        .rd_addr_o              (rd_addr_0_o        ),//vs2
        .rd_data_i              (rd_data_0_i        ),
        .rd_pending_i           (rd_pending_0_i     ),
        .rd_ticket_i            (rd_ticket_0_i      ),

        .wrtbck_req_o           (),       
        .wrtbck_grant_i         (1'b1),     
        .wrtbck_en_o            (wrtbck_en_o        ),        
        .wrtbck_reg_o           (wrtbck_reg_o       ),       
        .wrtbck_data_o          (wrtbck_data_o      ),      
        .wrtbck_ticket_o        (wrtbck_ticket_o    ),        

        .wrtbck_reg_a_o         (wrtbck_prb_reg_o[0]   ),      
        .wrtbck_locked_a_i      (wrtbck_prb_locked_i[0]),    
        .wrtbck_ticket_a_i      (wrtbck_prb_ticket_i[0]),       
        .wrtbck_reg_b_o         (wrtbck_prb_reg_o[1]   ),      
        .wrtbck_locked_b_i      (wrtbck_prb_locked_i[1]),     
        .wrtbck_ticket_b_i      (wrtbck_prb_ticket_i[1]),

        .unlock_en_o            (load_unlock_en     ),
        .unlock_reg_a_o         (load_unlock_reg_a  ),
        .unlock_reg_b_o         (load_unlock_reg_b  ),
        .unlock_ticket_o        (load_unlock_ticket ),

        .grant_i                (ld_grant           ),  
        .req_en_o               (ld_request         ),
        .req_addr_o             (load_req_addr      ),
        .req_microop_o          (load_req_microop   ),
        .req_size_o             (load_req_size      ),
        .req_ticket_o           (load_req_ticket    ),

        .resp_valid_i           (mem_resp_valid_i   ),
        .resp_ticket_i          (mem_resp_i.ticket  ),
        .resp_size_i            (mem_resp_i.size    ),
        .resp_data_i            (mem_resp_i.data    ),

        .is_busy_o              (is_busy[0]         ),
        .can_be_inteleaved_o    (),
        .start_addr_o           (),
        .end_addr_o             () 
    );


    vmu_st_eng 
    #(
        .REQ_DATA_WIDTH         (REQ_DATA_WIDTH    ),
        .VECTOR_LANES           (VECTOR_LANES      ),
        .ADDR_WIDTH             (ADDR_WIDTH        ),
        .MICROOP_WIDTH          (MICROOP_WIDTH     ),
        .VECTOR_TICKET_BITS     (VECTOR_TICKET_BITS)
    )store_engine
    (
        .clk                    (clk  ),
        .rst_n                  (rst_n),
        //Input Interface
        .valid_in               (push_store ),
        .instr_in               (instr_in   ),
        .ready_o                (store_ready),
        //RF Interface (per vreg)
        .rd_addr_1_o            (rd_addr_1_o   ),
        .rd_data_1_i            (rd_data_1_i   ),
        .rd_pending_1_i         (rd_pending_1_i),
        .rd_ticket_1_i          (rd_ticket_1_i ),
        //RF Interface (for `OP_INDEXED stride)
        .rd_addr_2_o            (rd_addr_2_o   ),
        .rd_data_2_i            (rd_data_2_i   ),
        .rd_pending_2_i         (rd_pending_2_i),
        .rd_ticket_2_i          (rd_ticket_2_i ),
        //Unlock Interface
        .unlock_en_o            (),
        .unlock_reg_a_o         (),
        .unlock_reg_b_o         (),
        .unlock_ticket_o        (),
        //Request Interface
        .grant_i                (st_grant           ),
        .req_en_o               (st_request         ),
        .req_addr_o             (store_req_addr     ),
        .req_microop_o          (store_req_microop  ),
        .req_size_o             (store_req_size     ),
        .req_data_o             (store_req_data     ),
        //Sync Interface
        .is_busy_o              (is_busy[1]),
        .can_be_inteleaved_o    (),
        .start_addr_o           (),
        .end_addr_o             ()
    );
    logic [1:0] push_data;
    assign load_starts  =  push_load & ~push_store;
    assign store_starts = ~push_load &  push_store;

    assign load_ends    = ~is_busy[0];
    assign store_ends   = ~is_busy[1];

    assign any_request = ld_request | st_request;
    assign any_grant   = ld_grant   | st_grant  ;

    assign push_data = load_starts  ? 2'b01 : 2'b10;
    assign push = load_starts | store_starts;
    fifo
    #(
        .DW             (2),
        .DEPTH          (3)
    )
    (
        .clk            (clk        ),
        .rst_n          (rst_n      ),
        .valid_flush    (1'b0),

        .push_data      (push_data  ),
        .push           (push       ),
        .ready          (fifo_ready ),

        .pop_data       (pop_data),
        .valid          (valid),
        .pop            (pop)
    );

    assign ld_grant =  valid & cache_ready_i & pop_data == 2'b01 & ld_request;
    assign st_grant =  valid & cache_ready_i & pop_data == 2'b10 & st_request;

    assign pop      = (valid & pop_data == 2'b01 & load_ends) |
                      (valid & pop_data == 2'b10 & store_ends);


    //Create output signal
    assign ready_o = valid_in & is_load  ? (load_ready  & fifo_ready) :
                     valid_in & is_store ? (store_ready & fifo_ready) :
                     (load_ready & store_ready & fifo_ready);

    assign mem_req_valid_o   = any_grant;
    assign mem_req_o.address = ld_grant ? load_req_addr : store_req_addr;

    assign mem_req_o.microop = ld_grant ? load_req_microop : store_req_microop;

    assign mem_req_o.size    = ld_grant ? load_req_size : store_req_size;

    assign mem_req_o.ticket  = ld_grant ? load_req_ticket : 1'b0;

    assign mem_req_o.data    = store_req_data;



endmodule
