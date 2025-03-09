//--------------------------scalar---------------------------------//
//opcode: [6:2]
`define LUI             5'b01101
`define AUIPC           5'b00101
`define JAL             5'b11011
`define JALR            5'b11001
`define B_TYPE          5'b11000
`define L_TYPE          5'b00000
`define S_TYPE          5'b01000
`define I_TYPE          5'b00100
`define R_TYPE          5'b01100
`define FENCE           5'b00011
`define SYSTEM_CSR      5'b11100   


`define BEQ             3'b000
`define BNE             3'b001
`define BLT             3'b100
`define BGE             3'b101
`define BLTU            3'b110
`define BGEU            3'b111
`define LB              3'b000
`define LH              3'b001
`define LW              3'b010
`define LBU             3'b100
`define LHU             3'b101

`define SB              3'b000
`define SH              3'b001
`define SW              3'b010

`define ADDI            3'b000
`define SLLI            3'b001
`define SLTI            3'b010
`define SLTIU           3'b011
`define XORI            3'b100
`define SRLI_SRAI       3'b101
`define SRLI            7'b0000000
`define SRAI            7'b0100000
`define ORI             3'b110
`define ANDI            3'b111

`define ADD_SUB_MUL     3'b000
`define ADD             7'b0000000
`define SUB             7'b0100000 
`define MUL             7'b0000001 
`define SLL_MULH        3'b001
`define SLL             7'b0000000
`define MULH            7'b0000001
`define SLT_MULHSU      3'b010
`define SLT             7'b0000000
`define MULHSU          7'b0000001
`define SLTU_MULHU      3'b011 
`define SLTU            7'b0000000
`define MULHU           7'b0000001
`define XOR_DIV         3'b100
`define XOR             7'b0000000
`define DIV             7'b0000001
`define SRL_DIVU        3'b101
`define SRL             7'b0000000
`define SRA             7'b0100000
`define DIVU            7'b0000001
`define OR_REM          3'b110
`define OR              7'b0000000
`define REM             7'b0000001
`define AND_REMU        3'b111
`define AND             7'b0000000
`define REMU            7'b0000001

`define SYSTEM          3'b000 
`define ECALL           5'b00000
`define EBREAK          5'b00001
`define MRET            5'b00010
`define WFI             5'b00101
`define CSRRW           3'b001
`define CSRRS           3'b010
`define CSRRC           3'b011
`define CSRRWI          3'b101
`define CSRRSI          3'b110
`define CSRRCI          3'b111


//--------------------------vector---------------------------------//
`define V_CONFIG_NORMAL 5'b10101
`define V_LOAD          5'b00001
`define V_STORE         5'b01001
`define V_CONFIG        3'b111
//vector mop
`define VL              2'b00 
`define VLS             2'b10
`define VLX             2'b01
`define VLXO            2'b11
`define VS              2'b00 
`define VSS             2'b10
`define VSX             2'b01
`define VSXO            2'b11
//Vector funct3
`define OPIVV           3'b000
`define OPIVI           3'b011
`define OPIVX           3'b100
//Vector funct6
`define VADD            6'b000000
`define VSUB            6'b000010
`define VAND            6'b001001
`define VOR             6'b001010
`define VXOR            6'b001011
`define VADC            6'b010000
`define VSLL            6'b100101
`define VSRL            6'b101000
`define VSRA            6'b101001
`define VSLT            6'b011010
`define VSLTU           6'b011011
`define VMV             6'b010111

`define VADDI           6'b000000
`define VANDI           6'b001001
`define VORI            6'b001010
`define VXORI           6'b001011
`define VSLLI           6'b100101
`define VSRLI           6'b101000
`define VSRAI           6'b101001