module top_tb();

reg clk;
reg rst_n;
reg external_interrupt;
reg [450:0] inst_name;
reg [450:0] inst_list [0:50];
reg [7:0]   mem [131072:0];

integer i;
integer k;

logic [31:0] s10_x26; 
logic [31:0] s11_x27; 
logic [31:0] gp_x3;   
logic [31:0] a7_x17;  
logic [31:0] a0_x10;  
logic [31:0] x2_sp;   
logic [63:0] cycle;                            
logic [19:0] commit_instr;    
logic [19:0] branch_instr;    
logic [19:0] branch_instr_num;
logic [19:0] mispredict;      
logic        wfi1;            
logic        wfi2; 

assign s10_x26 = u_top.u_processor.debug_regfile.x26_s10_w;
assign s11_x27 = u_top.u_processor.debug_regfile.x27_s11_w;
assign gp_x3   = u_top.u_processor.debug_regfile.x3_gp_w;
assign a7_x17  = u_top.u_processor.debug_regfile.x17_a7_w;
assign a0_x10  = u_top.u_processor.debug_regfile.x10_a0_w;
assign x2_sp   = u_top.u_processor.debug_regfile.x2_sp_w;

//------------------performance test-------------------------//
assign cycle            = {u_top.u_processor.u0_execute_stage.lsu_csr.csr_ctrl.csr_reg.csr_mcycle_h_q,
                           u_top.u_processor.u0_execute_stage.lsu_csr.csr_ctrl.csr_reg.csr_mcycle_q};
assign commit_instr     = u_top.u_processor.u_rob.instr;
assign branch_instr     = u_top.u_processor.instruction_decode.branch_instr;
assign branch_instr_num = u_top.u_processor.instruction_decode.branch_instr_num;
assign mispredict       = u_top.u_processor.instruction_decode.mispredict;
assign wfi1             = u_top.u_processor.instruction_decode.u_decoder.decoder_full_a.wfi;
assign wfi2             = u_top.u_processor.instruction_decode.u_decoder.decoder_full_b.wfi;

real cpi;

real cy =cycle;
real instr=commit_instr;
initial begin  
    clk  = 1'b0;
    rst_n = 1'b0;
    #20
    rst_n = 1'b1;

    for (k = 7; k <= 7; k=k+1) begin
        inst_name = inst_list[k];
        inst_load(inst_name);
        #2000;
    end 
    
end

initial begin  
    external_interrupt = 1'b0;
/*    #3000
    external_interrupt = 1'b1;
    #40
    external_interrupt = 1'b0;
    #1000
    external_interrupt = 1'b1;
    #40
    external_interrupt = 1'b0;*/
end

always #10 clk = ~clk;

task inst_load;
    input [600:0] inst_name;
    
    begin
    for (i=0;i<131072;i=i+1)
        mem[i] = 0;
    $readmemh(inst_name, mem);

    for (i=0;i<131072;i=i+1) begin
        u_top.u_main_memory.write(i, mem[i]);
    end
    
    end

endtask

task reset;                // reset 1 clock
    begin
        rst_n = 0; 
        #20;
        rst_n = 1;
    end
endtask

integer r;
string result;
always begin
    wait(wfi1|wfi2)   
    $display("cycle is: %d", cycle); 
    $display("instr is: %d", commit_instr); 
    $display("branch_instr is: %d", branch_instr); 
    $display("branch_instr_num is: %d", branch_instr_num); 
    $display("mispredict_instr_num is: %d", mispredict); 
  //  cpi = cy/instr;

  //  $display("CPI is: %f", cpi);
    $finish;
end
initial begin
    inst_list[0]  = "../microbench/bp_test/cond.verilog"; 
    inst_list[1]  = "../microbench/bp_test/complexctrl.verilog"; 
    inst_list[2]  = "../microbench/bp_test/recur.verilog";
    inst_list[3]  = "../microbench/bp_test/switch.verilog";//problem
    inst_list[4]  = "../microbench/ex_test/depchain.verilog";
    inst_list[5]  = "../microbench/ex_test/straight.verilog";//problem
    inst_list[6]  = "../microbench/mem_test/memdep.verilog";
    inst_list[7]  = "../microbench/dhrystone.verilog";
end

initial begin
    #(1000 * 20000);
    $display("~~~~~~~~~~~~~~~~~~~ %s time_out ~~~~~~~~~~~~~~~~~~~~", inst_name); 
    $finish;
end

rv32im_vector u_top
(
    .clk                    (clk ),
    .rst_n                  (rst_n),
    .external_interrupt     (external_interrupt),
    .timer_interrupt        ()
);



initial begin 
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0,top_tb,"+all");
    $fsdbDumpMDA();
end


endmodule
