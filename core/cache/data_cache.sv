//{Valid}{Dirty}[Tag][Data]
module data_cache #(
    parameter DATA_WIDTH           = 32   ,//
    parameter ADDR_BITS            = 32   ,//
    parameter R_WIDTH              = 6    ,//物理寄存器位宽（64个）
    parameter MICROOP              = 5    ,//
    parameter ROB_TICKET           = 3    ,//ROB编号
    parameter ASSOCIATIVITY        = 4    ,//D-Cache路数
    parameter ENTRIES              = 256  ,//Cache line数
    parameter BLOCK_WIDTH          = 256  ,//Cache line位宽
    parameter BUFFER_SIZES         = 4    ,//Load/Store buffer深度
    parameter VECTOR_ENABLED       = 1    ,
    parameter VECTOR_MICROOP_WIDTH = 7    ,
    parameter VECTOR_REQ_WIDTH     = 256  ,
    parameter VECTOR_LANES         = 8
) (
    input  logic                   clk                ,
    input  logic                   rst_n              ,
    input  logic                   output_used        ,
    //Load Input Port
    input  logic                   load_valid         ,
    input  logic [  ADDR_BITS-1:0] load_address       ,
    input  logic [    R_WIDTH-1:0] load_dest          ,
    input  logic [    MICROOP-1:0] load_microop       ,
    input  logic [ ROB_TICKET-1:0] load_ticket        ,
    //Store Input Port
    input  logic                   store_valid        ,
    input  logic [  ADDR_BITS-1:0] store_address      ,
    input  logic [ DATA_WIDTH-1:0] store_data         ,
    input  logic [    MICROOP-1:0] store_microop      ,
    //Request Write Port to L2
    output logic                   write_l2_valid     ,
    output logic [  ADDR_BITS-1:0] write_l2_addr      ,
    output logic [BLOCK_WIDTH-1:0] write_l2_data      ,
    //Request Read Port to L2
    output logic                   request_l2_valid   ,
    output logic [  ADDR_BITS-1:0] request_l2_addr    ,
    input  logic                   update_l2_valid    ,
    input  logic [  ADDR_BITS-1:0] update_l2_addr     ,
    input  logic [BLOCK_WIDTH-1:0] update_l2_data     ,
    //Output Port
    output logic                   cache_load_blocked ,
    output logic                   cache_store_blocked,
    output logic                   cache_will_block   ,
    output ex_update               served_output      ,
    //Vector Req Input Port
    input  logic                   mem_req_valid_i     ,
    input  vector_mem_req          mem_req_i           ,
    output logic                   cache_vector_ready_o,
    output logic                   vector_resp_valid_o ,
    output vector_mem_resp         vector_resp
);
    //Local Parameter
    localparam OUTPUT_BITS   = $clog2(ASSOCIATIVITY);
    localparam INDEX_BITS    = $clog2(ENTRIES);
    localparam OFFSET_BITS   = $clog2(BLOCK_WIDTH/DATA_WIDTH)+2;
    localparam TAG_BITS      = ADDR_BITS-INDEX_BITS-OFFSET_BITS;

    // #Internal Signals#
    logic [ROB_TICKET-1:0] ld_head_ticket, wt_s_ticket, wt_w_ticket;
    logic [ADDR_BITS-1:0]  ld_head_addr, st_head_addr, wt_w_address, saved_search_addr, served_address, wt_search_addr, search_address_o;
    logic [DATA_WIDTH-1:0] st_head_data, wt_s_data, wt_s_frw_data, wt_w_data, st_s_data, served_data;
    logic [MICROOP-1:0]    ld_head_microop, st_head_microop, wt_s_microop, wt_w_microop,  served_microop;
    logic [R_WIDTH-1:0]    ld_head_dest, wt_s_dest, wt_w_dest;
    logic                  ld_ready, ld_valid, st_ready, st_valid, wt_ready, wt_valid, wt_in_walk;
    logic                  ld_pop, ld_push, st_pop, st_push, store_isfetched, wt_push;
    logic                  ld_head_isfetched, st_head_isfetched;
    logic                  wt_invalidate, wt_found_one, wt_s_frw_hit, wt_s_isstore, wt_w_isstore;
    logic                  ld_s_phit, st_s_vhit, st_s_phit, served_exc_v;
    // Second Read port related signals
    logic [ASSOCIATIVITY-1:0][BLOCK_WIDTH-1:0] data_b            ;
    logic [ASSOCIATIVITY-1:0][   TAG_BITS-1:0] tag_b             ;
    logic [   INDEX_BITS-1:0]                  read_line_select_b;
    logic [     TAG_BITS-1:0]                  tag_usearch_b     ;
    logic [ASSOCIATIVITY-1:0]                  entry_found_b     ;
    logic [  BLOCK_WIDTH-1:0]                  block_picked_b    ;
    logic                                      Hit_a, Hit_b;
    logic [    VECTOR_REQ_WIDTH-1:0] vct_served_data     ;
    logic [         BLOCK_WIDTH-1:0] vct_new_modded_block;
    logic [           ADDR_BITS-1:0] vct_head_addr       ;
    logic [           ADDR_BITS-1:0] vct_head_addr_b     ;
    logic [VECTOR_MICROOP_WIDTH-1:0] vct_head_microop    ;
    logic [                     1:0] vct_head_requested  ;
    logic                            vct_valid           ;
    logic                            vct_head_isstore    ;
    logic                            vct_request_a       ;
    logic                            vct_request_b       ;

    logic [ASSOCIATIVITY-1:0][BLOCK_WIDTH-1:0] data, overwritten_data;
    logic [ASSOCIATIVITY-1:0][TAG_BITS-1:0]    tag, overwritten_tag;
    logic [ASSOCIATIVITY-1:0][ENTRIES-1:0]     validity, dirty;
    logic [$clog2(ASSOCIATIVITY)-1:0]          entry_used;
    logic [INDEX_BITS-1:0]                     read_line_select, write_line_select;
    logic [OUTPUT_BITS-1:0]                    lru_way, new_valid_entry;
    logic [ASSOCIATIVITY-1:0]                  write_en_tag, write_en_data, all_valid_temp, entry_found;
    logic [TAG_BITS-1:0]                       new_tag, update_l2_tag, new_modded_tag, tag_usearch, tag_picked;
    logic [BLOCK_WIDTH-1:0]                    new_data, new_modded_block, block_picked, scalar_new_modded_block;
    logic [DATA_WIDTH-1:0]                     data_picked;
    logic [3:0]                                served_exc;
    logic                                      all_valid, lru_update, hit, hit_b, served, must_wait;

    logic [OFFSET_BITS-1:0]                         offset_select;
    logic [2:0][INDEX_BITS-1:0]                     read_address;
    logic [ASSOCIATIVITY-1:0][2:0][TAG_BITS-1:0]    read_tag;
    logic [ASSOCIATIVITY-1:0][2:0][BLOCK_WIDTH-1:0] read_data;
    //Serve FSM
    typedef enum logic [2:0] {IDLE, LD_IN, ST_IN, LD, ST, WT, VCT_LD, VCT_ST} serve_mode;
    serve_mode serve;

    //判断Cache是否命中需要的条件
    assign offset_select     = served_address[OFFSET_BITS-1 : 0];//选择对应Byte
    assign read_line_select  = served_address[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];//选择对应Cacheline
    assign tag_usearch       = served_address[OFFSET_BITS+INDEX_BITS +: TAG_BITS];
    //Cache hit时，直接写入Cache；Cache miss时，需要等待L2 Cache回填
    assign write_line_select = update_l2_valid ? update_l2_addr[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS] : served_address[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
    assign new_data          = update_l2_valid ? update_l2_data : new_modded_block;
    assign new_tag           = update_l2_valid ? update_l2_tag : new_modded_tag;                    //- same as the saved/read tag
    assign update_l2_tag     = update_l2_addr[OFFSET_BITS+INDEX_BITS +: TAG_BITS];
    //Cache miss时向L2 Cache请求回填
    assign request_l2_valid = (serve==LD_IN & ~served & ~ld_s_phit & ~st_s_phit) | (serve==ST_IN & ~served & ~st_s_phit & ~ld_s_phit & ~hit)
                              | vct_request_a | vct_request_b;//~served说明miss且无法bypass
    assign request_l2_addr  = vct_request_a ? vct_head_addr   :
                              vct_request_b ? vct_head_addr_b :
                                              served_address;
    //Writeback策略下向L2 Cache更新数据
    assign write_l2_valid = update_l2_valid & all_valid & dirty[lru_way][write_line_select];//判断是否dirty
    assign write_l2_addr  = {overwritten_tag[lru_way],write_line_select, {OFFSET_BITS{1'b0}}};
    assign write_l2_data  = overwritten_data[lru_way];

    assign cache_will_block    = wt_invalidate;
    assign cache_load_blocked  = wt_in_walk | ~ld_ready | ~wt_ready;
    assign cache_store_blocked = wt_in_walk | (load_valid & ~cache_load_blocked) | ~st_ready | ~wt_ready;
    //写回阶段的输出
    always_comb begin
        if(serve==LD_IN) begin
            served_output.valid           = served;
            served_output.destination     = load_dest;
            served_output.ticket          = load_ticket;
            served_output.valid_exception = served_exc_v;
            served_output.cause           = served_exc;
        end else if(serve==ST_IN) begin
            served_output.valid           = 1'b0;
            served_output.destination     = load_dest;
            served_output.ticket          = load_ticket;
            served_output.valid_exception = served_exc_v;
            served_output.cause           = served_exc;
        end else if(serve==LD) begin
            served_output.valid           = 1'b1;
            served_output.destination     = ld_head_dest;
            served_output.ticket          = ld_head_ticket;
            served_output.valid_exception = served_exc_v;
            served_output.cause           = served_exc;
        end else if(serve==ST) begin
            served_output.valid           = 1'b0;
            served_output.destination     = load_dest;
            served_output.ticket          = load_ticket;
            served_output.valid_exception = served_exc_v;
            served_output.cause           = served_exc;
        end else if(serve==WT) begin
            served_output.valid           = ~wt_s_isstore;
            served_output.destination     = wt_s_dest;
            served_output.ticket          = wt_s_ticket;
            served_output.valid_exception = served_exc_v;
            served_output.cause           = served_exc;
        end else begin
            served_output.valid           = 1'b0;
            served_output.destination     = load_dest;
            served_output.ticket          = load_ticket;
            served_output.valid_exception = served_exc_v;
            served_output.cause           = served_exc;
        end
    end
//在实现上，每个Way都使用两块独立的SRAM分别作为Tag-ram和Data-ram，并行地访问。
    genvar i;
    generate if(VECTOR_ENABLED) begin : D_Cache_data
        assign read_address[0] = read_line_select;
        assign read_address[1] = write_line_select;
        assign read_address[2] = read_line_select_b;
        for (i = 0; i < ASSOCIATIVITY ; i = i + 1) begin
            //read
            assign tag[i]              = read_tag[i][0];
            assign data[i]             = read_data[i][0];
            //write 
            assign overwritten_tag[i]  = read_tag[i][1];
            assign overwritten_data[i] = read_data[i][1];
            //read port2
            assign tag_b[i]              = read_tag[i][2];
            assign data_b[i]             = read_data[i][2];
            sram 
            #(
                .SIZE           (ENTRIES            ),
                .DATA_WIDTH     (TAG_BITS           ),
                .RD_PORTS       (3                  ),
                .WR_PORTS       (1                  ),
                .RESETABLE      (0                  )
            )
            TAG_RAM
            (
                .clk            (clk                ),
                .rst_n          (rst_n              ),
                .read_address   (read_address       ),
                .data_out       (read_tag[i]        ),
                .wr_en          (write_en_tag[i]    ),
                .write_address  (write_line_select  ),
                .new_data       (new_tag            )
            );
            sram 
            #(
                .SIZE           (ENTRIES            ),
                .DATA_WIDTH     (BLOCK_WIDTH        ),
                .RD_PORTS       (3                  ),
                .WR_PORTS       (1                  ),
                .RESETABLE      (0                  )
            )
            DATA_RAM
            (   
                .clk            (clk                ),
                .rst_n          (rst_n              ),
                .read_address   (read_address       ),
                .data_out       (read_data[i]       ),
                .wr_en          (write_en_data[i]   ),
                .write_address  (write_line_select  ),
                .new_data       (new_data           )
            );
            end
        end
        else begin
            assign read_address[0] = read_line_select;
            assign read_address[1] = write_line_select;
            for (i = 0; i < ASSOCIATIVITY ; i = i + 1) begin
                assign tag[i]             = read_tag[i][0];
                assign overwritten_tag[i] = read_tag[i][1];
                assign data[i]            = read_data[i][0];
                assign overwritten_data[i]= read_data[i][1];
            // Initialize the Tag Banks for each Set    -> Outputs the saved Tags
            sram #(.SIZE        (ENTRIES),
                   .DATA_WIDTH  (TAG_BITS),
                   .RD_PORTS    (2),
                   .WR_PORTS    (1),
                   .RESETABLE   (0))
            sram_tag(.clk                  (clk),
                     .rst_n                (rst_n),
                     .read_address         (read_address),
                     .data_out             (read_tag[i]),
                     .Wr_En                (write_en_tag[i]),
                     .write_address        (write_line_select),
                     .new_data             (new_tag));
            // Initialize the Data Banks for each Set   -> Outputs the saved Data
            sram #(.SIZE        (ENTRIES),
                   .DATA_WIDTH  (BLOCK_WIDTH),
                   .RD_PORTS    (2),
                   .WR_PORTS    (1),
                   .RESETABLE   (0))
            sram_data(.clk                  (clk),
                      .rst_n                (rst_n),
                      .read_address         (read_address),
                      .data_out             (read_data[i]),
                      .Wr_En                (write_en_data[i]),
                      .write_address        (write_line_select),
                      .new_data             (new_data));
            end
        end
    endgenerate
    //在非直接映射的结构下，需要使用Cache替换策略
    generate
        if(ASSOCIATIVITY>1) begin
            lru 
            #(
                .ASSOCIATIVITY  (ASSOCIATIVITY      ),
                .ENTRIES        (ENTRIES            ),
                .INDEX_BITS     (INDEX_BITS         ),
                .OUTPUT_BITS    (OUTPUT_BITS        )
            )
            LRU
            (
                .clk            (clk                ),
                .rst_n          (rst_n              ),
                .line_selector  (update_l2_valid ? update_l2_addr[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS] : read_line_select),
                .referenced_set (entry_used         ),
                .lru_update     (lru_update         ),
                .lru_way        (lru_way            )
            );
        end
    endgenerate
    //判断Cache是否命中
    always_comb begin : FindEntry
        entry_used  = 0;
        block_picked = data[0];
        tag_picked  = tag[0];
        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            if((tag[i]==tag_usearch) && validity[i][read_line_select]) begin
                entry_found[i] = 1'd1;
                entry_used     = i;
                block_picked   = data[i];
                tag_picked     = tag[i];
            end else begin
                entry_found[i] = 1'd0;
            end
        end
    end
    assign hit = |entry_found;
    // Create the second read memory port when vector enabled
    generate if (VECTOR_ENABLED) begin
        assign read_line_select_b  = vct_head_addr_b[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
        assign tag_usearch_b       = vct_head_addr_b[OFFSET_BITS+INDEX_BITS +: TAG_BITS];
        always_comb begin : FindEntry_B
            block_picked_b = data[0];
            for (int i = 0; i < ASSOCIATIVITY; i++) begin
                if((tag_b[i]==tag_usearch_b) && validity[i][read_line_select_b]) begin
                    entry_found_b[i] = 1'd1;
                    block_picked_b   = data_b[i];
                end else begin
                    entry_found_b[i] = 1'd0;
                end
            end
        end
        assign Hit_b = |entry_found_b;
    end endgenerate
//Cache hit或可以bypass时，serve等于1
//我们希望Load指令可以尽快地完成，这样可以使得后续的计算指令可以尽快地开始进行。
//当Load指令的地址已经计算好的时候，就可以去取数据，这时候，首先要去Store Queue里面找，
//如果有Store指令要写入的地址等于Load的地址，说明后面的Load依赖于前面的Store，
//如果Store的数据已经准备好了，就可以直接把数据转发过来，就不需要从Cache中获取，
//如果数据还没准备好，就需要等待这一条Store完成；如果没有找到匹配的Store指令，再从内存中取。
    always_comb begin
        //检测RAW冲突：对于Load指令，需要和前面Store指令的地址进行比较，如果匹配，可以bypass
        if(serve==LD_IN) begin
            if(load_dest == 0) begin
                served     = 1'b1;
                must_wait  = 1'b0;
                lru_update = 1'b0;
                served_output.data = 0;
            end 
            else if(wt_s_frw_hit) begin//首先要去wait buffer里面找
                //Forward from Wait Buffer
                served     = 1'b1;
                must_wait  = 1'b0;
                lru_update = 1'b0;
                served_output.data = wt_s_frw_data;
            end 
            else if(st_s_vhit) begin//如果Store的数据已经准备好了，就可以直接把数据转发过来
                //Forward from Store Buffer
                served     = 1'b1;
                must_wait  = 1'b0;
                lru_update = 1'b0;
                served_output.data = st_s_data;
            end 
            //st_s_phit指令该Load指令和上一条miss的store指令处于同一个Cache line
            //需要等待相关的store指令miss回填完才可以继续执行，所以存入Wait buffer
            else if(st_s_phit) begin
                //Store in wait buffer
                served     = 1'b0;
                must_wait  = 1'b1;
                lru_update = 1'b0;
                served_output.data = served_data;
            end 
            else if(hit) begin//不能bypass再去Cache里面找
                //Grab from Cache
                served     = 1'b1;
                must_wait  = 1'b0;
                lru_update = 1'b1;
                served_output.data = served_data;
            end 
            else begin
                //Can not Serve
                served     = 1'b0;
                lru_update = 1'b0;
                served_output.data = served_data;
                if(st_s_phit | ld_s_phit) begin
                //Store in Wait Buffer
                    must_wait = 1'b1;
                end else begin
                //Store in Load Buffer
                    must_wait = 1'b0;
                end
            end
        end 
        //对于Load指令如果发生miss需要从下级存储器先读取对应Cache line，再修改对应数据，再将对应Dirty位置1
        else if(serve==ST_IN) begin
            served_output.data = served_data;
            if(update_l2_valid) begin//Cahe正在回填
                //Write Conflict.. Store will wait in Buffers
                served     = 1'b0;
                lru_update = 1'b0;
                if(st_s_phit | ld_s_phit) begin
                    //Store in Wait Buffer
                    must_wait = 1'b1;
                end 
                else begin
                    //Store in Store Buffer
                    must_wait = 1'b0;
                end
            end 
            else begin
                //Serve the Store
                if(st_s_phit | ld_s_phit) begin//store指令和上一条miss的store/load指令处于同一个Cache line
                    //Previous Store was in ST Buffer.. Must wait in Wait Buffer
                    served     = 1'b0;
                    must_wait  = 1'b1;
                    lru_update = 1'b0;
                end else if(hit) begin
                    //If hit Serve Normally
                    served     = 1'b1;
                    must_wait  = 1'b0;
                    lru_update = 1'b1;
                end else begin
                    //Store in Store Buffer
                    served     = 1'b0;
                    must_wait  = 1'b0;
                    lru_update = 1'b0;
                end
            end
        end 
        else if(serve==LD) begin
            served     = 1'b1;
            must_wait  = 1'b0;
            lru_update = 1'b1;
            served_output.data = served_data;
        end 
        else if(serve==ST) begin
            served     = 1'b1;
            must_wait  = 1'b0;
            lru_update = 1'b1;
            served_output.data = served_data;
        end 
        else if (serve==WT) begin
            served     = 1'b1;
            must_wait  = 1'b0;
            lru_update = 1'b1;
            served_output.data = served_data;
        end 
        else if (serve==VCT_LD) begin
            served     = hit;
            must_wait  = 1'b0;
            lru_update = hit;
            served_output.data = served_data;
        end 
        else if (serve==VCT_ST) begin
            served     = hit;
            must_wait  = 1'b0;
            lru_update = hit;
            served_output.data = served_data;
        end
        else begin
            served     = 1'b0;
            must_wait  = 1'b0;
            lru_update = 1'b0;
            served_output.data = served_data;
        end
    end
    //Search for Validities
    always_comb begin
        //all_valid<='d1;
        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            all_valid_temp[i] = validity[i][write_line_select];
        end
    end
    //Indicates if all entries are valid
    assign all_valid = &all_valid_temp;

    //WRITE Enablers
    generate
        if(ASSOCIATIVITY>1) begin
            always_comb begin : WriteEnablers
                new_valid_entry = 0;
                write_en_data = 'b0;
                write_en_tag  = 'b0;
                if(update_l2_valid) begin
                    write_en_data = 'b0;
                    write_en_tag  = 'b0;
                    //Check if invalid entries exist
                    if(!all_valid) begin
                        for (int i = 0; i < ASSOCIATIVITY; i++) begin
                            if(!validity[i][write_line_select]) begin
                                new_valid_entry = i;
                                write_en_data[i] = 1'b1;
                                write_en_tag[i]  = 1'b1;
                                break;
                            end
                        end
                    end else begin
                        //no invalid entries, evict LRU
                        new_valid_entry = lru_way;
                        write_en_data[lru_way] = 1'b1;
                        write_en_tag[lru_way]  = 1'b1;
                    end
                end else if (serve==ST_IN && served) begin
                    write_en_data[entry_used] = 1'b1;
                    write_en_tag[entry_used]  = 1'b0;
                end else if (serve==ST) begin
                    write_en_data[entry_used] = 1'b1;
                    write_en_tag[entry_used]  = 1'b0;
                end else if(serve==WT && wt_s_isstore) begin
                    write_en_data[entry_used] = 1'b1;
                    write_en_tag[entry_used]  = 1'b0;
                end else begin
                    write_en_data = 'b0;
                    write_en_tag  = 'b0;
                end
            end
        end 
        else if (ASSOCIATIVITY==1) begin
            assign write_en_data = update_l2_valid | (serve==ST_IN && served) | (serve==ST) | (serve==WT && wt_s_isstore);
            assign write_en_tag  = update_l2_valid;
        end
    endgenerate

    //VALIDITY Management
    generate
        if(ASSOCIATIVITY>1) begin
            always_ff @(posedge clk or negedge rst_n) begin : ValidityManagement
                if(!rst_n) begin
                    for (int i = 0; i < ASSOCIATIVITY; i++) begin
                        validity[i] <= 'b0;
                    end
                end else begin
                    if(update_l2_valid) begin
                        if(!all_valid) begin
                            //Store new Data into an invalid Entry
                            validity[new_valid_entry][write_line_select] <= 1'b1;
                        end else begin
                            //Store new Data into the LRU Entry
                            validity[lru_way][write_line_select] <= 1'b1;
                        end
                    end
                end
            end
        end 
        else if (ASSOCIATIVITY==1) begin
            always_ff @(posedge clk or negedge rst_n) begin : ValidityManagement
                if(!rst_n) begin
                    validity <= 0;
                end else begin
                    if(update_l2_valid) begin
                        //Store new Data into the Entry
                        validity[write_line_select] <= 1'b1;
                    end
                end
            end
        end
    endgenerate

    //DIRTY Management
    generate
        if(ASSOCIATIVITY>1) begin
            always_ff @(posedge clk or negedge rst_n) begin : DirtyManagement
                if(!rst_n) begin
                    for (int i = 0; i < ASSOCIATIVITY; i++) begin
                        dirty[i] <= 'b0;
                    end
                end 
                else begin
                    if(update_l2_valid) begin
                        if(!all_valid) begin
                            //Store new Data into an invalid Entry
                            dirty[new_valid_entry][write_line_select] <= 1'b0;
                        end 
                        else begin
                            //Store new Data into the LRU Entry
                            dirty[lru_way][write_line_select] <= 1'b0;
                        end
                    end 
                    else if(serve==ST_IN && served) begin
                        dirty[entry_used][write_line_select] <= 1'b1;
                    end 
                    else if(serve==ST) begin
                        dirty[entry_used][write_line_select] <= 1'b1;
                    end 
                    else if(serve==WT && wt_s_isstore) begin
                        dirty[entry_used][write_line_select] <= 1'b1;
                    end
                end
            end
        end else if (ASSOCIATIVITY==1) begin
            always_ff @(posedge clk or negedge rst_n) begin : DirtyManagement
                if(!rst_n) begin
                    dirty <= 'b0;
                end 
                else begin
                    if(update_l2_valid) begin
                        dirty[write_line_select] <= 1'b0;
                    end else if(serve==ST_IN && served) begin
                        dirty[write_line_select] <= 1'b1;
                    end else if(serve==ST) begin
                        dirty[write_line_select] <= 1'b1;
                    end else if(serve==WT && wt_s_isstore) begin
                        dirty[write_line_select] <= 1'b1;
                    end
                end
            end
        end
    endgenerate

    //在接收到load/store指令时存入buffer中
    always_comb begin
        if(wt_in_walk) begin
            serve          = WT;
            served_address = search_address_o;
            served_microop = wt_s_microop;
        end 
//load/store指令输入优先
        //将load/store存入buffer
        else if(load_valid && !output_used) begin
            serve          = LD_IN;
            served_address = load_address;
            served_microop = load_microop;
        end 
        else if(store_valid && !output_used) begin
            serve          = ST_IN;
            served_address = store_address;
            served_microop = store_microop;
        end 
        
        //最旧的指令已经取到数据,将buffer中的指令读出
        else if(ld_valid && ld_head_isfetched && !output_used) begin//
            serve          = LD;
            served_address = ld_head_addr;
            served_microop = ld_head_microop;
        end 
        else if(st_valid && st_head_isfetched && !output_used && !update_l2_valid) begin
            serve          = ST;
            served_address = st_head_addr;
            served_microop = st_head_microop;
        end 
        else if (vct_valid && !vct_head_isstore) begin
            serve          = VCT_LD;
            served_address = vct_head_addr;
            served_microop = vct_head_microop;
        end 
        else if (vct_valid && vct_head_isstore && !update_l2_valid) begin
            serve          = VCT_ST;
            served_address = vct_head_addr;
            served_microop = vct_head_microop;
        end
        else begin
            serve          = IDLE;
            served_address = load_address;
            served_microop = load_microop;
        end
    end

    // New tag on hit stores is the same as the old one
    assign new_modded_tag = tag_picked;

    always_comb begin : DataPicked
        if(serve==ST_IN) begin
            data_picked = store_data;
        end else if(serve==ST) begin
            data_picked = st_head_data;
        end else begin
            data_picked = wt_s_data;
        end
    end
    //Initialize the Operations Module
    data_operation 
    #(
        .ADDR_W     (OFFSET_BITS),
        .DATA_W     (DATA_WIDTH),
        .MICROOP    (MICROOP),
        .BLOCK_W    (BLOCK_WIDTH),
        .LOAD_ONLY  (0)
    )
    data_operation  
    (
        .input_address  (offset_select),
        .input_block    (block_picked),
        .input_data     (data_picked),
        .microop        (served_microop),

        .valid_exc      (served_exc_v),
        .exception      (served_exc),
        .output_block   (scalar_new_modded_block),
        .output_vector  (served_data)
    );

    assign ld_pop  = (serve==LD);
    assign ld_push = (serve==LD_IN) & ~served & ~must_wait & ~ld_s_phit;
    //Initialize the Load Buffer
    ld_st_buffer 
    #(
        .DATA_WIDTH         (DATA_WIDTH     ),
        .ADDR_BITS          (ADDR_BITS      ),
        .BLOCK_ID_START     (OFFSET_BITS    ),
        .R_WIDTH            (R_WIDTH        ),
        .MICROOP            (MICROOP        ),
        .ROB_TICKET         (ROB_TICKET     ),
        .DEPTH              (BUFFER_SIZES   )
    )
    load_buffer 
    (
        .clk                (clk            ),
        .rst_n              (rst_n          ),

        .push               (ld_push        ),
        .write_address      (load_address   ),
        .write_data         (               ),
        .write_microop      (load_microop   ),
        .write_dest         (load_dest      ),
        .write_ticket       (load_ticket    ),
        .write_isfetched    (1'b0           ),

        .search_address     (served_address ),
        .search_microop_in  (               ),
        .search_data        (               ),
        .search_microop     (               ),
        .search_dest        (               ),
        .search_ticket      (               ),
        .search_valid_hit   (               ),
        .search_partial_hit (ld_s_phit      ),

        .valid_update       (update_l2_valid),
        .update_address     (update_l2_addr ),

        .pop                (ld_pop         ),
        .head_isfetched     (ld_head_isfetched),//？
        .head_address       (ld_head_addr   ),
        .head_data          (               ),
        .head_microop       (ld_head_microop),
        .head_dest          (ld_head_dest   ),
        .head_ticket        (ld_head_ticket ),

        .valid              (ld_valid       ),
        .ready              (ld_ready       )
        );

    assign st_pop  = (serve==ST);
    assign st_push = (serve==ST_IN & ~served & ~must_wait & ~st_s_phit);
    //Initialize the Store Buffer
    ld_st_buffer 
    #(
        .DATA_WIDTH         (DATA_WIDTH     ),
        .ADDR_BITS          (ADDR_BITS      ),
        .BLOCK_ID_START     (OFFSET_BITS    ),
        .R_WIDTH            (R_WIDTH        ),
        .MICROOP            (MICROOP        ),
        .ROB_TICKET         (ROB_TICKET     ),
        .DEPTH              (BUFFER_SIZES   )
    )store_buffer 
    (
        .clk                (clk            ),
        .rst_n              (rst_n          ),

        .push               (st_push        ),
        .write_address      (store_address  ),
        .write_data         (store_data     ),
        .write_microop      (store_microop  ),
        .write_dest         (               ),
        .write_ticket       (               ),
        .write_isfetched    (hit            ),

        .search_address     (served_address ),
        .search_microop_in  (served_microop ),
        .search_data        (st_s_data      ),
        .search_microop     (               ),
        .search_dest        (               ),
        .search_ticket      (               ),
        .search_valid_hit   (st_s_vhit      ),
        .search_partial_hit (st_s_phit      ),

        .valid_update       (update_l2_valid),
        .update_address     (update_l2_addr ),

        .pop                (st_pop),
        .head_isfetched     (st_head_isfetched),
        .head_address       (st_head_addr),
        .head_data          (st_head_data),
        .head_microop       (st_head_microop),
        .head_dest          (),             //NC
        .head_ticket        (),             //NC

        .valid              (st_valid),
        .ready              (st_ready)
    );

    //Wait Buffer变为Walk模式的信号
    assign wt_invalidate = (serve==LD | serve==ST) & wt_found_one;//原来miss的指令已经回填完成
    //Save the Search Address
    always_ff @(posedge clk) begin : SavedSearch
        if(serve==LD && wt_found_one) begin
                saved_search_addr <= ld_head_addr;
        end else if(serve==ST && wt_found_one) begin
            saved_search_addr <= st_head_addr;
        end
    end

    always_comb begin : WaitBufferInputs
        wt_w_dest   = load_dest;
        wt_w_ticket = load_ticket;
        wt_w_data   = store_data;
        if(serve==LD_IN) begin
            wt_w_address = load_address;
            wt_w_microop = load_microop;
        end else begin
            wt_w_address = store_address;
            wt_w_microop = store_microop;
        end
    end

    assign wt_w_isstore = (serve==ST_IN);
    assign wt_push = (serve==LD_IN & ~served & must_wait) | (serve==ST_IN & ~served & must_wait);
    assign wt_search_addr = (serve==WT) ? saved_search_addr: served_address;
    //当存在冲突时，将Load/Store指令存入wait buffer
    wait_buffer 
    #(
        .DATA_WIDTH         (DATA_WIDTH),
        .ADDR_BITS          (ADDR_BITS),
        .R_WIDTH            (R_WIDTH),
        .MICROOP            (MICROOP),
        .ROB_TICKET         (ROB_TICKET),
        .DEPTH              (2*BUFFER_SIZES)
    )
    wait_buffer
    (
        .clk                (clk            ),
        .rst_n              (rst_n          ),

        .write_enable       (wt_push        ),
        .write_is_store     (wt_w_isstore   ),
        .write_address      (wt_w_address   ),
        .write_data         (wt_w_data      ),
        .write_microop      (wt_w_microop   ),
        .write_dest         (wt_w_dest      ),
        .write_ticket       (wt_w_ticket    ),

        .search_invalidate  (wt_invalidate  ),
        .search_address     (wt_search_addr ),
        .search_microop_in  (served_microop ),
        .search_address_o   (search_address_o),
        .search_is_store    (wt_s_isstore   ),
        .search_data        (wt_s_data      ),
        .search_frw_data    (wt_s_frw_data  ),
        .search_microop     (wt_s_microop   ),
        .search_dest        (wt_s_dest      ),
        .search_ticket      (wt_s_ticket    ),
        .search_valid_hit   (wt_s_frw_hit   ),//load指令的地址与wait buffer中store指令的地址匹配，可以bypass对应数据

        .valid              (wt_valid       ),
        .ready              (wt_ready       ),
        .search_found_one   (wt_found_one   ),
        .search_found_multi (               ),
        .in_walk_mode       (wt_in_walk     )
    );

    generate if(VECTOR_ENABLED) begin: g_vector_buffer
        localparam SIZE_WIDTH = $clog2(VECTOR_REQ_WIDTH/8)+1;

        logic [  VECTOR_REQ_WIDTH-1:0] vct_head_data              ;
        logic [        SIZE_WIDTH-1:0] vct_head_size              ;
        logic [        INDEX_BITS-1:0] line_select_a              ;
        logic [        INDEX_BITS-1:0] line_select_b              ;
        logic [     2*BLOCK_WIDTH-1:0] block_picked_double        ;
        logic [     2*BLOCK_WIDTH-1:0] vct_new_modded_block_double;
        logic [$clog2(VECTOR_LANES):0] vct_head_ticket            ;
        logic                          nxt_multi_fetches_needed   ;
        logic                          multi_fetches_needed       ;
        logic                          multi_fetches_en           ;
        logic                          vct_push                   ;
        logic                          vct_pop                    ;

        assign Hit_a    = hit;
        assign vct_push = mem_req_valid_i & cache_vector_ready_o;//输入握手
        assign vct_pop  = (multi_fetches_needed | nxt_multi_fetches_needed) ? (serve===VCT_ST | serve===VCT_LD) & Hit_a & Hit_b :
                                                                              (serve===VCT_ST | serve===VCT_LD) & Hit_a;
        //Calculate if the data span in two cache lines
        assign vct_head_addr_b          = vct_head_addr + vct_head_size -1;
        assign line_select_a            = vct_head_addr[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
        assign line_select_b            = vct_head_addr_b[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
        assign nxt_multi_fetches_needed = (line_select_a !== line_select_b); //check if cross cache line

        assign multi_fetches_en = ~multi_fetches_needed & (serve===VCT_ST | serve===VCT_LD);
        always_ff @(posedge clk or negedge rst_n) begin : proc_multi_fetch_FSM
            if(~rst_n) begin
                multi_fetches_needed <= 1'b0;
            end else if (multi_fetches_en) begin
                multi_fetches_needed <= nxt_multi_fetches_needed;
            end else if (multi_fetches_needed & vct_pop) begin
                multi_fetches_needed <= 1'b0;
            end
        end
        // Maintain the FSM tracking multi-line fetches
        assign vct_request_a = (serve===VCT_ST | serve===VCT_LD) & ~Hit_a & ~vct_head_requested[0];
        assign vct_request_b = (serve===VCT_ST | serve===VCT_LD) & (vct_head_requested[0] | Hit_a) & ~vct_head_requested[1] & (multi_fetches_needed | nxt_multi_fetches_needed);
        //vct_head_requested用保存向L2发出的请求
        always_ff @(posedge clk or negedge rst_n) begin
            if(~rst_n) begin
                vct_head_requested <= '0;
            end 
            else if(vct_pop) begin
                    vct_head_requested <= '0;
            end 
            else if(vct_request_a) begin
                vct_head_requested[0] <= 1'b1;
            end 
            else if(vct_request_b) begin
                vct_head_requested <= 2'b11;
            end
        end
        vld_st_buffer 
        #(
            .DATA_WIDTH    (VECTOR_REQ_WIDTH      ),
            .ADDR_BITS     (ADDR_BITS             ),
            .BLOCK_ID_START(OFFSET_BITS           ),
            .MICROOP_WIDTH (VECTOR_MICROOP_WIDTH  ),
            .TICKET_WIDTH  ($clog2(VECTOR_LANES)+1),
            .SIZE_WIDTH    (SIZE_WIDTH            ),
            .DEPTH         (4                     )
        ) 
        vld_st_buffer 
        (
            .clk             (clk                 ),
            .rst_n           (rst_n               ),

            .push            (vct_push            ),
            .write_address   (mem_req_i.address   ),
            .write_data      (mem_req_i.data      ),
            .write_ticket    (mem_req_i.ticket    ),
            .write_size      (mem_req_i.size      ),
            .write_microop   (mem_req_i.microop   ),

            .valid_update_i  (update_l2_valid     ),
            .update_address_i(update_l2_addr      ),

            .valid_o         (vct_valid           ),
            .ready_o         (cache_vector_ready_o),
            .pop             (vct_pop             ),
            .head_is_store   (vct_head_isstore    ),
            .head_is_fetched (                    ),
            .head_address    (vct_head_addr       ),
            .head_data       (vct_head_data       ),
            .head_microop    (vct_head_microop    ),
            .head_ticket     (vct_head_ticket     ),
            .head_size       (vct_head_size       )
        );

        assign block_picked_double = {block_picked_b,block_picked};
        vdata_operation #(
            .ADDR_W   (OFFSET_BITS         ),
            .DATA_W   (VECTOR_REQ_WIDTH    ),
            .MICROOP_W(VECTOR_MICROOP_WIDTH),
            .SIZE_W   (SIZE_WIDTH          ),
            .BLOCK_W  (BLOCK_WIDTH         )
        ) vdata_operation (
            .clk          (clk                        ),
            .valid_i      (vct_pop                    ),
            //Inputs
            .input_address(offset_select              ),
            .input_block  (block_picked_double        ),
            .input_data   (vct_head_data              ),
            .microop      (vct_head_microop           ),
            .size         (vct_head_size              ),
            //Outputs
            .valid_exc    (                           ),
            .exception    (                           ),
            .output_block (vct_new_modded_block_double),
            .output_vector(vct_served_data            )
        );
        assign vct_new_modded_block = vct_new_modded_block_double[BLOCK_WIDTH-1:0];
        assign new_modded_block     = (serve === VCT_LD) | (serve === VCT_ST) ? vct_new_modded_block : scalar_new_modded_block;
        assign vector_resp_valid_o  = (multi_fetches_needed | nxt_multi_fetches_needed) ? serve===VCT_LD & Hit_a & Hit_b :
                                                                                          serve===VCT_LD & Hit_a;
        assign vector_resp.ticket   = vct_head_ticket;
        assign vector_resp.size     = vct_head_size;
        assign vector_resp.data     = vct_served_data;
    end 
    else begin
        assign new_modded_block    = scalar_new_modded_block;
        assign vct_valid           = 1'b0;
        assign vct_head_isstore    = 1'b0;
        assign vector_resp_valid_o = 1'b0;
        assign vct_request_a       = 1'b0;
        assign vct_request_b       = 1'b0;
        assign vct_head_requested  = 2'b00;
    end 
    endgenerate

endmodule
