`include "../include/defines.svh"
//`include "../include/enum.svh"
module decoder_full 
#(
    parameter DATA_WIDTH = 32 
)
(
    input   logic            valid          ,//decoder enable
    input   logic [31:0]     PC_in          ,
    input   logic [31:0]     instruction_in ,//instruction

    output  decoded_instr    outputs        ,
    output  logic            valid_branch   ,//valid branch instr
    output  logic            is_jumpl       ,
    output  logic            is_return      
);
    parameter V_IMM_EXTEND_BIT = DATA_WIDTH - 5;
    // #Internal Signals#
    logic [11:0]    immediate_i,immediate_s,immediate_sb;
    logic [19:0]    immediate_u,immediate_uj;
    logic           valid_map,is_branch;
    logic [4:0]     opcode,source1,source2,destination,shamt;
    logic [2:0]     funct3;
    logic [6:0]     funct7;
    logic [1:0]     mop;
    detected_instr  detected_instr;
    
    logic  wfi;
    assign valid_branch     = is_branch & valid;
    assign outputs.pc       = PC_in;
    assign outputs.is_valid = valid_map & valid;
    //Grab Fields from the Instruction
    assign opcode           = instruction_in[ 6: 2];
    assign source1          = instruction_in[19:15];
    assign source2          = instruction_in[24:20];
    assign destination      = instruction_in[11: 7];
    assign shamt            = instruction_in[24:20];
    assign funct3           = instruction_in[14:12];
    assign funct7           = instruction_in[31:25];
    assign outputs.csr_addr = (outputs.microoperation == 5'b11110) ? 12'h341 : instruction_in[31:20];
    assign outputs.csr_imm  = instruction_in[19:15];
    //imm generate
    assign immediate_i  = instruction_in[31:20];
    assign immediate_s  = {instruction_in[31:25],instruction_in[11:7]};
    assign immediate_sb = {instruction_in[31],instruction_in[7],instruction_in[30:25],instruction_in[11:8]};
    assign immediate_u  = instruction_in[31:12];
    assign immediate_uj = {instruction_in[31],instruction_in[19:12],instruction_in[20],instruction_in[30:21]};

    assign is_jumpl  = ((opcode==5'b11001) & (destination==1)) | (opcode==5'b11011) & (destination==1);
    assign is_return = (opcode==5'b11001) & (destination==0) & (source1==1);
    assign outputs.is_branch = is_branch;
    //vector load store
    assign mop       = instruction_in[27:26];
    assign outputs.vls_width = instruction_in[14:12];
    always_comb begin 
        valid_map                 = 1'b0;
        outputs.is_vector         = 1'b0;
        outputs.source1           = 'b0;
        outputs.source1_pc        = 'b0;
        outputs.source2           = 'b0;
        outputs.source2_immediate = 'b0;
        outputs.destination       = 'b0;
        outputs.immediate         = 'b0;
        outputs.functional_unit   = 'b0;
        outputs.microoperation    = 'b0;
        outputs.opivx             = 'b0;
        is_branch                 = 1'b0;
        wfi                       = 'b0;
        unique case (opcode)
            //LOAD ->
            `L_TYPE : begin
                unique case (funct3)
                    `LB : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00100;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = LB;
                    end
                    `LH : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00010;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = LH;
                    end
                    `LW : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00001;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = LW;
                    end
                    `LBU : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00101;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = LBU;
                    end
                    `LHU : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00011;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = LHU;
                    end
                    default : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 'b0;
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 'b0;
                        outputs.destination       = 'b0;
                        outputs.immediate         = 'b0;
                        outputs.functional_unit   = 'b0;
                        outputs.microoperation    = 'b0;
                        valid_map                 = 1'b0;
                        outputs.is_vector         = 1'b0;
                        is_branch                 = 1'b0;
                        detected_instr            = IDLE;
                    end
                endcase
            end
            //OP-IMM ->
            `I_TYPE : begin
                unique case (funct3)
                    `ADDI : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};        //sign extend
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b10;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00000;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = ADDI;
                    end
                    `SLLI : begin 
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{27{1'b0}},shamt};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00111;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = SLLI;
                    end
                    `SLTI : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};        //sign extend
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00010;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = SLTI;
                    end
                    `SLTIU : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};        //sign extend
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00011;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = SLTIU;
                    end
                    `XORI : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};    //sign extend
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b10;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b01100;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = XORI;
                    end
                    `SRLI_SRAI : begin
                        unique case (funct7)
                            `SRLI : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{27{1'b0}},shamt};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b11;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01000;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = SRLI;
                            end
                            `SRAI : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{27{1'b0}},shamt};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b11;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = SRAI;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `ORI : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};    //sign extend
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b10;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b01011;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = ORI;
                    end
                    `ANDI : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};    //sign extend
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b1;
                        outputs.functional_unit   = 2'b10;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b01010;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = ANDI;
                    end
                    default : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 'b0;
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 'b0;
                        outputs.destination       = 'b0;
                        outputs.immediate         = 'b0;
                        outputs.functional_unit   = 'b0;
                        outputs.microoperation    = 'b0;
                        valid_map                 = 1'b0;
                        outputs.is_vector         = 1'b0;
                        is_branch                 = 1'b0;
                        detected_instr            = IDLE;
                    end
                endcase
            end
            `AUIPC : begin
                outputs.source1           = 'b0;
                outputs.source1_pc        = 1'b1;
                outputs.immediate         = {immediate_u,{12{1'b0}}};
                outputs.source2           = 'b0;
                outputs.source2_immediate = 1'b1;
                outputs.functional_unit   = 2'b10;
                is_branch                 = 1'b0;
                outputs.microoperation    = 5'b00000;
                outputs.destination       = {1'b0,destination};
                valid_map                 = 1'b1;
                outputs.is_vector         = 1'b0;
                detected_instr            = AUIPC;
            end
            //STORE ->
            `S_TYPE : begin
                unique case (funct3)
                    `SB : begin
                        
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_s[11]}},immediate_s};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b01000;
                        outputs.destination       = 'b0;//设置为1，使ROB pending 可以拉高
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = SB;
                    end
                    `SH : begin
                        
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_s[11]}},immediate_s};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00111;
                        outputs.destination       = 'b0;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = SH;
                    end
                    `SW : begin
                        
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_s[11]}},immediate_s};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00110;
                        outputs.destination       = 'b0;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = SW;
                    end
                    default : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 'b0;
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 'b0;
                        outputs.destination       = 'b0;
                        outputs.immediate         = 'b0;
                        outputs.functional_unit   = 'b0;
                        outputs.microoperation    = 'b0;
                        valid_map                 = 1'b0;
                        outputs.is_vector         = 1'b0;
                        is_branch                 = 1'b0;
                        detected_instr            = IDLE;
                    end
                endcase
            end
            `R_TYPE : begin
                unique case (funct3)
                    `ADD_SUB_MUL : begin
                        unique case (funct7)
                            `ADD : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00000;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = ADD;
                            end
                            `SUB : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = SUB;
                            end
                            `MUL : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00010;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = MUL;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `SLL_MULH : begin
                        unique case (funct7)
                            `SLL : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b11;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00100;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = SLL;
                            end
                            `MULH : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00011;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = MULH;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `SLT_MULHSU : begin
                        unique case (funct7)
                            `SLT : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b11;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00000;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = SLT;
                            end
                            `MULHSU : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00101;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = MULHSU;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `SLTU_MULHU : begin
                        unique case (funct7)
                            `SLTU : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b11;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = SLTU;
                            end
                            `MULHU : begin 
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00100;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = MULHU;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `XOR_DIV : begin
                        unique case (funct7)
                            `XOR : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01100;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = XOR;
                            end
                            `DIV : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00110;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = DIV;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `SRL_DIVU : begin
                        unique case (funct7)
                            `SRL : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b11;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00101;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = SRL;
                            end
                            `SRA : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b11;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00110;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = SRA;
                            end
                            `DIVU : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00111;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = DIVU;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `OR_REM : begin
                        unique case (funct7)
                            `OR : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01011;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = OR;
                            end
                            `REM : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01000;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = REM;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `AND_REMU : begin
                        unique case (funct7)
                            `AND : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01010;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = AND;
                            end
                            `REMU : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = REMU;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    default : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 'b0;
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 'b0;
                        outputs.destination       = 'b0;
                        outputs.immediate         = 'b0;
                        outputs.functional_unit   = 'b0;
                        outputs.microoperation    = 'b0;
                        valid_map                 = 1'b0;
                        outputs.is_vector         = 1'b0;
                        is_branch                 = 1'b0;
                        detected_instr            = IDLE;
                    end
                endcase
            end   
            `LUI : begin
                outputs.source1           = 'b0;
                outputs.source1_pc        = 1'b0;
                outputs.immediate         = {immediate_u,{12{1'b0}}};
                outputs.source2           = 'b0;
                outputs.source2_immediate = 1'b1;
                outputs.functional_unit   = 2'b10;
                is_branch                 = 1'b0;
                outputs.microoperation    = 5'b00000;
                outputs.destination       = {1'b0,destination};
                valid_map                 = 1'b1;
                outputs.is_vector         = 1'b0;
                detected_instr            = LUI;
            end
            `B_TYPE : begin
                unique case (funct3)
                    `BEQ : begin//
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{19{immediate_sb[11]}},immediate_sb,1'b0};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b1;
                        outputs.microoperation    = 5'b01100;
                        outputs.destination       = 'b0;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = BEQ;
                    end
                    `BNE : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{19{immediate_sb[11]}},immediate_sb,1'b0};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b1;
                        outputs.microoperation    = 5'b01101;
                        outputs.destination       = 'b0;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = BNE;
                    end
                    `BLT : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{19{immediate_sb[11]}},immediate_sb,1'b0};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b1;
                        outputs.microoperation    = 5'b01110;
                        outputs.destination       = 'b0;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = BLT;
                    end
                    `BGE : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{19{immediate_sb[11]}},immediate_sb,1'b0};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b1;
                        outputs.microoperation    = 5'b10000;
                        outputs.destination       = 'b0;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = BGE;
                    end
                    `BLTU : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{19{immediate_sb[11]}},immediate_sb,1'b0};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b1;
                        outputs.microoperation    = 5'b01111;
                        outputs.destination       = 'b0;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = BLTU;
                    end
                    `BGEU : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{19{immediate_sb[11]}},immediate_sb,1'b0};
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b11;
                        is_branch                 = 1'b1;
                        outputs.microoperation    = 5'b10001;
                        outputs.destination       = 'b0;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = BGEU;
                    end
                    default : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 'b0;
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 'b0;
                        outputs.destination       = 'b0;
                        outputs.immediate         = 'b0;
                        outputs.functional_unit   = 'b0;
                        outputs.microoperation    = 'b0;
                        valid_map                 = 1'b0;
                        outputs.is_vector         = 1'b0;
                        is_branch                 = 1'b0;
                        detected_instr            = IDLE;
                    end
                endcase
            end
            `JALR : begin
                outputs.source1           = {1'b0,source1};
                outputs.source1_pc        = 1'b0;
                outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                outputs.source2           = 'b0;
                outputs.source2_immediate = 1'b1;
                outputs.functional_unit   = 2'b11;
                is_branch                 = 1'b1;
                outputs.microoperation    = 5'b01011;
                outputs.destination       = {1'b0,destination};
                valid_map                 = 1'b1;
                outputs.is_vector         = 1'b0;
                detected_instr            = JALR;
            end
            `JAL : begin
                outputs.source1           = 'b0;
                outputs.source1_pc        = 1'b1;
                outputs.immediate         = {{11{immediate_uj[18]}},immediate_uj,1'b0};
                outputs.source2           = 'b0;
                outputs.source2_immediate = 1'b1;
                outputs.functional_unit   = 2'b11;
                is_branch                 = 1'b1;
                outputs.microoperation    = 5'b01010;
                outputs.destination       = {1'b0,destination};
                valid_map                 = 1'b1;
                outputs.is_vector         = 1'b0;
                detected_instr            = JAL;
            end
            `SYSTEM_CSR : begin
                unique case (funct3)
                    `SYSTEM : begin
                        unique case (source2)
                            `ECALL : begin
                                outputs.source1           = 32'b0;
                                outputs.source1_pc        = 1'b1;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00010;
                                outputs.destination       = 32'b0;
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = ECALL;
                            end
                            `EBREAK : begin
                                outputs.source1           = 32'b0;
                                outputs.source1_pc        = 1'b1;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = 32'b0;
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = EBREAK;
                            end
                            `MRET : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b1;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b01;
                                is_branch                 = 1'b1;
                                outputs.microoperation    = 5'b11110;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b0;
                                detected_instr            = MRET;
                            end
                            `WFI : begin
                                wfi = 1'b1;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase
                    end
                    `CSRRW : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b01;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b11000;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = CSRRW;
                    end
                    `CSRRS : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b01;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b11001;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        detected_instr            = CSRRS;
                    end
                    `CSRRC : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b01;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b11010;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = CSRRC;
                    end
                    `CSRRWI : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b01;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b11011;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = CSRRWI;
                    end
                    `CSRRSI : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b01;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b11100;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = CSRRSI;
                    end
                    `CSRRCI : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = {{20{immediate_i[11]}},immediate_i};
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b01;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b11101;
                        outputs.destination       = {1'b0,destination};
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b0;
                        detected_instr            = CSRRCI;
                    end
                    default : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 'b0;
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 'b0;
                        outputs.destination       = 'b0;
                        outputs.immediate         = 'b0;
                        outputs.functional_unit   = 'b0;
                        outputs.microoperation    = 'b0;
                        valid_map                 = 1'b0;
                        outputs.is_vector         = 1'b0;
                        is_branch                 = 1'b0;
                        detected_instr            = IDLE;
                    end
                endcase
            end
            `FENCE : begin
                outputs.source1           = 32'b0;
                outputs.source1_pc        = 1'b1;
                outputs.immediate         = 32'b0;
                outputs.source2           = 'b0;
                outputs.source2_immediate = 1'b0;
                outputs.functional_unit   = 2'b10;
                is_branch                 = 1'b0;
                outputs.microoperation    = 5'b00011;
                outputs.destination       = 32'b0;
                valid_map                 = 1'b1;
                outputs.is_vector         = 1'b0;
                detected_instr            = FENCE;
            end
            //vector instruction
            `V_LOAD : begin
                unique case (mop)
                    `VL : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = 32'b0;
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00000;
                        outputs.destination       = {1'b0,destination};;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b1;
                        detected_instr            = V_LOAD_UNIT_STRIDE;
                    end 
                    `VLS : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = 32'b0;
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00001;
                        outputs.destination       = {1'b0,destination};;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b1;
                        detected_instr            = V_LOAD_STRIDE;
                    end
                    `VLX : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = 32'b0;
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00010;
                        outputs.destination       = {1'b0,destination};;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b1;
                        detected_instr            = V_LOAD_INDEX;
                    end
                    `VLXO : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = 32'b0;
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00011;
                        outputs.destination       = {1'b0,destination};;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b1;
                        detected_instr            = V_LOAD_INDEX_ORDER;
                    end
                endcase
            end
            `V_STORE : begin
                unique case (mop)
                    `VS : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = 32'b0;
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00100;
                        outputs.destination       = {1'b0,destination};;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b1;
                        detected_instr            = V_STORE_UNIT_STRIDE;
                    end 
                    `VSS : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = 32'b0;
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00101;
                        outputs.destination       = {1'b0,destination};;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b1;
                        detected_instr            = V_STORE_STRIDE;
                    end
                    `VSX : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = 32'b0;
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00110;
                        outputs.destination       = {1'b0,destination};;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b1;
                        detected_instr            = V_STORE_INDEX;
                    end
                    `VSXO : begin
                        outputs.source1           = {1'b0,source1};
                        outputs.source1_pc        = 1'b0;
                        outputs.immediate         = 32'b0;
                        outputs.source2           = {1'b0,source2};
                        outputs.source2_immediate = 1'b0;
                        outputs.functional_unit   = 2'b00;
                        is_branch                 = 1'b0;
                        outputs.microoperation    = 5'b00111;
                        outputs.destination       = {1'b0,destination};;
                        valid_map                 = 1'b1;
                        outputs.is_vector         = 1'b1;
                        detected_instr            = V_STORE_INDEX_ORDER;
                    end
                endcase
            end
            `V_CONFIG_NORMAL : begin
                unique case (funct3)
                    `OPIVV: begin
                        unique case (funct7[6:1])//funct6
                            `VADD : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVADD;
                            end
                            `VSUB : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00010;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVSUB;
                            end
                            `VAND : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00011;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVAND;
                            end
                            `VOR : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00100;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVOR;
                            end
                            `VXOR : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00101;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVXOR;
                            end
                            `VSLL : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00110;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVSLL;
                            end
                            `VSRL : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00111;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVSRL;
                            end
                            `VSRA : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01000;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVSRA;
                            end
                            `VSLT : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVSLT;
                            end
                            `VSLTU : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b01010;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVVSLTU;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase      
                    end
                    `OPIVI: begin
                        unique case (funct7[6:1])//funct6
                            `VADDI : begin
                                outputs.source1           = {1'b0,source2};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{V_IMM_EXTEND_BIT{source1[4]}},source1};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b10001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVIADD;
                            end
                            `VANDI : begin
                                outputs.source1           = {1'b0,source2};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{V_IMM_EXTEND_BIT{source1[4]}},source1};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b10011;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVIAND;
                            end
                            `VORI : begin
                                outputs.source1           = {1'b0,source2};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{V_IMM_EXTEND_BIT{source1[4]}},source1};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b10100;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVIAND;
                            end
                            `VXORI : begin
                                outputs.source1           = {1'b0,source2};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{V_IMM_EXTEND_BIT{source1[4]}},source1};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b10101;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVIXOR;
                            end
                            /*`VADC : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVIADC;
                            end*/
                            `VSLLI : begin
                                outputs.source1           = {1'b0,source2};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{V_IMM_EXTEND_BIT{source1[4]}},source1};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b10110;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVISLL;
                            end
                            `VSRLI : begin
                                outputs.source1           = {1'b0,source2};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{V_IMM_EXTEND_BIT{source1[4]}},source1};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b10111;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVISRL;
                            end
                            `VSRAI : begin
                                outputs.source1           = {1'b0,source2};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = {{V_IMM_EXTEND_BIT{source1[4]}},source1};
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b11000;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVISRA;
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase      
                    end
                    `OPIVX: begin
                        outputs.opivx = 1'b1;
                        unique case (funct7[6:1])//funct6
                            `VADD : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00000;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXADD;
                            end
                            `VSUB : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXSUB;
                            end
                            `VAND : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXAND;
                            end
                            `VOR : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXOR;
                            end
                            `VXOR : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXXOR;
                            end
                            `VADC : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXADC;
                            end
                            `VSLL : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXSLL;
                            end
                            `VSRL : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXSRL;
                            end
                            `VSRA : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXSRA;
                            end
                            `VMV : begin
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 1'b0;
                                outputs.immediate         = 32'b0;
                                outputs.source2           = {1'b0,source2};
                                outputs.source2_immediate = 1'b0;
                                outputs.functional_unit   = 2'b10;
                                is_branch                 = 1'b0;
                                outputs.microoperation    = 5'b00001;
                                outputs.destination       = {1'b0,destination};
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                detected_instr            = IVXVMV;
                            end 
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end
                        endcase      
                    end
                    `V_CONFIG: begin//config指令在译码时当作CSR
                        case(instruction_in[31]) 
                            1'b0 : begin//VSETVLI
                                outputs.source1           = {1'b0,source1};
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 1'b1;
                                outputs.destination       = {1'b0,destination};
                                outputs.immediate         = {20'b0,immediate_i};;
                                outputs.functional_unit   = 2'b01;
                                outputs.microoperation    = 5'b10000;
                                valid_map                 = 1'b1;
                                outputs.is_vector         = 1'b1;
                                is_branch                 = 1'b0;
                                detected_instr            = VSETVLI;  
                            end
                            1'b1 : begin
                                case(instruction_in[30]) 
                                    1'b0 : begin//VSETVL
                                        outputs.source1           = {1'b0,source1};
                                        outputs.source1_pc        = 'b0;
                                        outputs.source2           = {1'b0,source2};
                                        outputs.source2_immediate = 'b0;
                                        outputs.destination       = {1'b0,destination};
                                        outputs.immediate         = 'b0;
                                        outputs.functional_unit   = 2'b01;
                                        outputs.microoperation    = 5'b10001;
                                        valid_map                 = 1'b1;
                                        outputs.is_vector         = 1'b1;
                                        is_branch                 = 1'b0;
                                        detected_instr            = VSETVL; 
                                    end
                                    1'b1 :begin//VSETIVLI
                                        outputs.source1           = 'b0;
                                        outputs.source1_pc        = 'b0;
                                        outputs.source2           = 'b0;
                                        outputs.source2_immediate = 1'b1;
                                        outputs.destination       = {1'b0,destination};
                                        outputs.immediate         = {27'b0,source1};
                                        outputs.functional_unit   = 2'b01;
                                        outputs.microoperation    = 5'b10010;
                                        valid_map                 = 1'b1;
                                        outputs.is_vector         = 1'b1;
                                        is_branch                 = 1'b0;
                                        detected_instr            = VSETIVLI; 
                                    end
                                endcase
                            end
                            default : begin
                                outputs.source1           = 'b0;
                                outputs.source1_pc        = 'b0;
                                outputs.source2           = 'b0;
                                outputs.source2_immediate = 'b0;
                                outputs.destination       = 'b0;
                                outputs.immediate         = 'b0;
                                outputs.functional_unit   = 'b0;
                                outputs.microoperation    = 'b0;
                                valid_map                 = 1'b0;
                                outputs.is_vector         = 1'b0;
                                is_branch                 = 1'b0;
                                detected_instr            = IDLE;
                            end   
                        endcase
                    end
                    default : begin
                        outputs.source1           = 'b0;
                        outputs.source1_pc        = 'b0;
                        outputs.source2           = 'b0;
                        outputs.source2_immediate = 'b0;
                        outputs.destination       = 'b0;
                        outputs.immediate         = 'b0;
                        outputs.functional_unit   = 'b0;
                        outputs.microoperation    = 'b0;
                        valid_map                 = 1'b0;
                        outputs.is_vector         = 1'b0;
                        is_branch                 = 1'b0;
                        detected_instr            = IDLE;
                    end
                endcase
            end
            default : begin
                outputs.source1           = 'b0;
                outputs.source1_pc        = 'b0;
                outputs.source2           = 'b0;
                outputs.source2_immediate = 'b0;
                outputs.destination       = 'b0;
                outputs.immediate         = 'b0;
                outputs.functional_unit   = 'b0;
                outputs.microoperation    = 'b0;
                valid_map                 = 1'b0;
                outputs.is_vector         = 1'b0;
                is_branch                 = 1'b0;
                detected_instr            = IDLE;
            end
        endcase
    end

endmodule