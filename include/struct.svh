//Packet Fetched from IF
typedef struct packed {
    logic          taken_branch;
    logic [31 : 0] pc          ;
    logic [31 : 0] data        ;
} fetched_packet;

typedef struct packed {
    logic [31 : 0] pc               ;
    logic [ 5 : 0] source1          ;
    logic          source1_pc       ;
    logic [ 5 : 0] source2          ;
    logic          source2_immediate;
    logic [31 : 0] immediate        ;
    logic [ 5 : 0] destination      ;
    logic [ 1 : 0] functional_unit  ;
    logic [ 4 : 0] microoperation   ;
    logic          is_branch        ;
    logic          is_valid         ;
    logic [11 : 0] csr_addr         ;
    logic [ 4 : 0] csr_imm          ;

    logic          is_vector        ;
    logic          opivx            ;
    logic [ 2 : 0] vls_width        ;
} decoded_instr;

typedef struct packed {
    logic [31 : 0] pc               ;
    logic [ 5 : 0] source1          ;
    logic          source1_pc       ;
    logic [ 5 : 0] source2          ;
    logic          source2_immediate;
    logic [31 : 0] immediate        ;
    logic [ 5 : 0] destination      ;
    logic [ 1 : 0] functional_unit  ;
    logic [ 4 : 0] microoperation   ;
    logic [ 3 : 0] ticket           ;
    logic          rat_id           ;
    logic          is_branch        ;
    logic          is_valid         ;
    logic [1:0]    branch_id        ;
    logic [11 : 0] csr_addr         ;
    logic [ 4 : 0] csr_imm          ;
//vector
    logic [ 5 : 0] logic_source1    ;
    logic [ 5 : 0] logic_source2    ;
    logic          is_vector        ;
    logic          vl_in_source1    ;
    logic          is_vector_cfg    ;
    logic          vsetvli          ;
    logic          vsetvl           ;
    logic          vsetivli         ;
    logic          vector_need_rs1  ;
    logic          vector_need_rs2  ;    
    logic [ 2 : 0] vls_width        ;
} renamed_instr;

typedef struct packed {
    logic          valid          ;
    logic [31 : 0] pc             ;
    logic [ 5 : 0] destination    ;
    logic [31 : 0] data1          ;
    logic [31 : 0] data2          ;
    logic [31 : 0] immediate      ;
    logic [ 1 : 0] functional_unit;
    logic [ 4 : 0] microoperation ;
    logic          rat_id         ;
    logic          is_vector      ;
    logic          vl_in_source1  ;
    logic [ 5 : 0] vl             ;
    logic [ 5 : 0] vlmax          ;
    logic          reconfigure    ;
    logic          dst_iszero     ;
    logic [ 2 : 0] ticket         ;
    logic [1:0]    branch_id      ;
    logic [11 : 0] csr_addr       ;
    logic [ 4 : 0] csr_imm        ;
}to_execution;

typedef struct packed {
    logic          valid          ;

    logic [ 4 : 0] dst            ;
    logic [ 4 : 0] src1           ;
    logic [ 4 : 0] src2           ;

    logic [31 : 0] data1          ;
    logic [31 : 0] data2          ;
    logic [31 : 0] immediate      ;

    logic          reconfigure    ;
    logic [ 1 : 0] fu             ;//0:valu 1:vmu
    logic [ 4 : 0] microop        ;

    logic [ 5 : 0] vl             ;
    logic [ 5 : 0] maxvl          ;
    logic [ 2 : 0] vls_width      ;
}to_vector;

typedef struct packed {
    logic          valid          ;

    logic [ 4 : 0] dst            ;
    logic          dst_iszero     ;
    logic [ 4 : 0] src1           ;
    logic          src1_iszero    ;
    logic [ 4 : 0] src2           ;
    logic          src2_iszero    ;    

    logic [31 : 0] data1          ;
    logic [31 : 0] data2          ;
    logic [31 : 0] immediate      ;

    logic          reconfigure    ;
    logic [ 4 : 0] ticket         ;
    logic [ 1 : 0] fu             ;//0:valu 1:vmu
    logic [ 4 : 0] microop        ;
    logic          is_store       ; 
    logic [ 1:  0] lock           ;
    logic [ 5 : 0] vl             ;
    logic [ 5 : 0] maxvl          ;
}to_vis;

typedef struct packed {
    logic          valid          ;

    logic [ 4 : 0] dst            ;
    logic [ 4 : 0] src1           ;
    logic [ 4 : 0] src2           ;

    logic [31 : 0] data1          ;
    logic [31 : 0] data2          ;
    logic [31 : 0] immediate      ;

    logic          reconfigure    ;
    logic [ 4 : 0] ticket         ;
    logic [ 4 : 0] last_ticket_src1;
    logic [ 4 : 0] last_ticket_src2;
    logic [ 4 : 0] microop        ;

    logic [ 5 : 0] vl             ;
    logic [ 5 : 0] maxvl          ;
    logic [ 2 : 0] vls_width      ;
}to_vmu;

//Struct from EX stage to update internal ROB status
typedef struct packed {
    logic          valid          ;
    logic [ 5 : 0] destination    ;
    logic [ 2 : 0] ticket         ;
    logic [31 : 0] data           ;
    logic          valid_exception;
    logic [ 3 : 0] cause          ;
    logic          is_csr         ;
    logic [11 : 0] csr_addr       ;
    logic [31 : 0] csr_wdata      ;
    logic          update_vl_en   ;
} ex_update;

typedef struct packed {
    logic          is_csr         ;
    logic [11 : 0] csr_addr       ;
    logic [31 : 0] csr_wdata      ;
} csr_update;

typedef struct packed {
    logic          valid_jump  ;
    logic          csr_branch  ;
    logic          jump_taken  ;
    logic          is_comp     ;
    logic          rat_id      ;
    logic [31 : 0] orig_pc     ;
    logic [31 : 0] jump_address;
    logic [2 : 0]  ticket      ;
    logic [1:0]    branch_id   ;
} predictor_update;

//Internal ROB configuration (per entry)
typedef struct packed {
    logic          valid          ;
    logic          pending        ;
    logic          flushed        ;
    logic          valid_dest     ;
    logic [ 5 : 0] lreg           ;
    logic [ 5 : 0] preg           ;
    logic [ 5 : 0] ppreg          ;
    logic [ 4 : 0] microoperation ;
    logic          valid_exception;//Clear reorder buffer on exception
    logic [ 3 : 0] cause          ;//redirect depending on cause
    logic          is_store       ;
    logic [31 : 0] address        ;
    logic [31 : 0] pc             ;
    logic [11 : 0] csr_addr       ;
    logic [31 : 0] csr_wdata      ;
    logic          update_vl_en   ;
    logic          csr;
} rob_entry;
//---------------------------------------------------------------------------------------
//Struct towards Issue stage
typedef struct packed {
    logic         is_full  ;
    logic         two_empty;
    logic [2 : 0] ticket   ;
} to_issue;

//---------------------------------------------------------------------------------------
//Struct from IS stage to request new entries(2x max per cycle)
typedef struct packed {
    logic         valid_request_1 ;
    logic         valid_dest_1    ;
    logic         csr_store_pending_1 ;
    logic [5 : 0] lreg_1          ;
    logic [5 : 0] preg_1          ;
    logic [5 : 0] ppreg_1         ;
    logic [4 : 0] microoperation_1;
    logic [31: 0] pc_1            ;
    logic         csr_1           ;
    //logic [11: 0] csr_addr_1      ;

    logic         valid_request_2 ;
    logic         valid_dest_2    ;
    logic         csr_store_pending_2 ;
    logic [5 : 0] lreg_2          ;
    logic [5 : 0] preg_2          ;
    logic [5 : 0] ppreg_2         ;
    logic [4 : 0] microoperation_2;
    logic [31: 0] pc_2            ;
    logic         csr_2           ;
    //logic [11: 0] csr_addr_2      ;
} new_entries;

//---------------------------------------------------------------------------------------
//Struct to Update the Architectural Register File
typedef struct packed {
    logic          valid_commit;
    logic          valid_write ;
    logic          flushed     ;
    logic [ 5 : 0] ldst        ;
    logic [ 5 : 0] pdst        ;
    logic [ 5 : 0] ppdst       ;
    logic [31 : 0] data        ;
    logic [ 2 : 0] ticket      ;
    logic [31 : 0] pc          ;
    logic [11 : 0] csr_addr    ;
    logic [31 : 0] csr_wdata   ;
    logic          update_vl_en;
    logic          csr         ;
    logic          valid_exception;//Clear reorder buffer on exception
    logic [ 3 : 0] cause          ;//redirect depending on cause
    logic [31 : 0] address        ;
} writeback_toARF;

typedef struct packed {
    logic         pending;
    logic [1 : 0] fu     ;
    logic [2 : 0] ticket ;
    logic         in_rob ;
}scoreboard_entry;

//---------------------------------------------------------------------------------------
//Struct from IS stage to request new entries(2x max per cycle)
typedef struct packed {
    logic         valid_exception;
    logic [3:0]   exception      ;
    logic [31:0]  exception_addr ;
    logic [31:0]  exception_pc   ;
} exception_entry;

//vector
typedef struct packed {
    logic        valid    ;
    logic        mask     ;

    logic [31:0] data1    ;
    logic [31:0] data2    ;
    logic [31:0] immediate;
}to_vector_exec;

localparam DUMMY_VECTOR_LANES   = 8;
localparam DUMMY_REQ_DATA_WIDTH = 256;
typedef struct packed {
    logic [                            4:0] dst     ;
    logic [                            3:0] ticket  ;
    logic [                            1:0] fu      ;
    logic [                            4:0] microop ;
    logic [$clog2(32*DUMMY_VECTOR_LANES):0] vl      ;
    logic                                   head_uop;
    logic                                   end_uop ;
}to_vector_exec_info;

typedef struct packed {
    logic [                            31:0]   address;
    logic [                             6:0]   microop;
    logic [$clog2(DUMMY_REQ_DATA_WIDTH/8):0]   size   ;
    logic [        DUMMY_REQ_DATA_WIDTH-1:0]   data   ;
    logic [    $clog2(DUMMY_VECTOR_LANES):0]   ticket ; //$clog2(VECTOR_LANES)
}vector_mem_req;
//--------------------------------------
//Vector memory response
typedef struct packed {
    logic [    $clog2(DUMMY_VECTOR_LANES):0]   ticket; //$clog2(VECTOR_LANES)
    logic [$clog2(DUMMY_REQ_DATA_WIDTH/8):0]   size  ; //$clog2(REQ_DATA_WIDTH/8)
    logic [        DUMMY_REQ_DATA_WIDTH-1:0]   data  ; //REQ_DATA_WIDTH
}vector_mem_resp;