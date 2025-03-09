`include "../include/csr_defines.svh"
module csr_registers 
#(
    parameter DATA_WIDTH   = 32 ,
    parameter ADDR_WIDTH   = 12 ,
    parameter CSR_DEPTH    = 4096,
    parameter CYCLE_PERIOD = 1
) 
(
    input   logic                       clk             ,
    input   logic                       rst_n           ,
    input   logic                       ext_intr        ,    
    input   logic                       timer_intr      , 
    output  logic                       interrupt_o     ,
    input   logic                       update_vl_en    ,      
    input   logic [31:0]                update_vtype    , 

    input   logic                       valid_exception ,
    input   logic [3:0]                 exception       ,
    input   logic [31:0]                exception_pc    ,  
    input   logic [31:0]                exception_addr  ,
    input   logic                       mret            ,
    // read side
    input   logic                       read_en         ,
    input   logic [ADDR_WIDTH-1:0]      read_addr       ,
    output  logic [DATA_WIDTH-1:0]      data_out        ,
    // write side       
    input   logic                       write_en        ,
    input   logic [ADDR_WIDTH-1:0]      write_addr      ,
    input   logic [DATA_WIDTH-1:0]      write_data  
        
);
    //CSR - Machine
    logic [31:0]  csr_mtvec_q;
    logic [31:0]  csr_mcause_q;
    logic [31:0]  csr_mepc_q;
    logic [31:0]  csr_mtval_q;
    logic [31:0]  csr_mstatus_q;
    logic [31:0]  csr_mie_q;
    logic [31:0]  csr_mip_q;
    logic [31:0]  csr_mcycle_q;
    logic [31:0]  csr_mcycle_h_q;
    logic         csr_mtime_ie_q;

    logic [31:0]  csr_vstart_q;
    logic [31:0]  csr_vxsat_q;
    logic [31:0]  csr_vxrm_q;
    logic [31:0]  csr_vcsr_q;
    logic [31:0]  csr_vl_q;
    logic [31:0]  csr_vtype_q;
    logic [31:0]  csr_vlenb_q;
//-----------------------------------------------------------------
// CSR Read Port
//-----------------------------------------------------------------
    logic [31:0] rdata_r;
    always @(*) begin
        rdata_r = 32'b0;
        if(ext_intr)
            rdata_r = csr_mtvec_q;
        else begin
            case (read_addr)
            //Machine CSR 
            `CSR_MEPC:     rdata_r = csr_mepc_q;
            `CSR_MTVEC:    rdata_r = csr_mtvec_q;
            `CSR_MCAUSE:   rdata_r = csr_mcause_q;
            `CSR_MTVAL:    rdata_r = csr_mtval_q;
            `CSR_MSTATUS:  rdata_r = csr_mstatus_q;
            `CSR_MIP:      rdata_r = csr_mip_q;
            `CSR_MIE:      rdata_r = csr_mie_q;
            `CSR_MCYCLE,
            `CSR_MTIME:    rdata_r = csr_mcycle_q;
            `CSR_MTIMEH:   rdata_r = csr_mcycle_h_q;
            //Vector CSR 
            `CSR_VSTART :  rdata_r = csr_vstart_q;
            `CSR_VXSAT :   rdata_r = csr_vxsat_q;
            `CSR_VXRM :    rdata_r = csr_vxrm_q;
            `CSR_VCSR :    rdata_r = csr_vcsr_q;
            `CSR_VL :      rdata_r = csr_vl_q;
            `CSR_VTYPE :   rdata_r = csr_vtype_q;
            `CSR_VLENB :   rdata_r = csr_vlenb_q;
            default     :  rdata_r = 32'b0;
            endcase
        end
    end

    assign data_out = rdata_r;
//-----------------------------------------------------------------
// CSR register next state
//-----------------------------------------------------------------
// CSR - Machine
    logic [31:0]  csr_mepc_r;
    logic [31:0]  csr_mcause_r;
    logic [31:0]  csr_mstatus_r;
    logic [31:0]  csr_mtval_r;
    logic [31:0]  csr_mtvec_r;
    logic [31:0]  csr_mip_r;
    logic [31:0]  csr_mie_r;
    logic [31:0]  csr_mcycle_r;
    logic         csr_mtime_ie_r;

    logic [31:0]  csr_mip_next_q;
    logic [31:0]  csr_mip_next_r;
    logic [31:0]  csr_vstart_r;
    logic [31:0]  csr_vxsat_r;
    logic [31:0]  csr_vxrm_r;
    logic [31:0]  csr_vcsr_r;
    logic [31:0]  csr_vl_r;
    logic [31:0]  csr_vtype_r;
    logic [31:0]  csr_vlenb_r;

    logic [31:0]  interrupt_pending;
    logic         interrupt_signal,interrupt_last;
    assign interrupt_pending = csr_mip_q & csr_mie_q;
    assign interrupt_signal  = |interrupt_pending;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            interrupt_last <= 1'b0;
        else 
            interrupt_last <= interrupt_signal; 
    end
    assign interrupt_o = ~interrupt_last & interrupt_signal;
    always_comb begin
        // CSR - Machine
        csr_mip_next_r  = csr_mip_next_q;
        csr_mepc_r      = csr_mepc_q;
        csr_mstatus_r   = csr_mstatus_q;
        csr_mcause_r    = csr_mcause_q;
        csr_mtval_r     = csr_mtval_q;
        csr_mtvec_r     = csr_mtvec_q;
        csr_mip_r       = csr_mip_q;
        csr_mie_r       = csr_mie_q;
        csr_mcycle_r    = csr_mcycle_q + 32'd1;
        csr_mtime_ie_r  = csr_mtime_ie_q;    
        csr_mstatus_r[`SR_MPP_R] = 2'b11;//only support machine mode
        // Interrupts
        if(mret) begin
            // MRET (return from machine)
            // Interrupt enable pop
            csr_mstatus_r[`SR_MIE_R]  = csr_mstatus_r[`SR_MPIE_R];
            csr_mstatus_r[`SR_MPIE_R] = 1'b1;
        end
        // Exception return
        else if(ext_intr) begin
            //raise exteranl interrupt request
            csr_mip_r[`SR_IP_MEIP_R] = 1'b1;
            if(csr_mstatus_r[`SR_MIE_R])//ready to handle interrupt
                // Save interrupt state
                csr_mstatus_r[`SR_MPIE_R] = csr_mstatus_r[`SR_MIE_R];
                // Disable interrupts 
                csr_mstatus_r[`SR_MIE_R]  = 1'b0;
                // Record interrupt source PC
                csr_mepc_r           = exception_pc;
                //csr_mtval_r          = 32'b0;
        end

        else if (timer_intr)begin
            //raise timer interrupt request
            csr_mip_r[`SR_IP_MTIP_R] = 1'b1;
            if(csr_mstatus_r[`SR_MIE_R])//ready to handle interrupt
                // Save interrupt state
                csr_mstatus_r[`SR_MPIE_R] = csr_mstatus_r[`SR_MIE_R];
                // Disable interrupts 
                csr_mstatus_r[`SR_MIE_R]  = 1'b0;
                // Record interrupt source PC
                csr_mepc_r           = exception_pc;
        end
        // Exception - handled in machine mode
        else if(valid_exception) begin
            // Save interrupt / supervisor state
            csr_mstatus_r[`SR_MPIE_R] = csr_mstatus_r[`SR_MIE_R];
            // Disable interrupts and enter supervisor mode
            csr_mstatus_r[`SR_MIE_R]  = 1'b0;
            // Record fault source PC
            csr_mepc_r   = exception_pc;
            // Bad address / PC
            case (exception)
            `EXCEPTION_MISALIGNED_FETCH,
            `EXCEPTION_FAULT_FETCH,
            `EXCEPTION_PAGE_FAULT_INST:     csr_mtval_r = exception_pc;
            `EXCEPTION_ILLEGAL_INSTRUCTION,
            `EXCEPTION_MISALIGNED_LOAD,
            `EXCEPTION_FAULT_LOAD,
            `EXCEPTION_MISALIGNED_STORE,
            `EXCEPTION_FAULT_STORE,
            `EXCEPTION_PAGE_FAULT_LOAD,
            `EXCEPTION_PAGE_FAULT_STORE:    csr_mtval_r = exception_addr;
            default:                        csr_mtval_r = 32'b0;
            endcase        
            // Fault cause
            csr_mcause_r = {28'b0, exception[3:0]};
        end
        else if(write_en)begin
            case(write_addr)
            // CSR - Machine
            `CSR_MEPC:     csr_mepc_r     = write_data;
            `CSR_MTVEC:    csr_mtvec_r    = write_data;
            `CSR_MCAUSE:   csr_mcause_r   = write_data;
            `CSR_MTVAL:    csr_mtval_r    = write_data;
            `CSR_MSTATUS:  csr_mstatus_r  = write_data;
            `CSR_MIP:      csr_mip_r      = write_data;
            `CSR_MIE:      csr_mie_r      = write_data;
            default:;
            endcase
        end
        // External interrupts
    end
    always_comb begin
        // CSR - Machine
        csr_vstart_r    = csr_vstart_q;        
        csr_vxsat_r     = csr_vxsat_q;    
        csr_vxrm_r      = csr_vxrm_q;    
        csr_vcsr_r      = csr_vcsr_q;    
        csr_vl_r        = csr_vl_q;    
        csr_vtype_r     = csr_vtype_q;    
        csr_vlenb_r     = csr_vlenb_q; 
        if(update_vl_en) begin
            csr_vtype_r = update_vtype;
        end
        if(write_en)begin
            case(write_addr)
            // CSR - Machine
            `CSR_VSTART:   csr_vstart_r   = write_data;     
            `CSR_VXSAT:    csr_vxsat_r    = write_data;
            `CSR_VXRM:     csr_vxrm_r     = write_data;
            `CSR_VCSR:     csr_vcsr_r     = write_data;
            `CSR_VL:       csr_vl_r       = write_data;
            `CSR_VLENB:    csr_vlenb_r    = write_data;
            default:;
            endcase
        end  
    end   
//-----------------------------------------------------------------
// CSR Update
//-----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            // CSR - Machine
            csr_mepc_q         <= 32'h0;
            csr_mstatus_q      <= 32'h0000_0008;//default
            csr_mcause_q       <= 32'h0;
            csr_mtval_q        <= 32'h0;
            csr_mtvec_q        <= 32'h0;
            csr_mip_q          <= 32'h0;
            csr_mie_q          <= 32'h0000_0880;
            csr_mcycle_q       <= 32'h0;
            csr_mcycle_h_q     <= 32'h0;
            csr_mtime_ie_q     <=  1'b0;
            csr_mip_next_q     <= 32'h0;
            csr_vstart_q       <= 32'h0; 
            csr_vxsat_q        <= 32'h0;  
            csr_vxrm_q         <= 32'h0;   
            csr_vcsr_q         <= 32'h0;   
            csr_vl_q           <= 32'h0;    
            csr_vtype_q        <= 32'h0;  
            csr_vlenb_q        <= 32'h0;  
        end
        else begin
            // CSR - Machine
            csr_mepc_q         <= csr_mepc_r;
            csr_mstatus_q      <= csr_mstatus_r;
            csr_mcause_q       <= csr_mcause_r;
            csr_mtval_q        <= csr_mtval_r;
            csr_mtvec_q        <= csr_mtvec_r;
            csr_mip_q          <= csr_mip_r;
            csr_mie_q          <= csr_mie_r;
            csr_mcycle_q       <= csr_mcycle_r;
            csr_mtime_ie_q     <= csr_mtime_ie_r;
           // csr_mip_next_q     <= buffer_mip_w ? csr_mip_next_r : 32'b0;
            // Increment upper cycle counter on lower 32-bit overflow
            csr_mcycle_h_q <= (csr_mcycle_q == 32'hFFFFFFFF) ? csr_mcycle_h_q + 32'd1 : csr_mcycle_h_q;

            csr_vstart_q       <= csr_vstart_r; 
            csr_vxsat_q        <= csr_vxsat_r;  
            csr_vxrm_q         <= csr_vxrm_r;   
            csr_vcsr_q         <= csr_vcsr_r;   
            csr_vl_q           <= csr_vl_r;    
            csr_vtype_q        <= csr_vtype_r;  
            csr_vlenb_q        <= csr_vlenb_r; 
        end
    end
endmodule
