`include "../include/csr_defines.svh"
module csr 
#(
    parameter SUPPORT_MULDIV = 1,
    parameter SUPPORT_SUPER  = 0
) 
(
    input   logic                   clk                 ,
    input   logic                   rst_n               ,
    input   logic                   external_interrupt  ,//外部中断
    input   logic                   timer_interrupt     ,
   /* input   logic [31:0]            cpu_id_i            ,
    input   logic [31:0]            reset_vector_i      ,
    input   logic                   interrupt_inhibit_i ,*/

    input   logic                   valid               ,
    input   to_execution            input_data          ,
    input   writeback_toARF         writeback           ,
    input   writeback_toARF         rob_bypass          ,
    input   exception_entry         exception_i         ,
    input   csr_update              csr_update          ,

    output  ex_update               fu_update           ,
    output  logic [31:0]            csr_branch_pc       ,
    output  logic                   csr_branch             
);
    logic csrrw,csrrs,csrrc,csrrwi,csrrsi,csrrci,mret;
    logic vsetvli,vsetvl,vsetivli;
    logic is_vector_cfg;
    logic is_csr;
    logic interrupt_o;

    assign csrrw    = valid && (input_data.microoperation == 5'b11000);
    assign csrrs    = valid && (input_data.microoperation == 5'b11001);
    assign csrrc    = valid && (input_data.microoperation == 5'b11010);
    assign csrrwi   = valid && (input_data.microoperation == 5'b11011);
    assign csrrsi   = valid && (input_data.microoperation == 5'b11100);
    assign csrrci   = valid && (input_data.microoperation == 5'b11101);
    assign mret     = valid && (input_data.microoperation == 5'b11110);
//vector config
    assign vsetvli  = valid && (input_data.microoperation == 5'b10000);
    assign vsetvl   = valid && (input_data.microoperation == 5'b10001);
    assign vsetivli = valid && (input_data.microoperation == 5'b10010);
    assign is_vector_cfg = vsetvli | vsetvl  | vsetivli;


    assign is_csr   = csrrw | csrrs | csrrc | csrrwi| csrrsi | csrrci | mret | input_data.reconfigure;
    logic        csr_ren;
    logic [11:0] csr_addr;
    logic [31:0] csr_rdata;
    logic [31:0] csr_imm;
    assign csr_imm  = {27'b0,input_data.csr_imm};
    assign csr_ren  = valid & is_csr;

    assign fu_update.valid           = valid & input_data.valid;
    assign fu_update.destination     = input_data.destination;
    assign fu_update.ticket          = input_data.ticket;
    assign fu_update.data            = input_data.vl_in_source1 ? input_data.data1 : csr_rdata;
    assign fu_update.is_csr          = is_csr;
    assign fu_update.update_vl_en    = input_data.reconfigure;

    always_comb begin
        case(input_data.microoperation)
        //value of vtype
            5'b10000 : fu_update.csr_addr = input_data.csr_addr;
            5'b10001 : fu_update.csr_addr = input_data.data2;
            5'b10010 : fu_update.csr_addr = {2'b0,input_data.csr_addr[9:0]};
        //value of others CSRs
            default  : fu_update.csr_addr = input_data.csr_addr;
        endcase
    end
    always_comb begin
        if(interrupt_o) begin
            csr_branch    = 1'b1;
            case(12'h305)//是否需要Bypass?? 或者CSR初始化完成前令中断无效
                csr_update.csr_addr : csr_branch_pc = csr_update.csr_wdata;
                writeback.csr_addr  : csr_branch_pc = writeback.csr_wdata;
                rob_bypass.csr_addr : csr_branch_pc = rob_bypass.csr_wdata;
                default             : csr_branch_pc = csr_rdata;
            endcase
        end
        else if(mret) begin
            csr_branch    = 1'b1;
            case(input_data.csr_addr)
                csr_update.csr_addr : csr_branch_pc = csr_update.csr_wdata;
                writeback.csr_addr  : csr_branch_pc = writeback.csr_wdata;
                rob_bypass.csr_addr : csr_branch_pc = rob_bypass.csr_wdata;
                default             : csr_branch_pc = csr_rdata;
            endcase
        end 
        else begin
            csr_branch    = 1'b0;
            csr_branch_pc = 32'b0;
        end
    end

    always_comb begin
        case(input_data.microoperation)
            5'b11000 : fu_update.csr_wdata  = input_data.data1;
            5'b11001 : fu_update.csr_wdata  = input_data.data1 | csr_rdata;
            5'b11010 : fu_update.csr_wdata  = input_data.data1 & csr_rdata;
            5'b11011 : fu_update.csr_wdata  = csr_imm;
            5'b11100 : fu_update.csr_wdata  = input_data.data1 | csr_imm;
            5'b11101 : fu_update.csr_wdata  = input_data.data1 & csr_imm;
            5'b10000,
            5'b10001, 
            5'b10010 : fu_update.csr_wdata  = input_data.vl;
            default  : fu_update.csr_wdata  = 32'b0;
        endcase
    end 
    always_comb begin
        case(input_data.microoperation)
            5'b00010 : begin
                fu_update.valid_exception = 1'b1;
                fu_update.cause           = 4'h1;
            end
            default  : begin
                fu_update.valid_exception = 1'b0;
                fu_update.cause           = 4'h0;
            end
        endcase
    end
 
    logic [11:0] wb_csr_addr;
    assign wb_csr_addr =  writeback.update_vl_en ? 12'h020 : writeback.csr_addr;
    csr_registers  csr_reg
    (
        .clk                    (clk                ),
        .rst_n                  (rst_n              ),
        .ext_intr               (external_interrupt ),
        .timer_intr             (timer_interrupt    ),
        .interrupt_o            (interrupt_o        ),
        .update_vl_en           (writeback.update_vl_en),
        .update_vtype           (writeback.csr_addr),

        .valid_exception        (exception_i.valid_exception),
        .exception              (exception_i.exception      ),
        .exception_pc           (exception_i.exception_pc   ),
        .exception_addr         (exception_i.exception_addr ),
        .mret                   (mret),

        .read_en                (valid),
        .read_addr              (input_data.csr_addr),
        .data_out               (csr_rdata),
        // CSR register writes (WB)
        .write_en               (writeback.csr & writeback.valid_commit & ~writeback.flushed ),
        .write_addr             (wb_csr_addr),
        .write_data             (writeback.csr_wdata)
    );

endmodule