module rv32im_vector
(
    input   logic       clk                 ,
    input   logic       rst_n               ,
    input   logic       external_interrupt  ,
    input   logic       timer_interrupt  
);
    //Memory System Parameters
    localparam IC_ENTRIES   = 32  ;
    localparam IC_DW        = 128 ;
    localparam DC_ENTRIES   = 32  ;
    localparam DC_DW        = 256 ;
    localparam L2_ENTRIES   = 10240000;
    localparam L2_DW        = 512 ;
    localparam REALISTIC    = 1   ;
    localparam DELAY_CYCLES = 2  ;
    //Predictor Parameters
    localparam RAS_DEPTH        = 8  ;
    localparam GSH_HISTORY_BITS = 2  ;
    localparam GSH_SIZE         = 256;
    localparam BTB_SIZE         = 256;
    //Dual Issue Enabler
    localparam DUAL_ISSUE = 1;
    //ROB Parameters    (Do NOT MODIFY, structs cannot update their widths automatically)
    localparam ROB_ENTRIES  = 8                  ; //default: 8
    localparam ROB_TICKET_W = $clog2(ROB_ENTRIES); //default: DO NOT MODIFY
    //Other Parameters  (DO NOT MODIFY)
    localparam ISTR_DW        = 32        ; //default: 32
    localparam ADDR_BITS      = 32        ; //default: 32
    localparam DATA_WIDTH     = 32        ; //default: 32
    localparam FETCH_WIDTH    = 64        ; //default: 64
    localparam R_WIDTH        = 6         ; //default: 6
    localparam MICROOP_W      = 5         ; //default: 5
    //localparam UNCACHEABLE_ST = 4294901760; //default: 4294901760
    //CSR Parameters        (DO NOT MODIFY)
    localparam CSR_DEPTH = 64;
    //Vector Parameters
    localparam VECTOR_ENABLED   = 0;
    localparam VECTOR_ELEM      = 4;
    localparam VECTOR_ACTIVE_EL = 4;
    //===================================================================================
    logic                    icache_valid_i      ;
    logic                    dcache_valid_i      ;
    logic                    cache_store_valid   ;
    logic                    icache_valid_o      ;
    logic                    dcache_valid_o      ;
    logic                    cache_load_valid    ;
    logic                    write_l2_valid      ;
    logic [   ADDR_BITS-1:0] icache_address_i    ;
    logic [   ADDR_BITS-1:0] dcache_address_i    ;
    logic [   ADDR_BITS-1:0] cache_store_addr    ;
    logic [   ADDR_BITS-1:0] icache_address_o    ;
    logic [   ADDR_BITS-1:0] dcache_address_o    ;
    logic [   ADDR_BITS-1:0] write_l2_addr_c     ;
    logic [   ADDR_BITS-1:0] write_l2_addr       ;
    logic [   ADDR_BITS-1:0] cache_load_addr     ;
    logic [       DC_DW-1:0] write_l2_data       ;
    logic [       DC_DW-1:0] write_l2_data_c     ;
    logic [       DC_DW-1:0] dcache_data_o       ;
    logic [  DATA_WIDTH-1:0] cache_store_data    ;
    logic [       IC_DW-1:0] icache_data_o       ;
    logic [   ADDR_BITS-1:0] current_pc          ;
    logic                    hit_icache          ;
    logic                    miss_icache         ;
    logic                    partial_access      ;
    logic [ FETCH_WIDTH-1:0] fetched_data        ;
    logic                    cache_store_uncached;
    logic                    cache_store_cached  ;
    logic                    write_l2_valid_c    ;
    logic [     R_WIDTH-1:0] cache_load_dest     ;
    logic [   MICROOP_W-1:0] cache_load_microop  ;
    logic [   MICROOP_W-1:0] cache_store_microop ;
    logic [ROB_TICKET_W-1:0] cache_load_ticket   ;
    logic [             1:0] partial_type        ;
    ex_update                cache_fu_update     ;
    logic                    cache_will_block    ;
    logic                    cache_blocked       ;
    logic                    cache_store_blocked ;
    logic                    cache_load_blocked  ;

    logic        frame_buffer_write  ;
    logic [15:0] frame_buffer_data   ;
    logic [14:0] frame_buffer_address;
    logic [ 7:0] red_o, green_o, blue_o;
    logic [ 4:0] color               ;
    logic                    vector_flush_valid;
    logic                    vector_valid;      
    to_vector                vector_instruction;
    logic                    vector_ready;
    logic                    mem_req_valid_o;
    vector_mem_req           mem_req_o;       
    logic                    cache_ready_i;   
    logic                    mem_resp_valid_i;
    vector_mem_resp          mem_resp_i;            
    processor_top u_processor
    (
        .clk                    (clk  ),
        .rst_n                  (rst_n),
        .external_interrupt     (external_interrupt),
        .timer_interrupt        (timer_interrupt),
        .vector_flush_valid     (vector_flush_valid),
        .vector_valid           (vector_valid      ),        
        .vector_instruction     (vector_instruction),
        .vector_ready           (vector_ready      ),     
        //Input from ICache     
        .current_pc             (current_pc      ),
        .hit_icache             (hit_icache      ),
        .miss_icache            (miss_icache     ),
        .partial_access         (partial_access  ),
        .partial_type           (partial_type    ),
        .fetched_data           (fetched_data    ),

        .cache_wb_valid_o       (cache_store_cached ),
        .cache_wb_addr_o        (cache_store_addr   ),
        .cache_wb_data_o        (cache_store_data   ),
        .cache_wb_microop_o     (cache_store_microop),
        // Load for DCache  
        .cache_load_valid       (cache_load_valid  ),
        .cache_load_addr        (cache_load_addr   ),
        .cache_load_dest        (cache_load_dest   ),
        .cache_load_microop     (cache_load_microop),
        .cache_load_ticket      (cache_load_ticket ),
        //Misc
        .cache_fu_update        (cache_fu_update),
        .cache_store_blocked    (cache_store_blocked),
        .cache_load_blocked     (cache_load_blocked),
        .cache_will_block       (),
        .ld_st_output_used      (ld_st_output_used)
    );
    vector_top
    #(
        .VIQ_DEPTH          (4 ),
        .DATA_WIDTH         (32),
        .VECTOR_TICKET_BITS (4 ),
        .VECTOR_LANES       (8 )    
    )vector_cpu
    (
        .clk                 (clk  ),
        .rst_n               (rst_n),

        .vector_flush_valid  (vector_flush_valid), 
        .vector_valid        (vector_valid      ),
        .vector_ready        (vector_ready      ),
        .vector_instruction  (vector_instruction),

        //Cache Request Interface
    	.mem_req_valid_o     (mem_req_valid_o   ),
    	.mem_req_o           (mem_req_o         ),
    	.cache_ready_i       (cache_ready_i     ),
    	//Cache Response Interface  
    	.mem_resp_valid_i    (mem_resp_valid_i  ), 
    	.mem_resp_i          (mem_resp_i        )
    );

    data_cache 
    #(
        .DATA_WIDTH    (DATA_WIDTH  ),
        .ADDR_BITS     (ADDR_BITS   ),
        .R_WIDTH       (R_WIDTH     ),
        .MICROOP       (MICROOP_W   ),
        .ROB_TICKET    (ROB_TICKET_W),
        .ENTRIES       (DC_ENTRIES  ),
        .BLOCK_WIDTH   (DC_DW       ),
        .BUFFER_SIZES  (4           ),
        .ASSOCIATIVITY (4           ),
        .VECTOR_ENABLED(1           )
    ) data_cache (
        .clk                 (clk                ),
        .rst_n               (rst_n              ),
        .output_used         (ld_st_output_used  ),
        //Load Input Port 
        .load_valid          (cache_load_valid  ),
        .load_address        (cache_load_addr   ),
        .load_dest           (cache_load_dest   ),
        .load_microop        (cache_load_microop),
        .load_ticket         (cache_load_ticket ),
        //Store Input Port 
        .store_valid         (cache_store_cached ),
        .store_address       (cache_store_addr   ),
        .store_data          (cache_store_data   ),
        .store_microop       (cache_store_microop),
        //Request Write Port to L2
        .write_l2_valid      (write_l2_valid_c   ),
        .write_l2_addr       (write_l2_addr_c    ),
        .write_l2_data       (write_l2_data_c    ),
        //Request Read Port to L2
        .request_l2_valid    (dcache_valid_i     ),
        .request_l2_addr     (dcache_address_i   ),
        // Update Port from L2
        .update_l2_valid     (dcache_valid_o     ),
        .update_l2_addr      (dcache_address_o   ),
        .update_l2_data      (dcache_data_o      ),
        //Output Port 
        .cache_will_block    (cache_will_block   ),
        .cache_store_blocked (cache_store_blocked),
        .cache_load_blocked  (cache_load_blocked ),
        .served_output       (cache_fu_update    ),

        .mem_req_valid_i     (mem_req_valid_o    ),
        .mem_req_i           (mem_req_o          ),
        .cache_vector_ready_o(cache_ready_i      ),
        .vector_resp_valid_o (mem_resp_valid_i   ),
        .vector_resp         (mem_resp_i         )
    );
    icache 
    #(
        .ENTRIES                (256),
        .ASSOCIATIVITY          (2  ),
        .BLOCK_WIDTH            (IC_DW),
        .INSTR_BITS             (32 ),
        .DATA_BUS_WIDTH         (64)
    )u_icache 
    (
        .clk                    (clk             ),
        .rst_n                  (rst_n           ),

		.address                (current_pc      ),
		.hit                    (hit_icache      ),
		.miss                   (miss_icache     ),
		.partial_access         (partial_access  ),
		.partial_type           (partial_type    ),
		.fetched_data           (fetched_data    ),

        .valid_o                (icache_valid_i  ),
        .ready_in               (icache_valid_o  ),
        .address_out            (icache_address_i),
        .data_in                (icache_data_o   )
    );
    main_memory  
    #(
        .L2_BLOCK_DW     (512) ,
        .L2_ENTRIES      (L2_ENTRIES),
        .ADDRESS_BITS    (32)  ,
        .ICACHE_BLOCK_DW (IC_DW) ,
        .DCACHE_BLOCK_DW (256) ,
        .REALISTIC       (REALISTIC)   ,
        .DELAY_CYCLES    (DELAY_CYCLES)  
    )u_main_memory
    (
        .clk              (clk             ),
        .rst_n            (rst_n           ),
        //Read Request Input from ICache
        .icache_valid_i   (icache_valid_i  ),
        .icache_address_i (icache_address_i),
        //Output to ICache
        .icache_valid_o   (icache_valid_o  ),
        //.icache_address_o (icache_address_o),
        .icache_data_o    (icache_data_o   ),
        //Read Request Input from DCache
        .dcache_valid_i   (dcache_valid_i  ),
        .dcache_address_i (dcache_address_i),
        //Output to DCache
        .dcache_valid_o   (dcache_valid_o  ),
        .dcache_address_o (dcache_address_o),
        .dcache_data_o    (dcache_data_o   ),
        //Write Request Input from DCache
        .dcache_valid_wr  (write_l2_valid  ),
        .dcache_address_wr(write_l2_addr   ),
        .dcache_data_wr   (write_l2_data   )
    );
endmodule