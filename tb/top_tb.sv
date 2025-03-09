module top_tb();

reg clk;
reg rst_n;
reg external_interrupt;
reg [450:0] inst_name;
reg [450:0] inst_list [0:50];
reg [7:0]   mem [131072:0];

integer i;
integer k;

wire [31:0] s10_x26 = u_top.u_processor.debug_regfile.x26_s10_w;
wire [31:0] s11_x27 = u_top.u_processor.debug_regfile.x27_s11_w;
wire [31:0] gp_x3   = u_top.u_processor.debug_regfile.x3_gp_w;
wire [31:0] a7_x17  = u_top.u_processor.debug_regfile.x17_a7_w;
wire [31:0] a0_x10  = u_top.u_processor.debug_regfile.x10_a0_w;


initial begin  
    clk  = 1'b0;
    rst_n = 1'b0;
    #20
    rst_n = 1'b1;
    for (k = 0; k <= 44; k=k+1) begin
        inst_name = inst_list[k];
        inst_load(inst_name);
        #2000;
    end 
    $finish;
end

initial begin  
    external_interrupt = 1'b0;
    #3000
    external_interrupt = 1'b0;
    #40
    external_interrupt = 1'b0;
    #1000
    external_interrupt = 1'b0;
    #40
    external_interrupt = 1'b0;
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
    
    wait(a7_x17 == 32'h5d);
    #1000;
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
always begin
    wait(a7_x17 == 32'h5d)   
        #100
        if (a0_x10 == 32'h0) begin
            $display("~~~~~~~~~~~~~~~~~~~ %s PASS ~~~~~~~~~~~~~~~~~~~",inst_name);
            reset;
        end 
        else begin
            $display("~~~~~~~~~~~~~~~~~~~ %s FAIL ~~~~~~~~~~~~~~~~~~~~",inst_name);
            $display("fail testnum = %2d", a0_x10);
            $finish;
            //for (r = 0; r < 32; r = r + 1)
            //    $display("x%2d = 0x%x", r, rv32i_min_sopc_inst0. rv32i_inst0. regfile_inst0.regs[r]);
        end
end
initial begin
    inst_list[0]  = "../isa/generated/rv32ui-p-add.verilog";   inst_list[1]  = "../isa/generated/rv32ui-p-sub.verilog";  inst_list[2]  = "../isa/generated/rv32ui-p-xor.verilog";
    inst_list[3]  = "../isa/generated/rv32ui-p-or.verilog";    inst_list[4]  = "../isa/generated/rv32ui-p-and.verilog";  inst_list[5]  = "../isa/generated/rv32ui-p-add.verilog";
    inst_list[6]  = "../isa/generated/rv32ui-p-srl.verilog";   inst_list[7]  = "../isa/generated/rv32ui-p-sra.verilog";  inst_list[8]  = "../isa/generated/rv32ui-p-slt.verilog";
    inst_list[9]  = "../isa/generated/rv32ui-p-sltu.verilog";  inst_list[10] = "../isa/generated/rv32ui-p-addi.verilog"; inst_list[11] = "../isa/generated/rv32ui-p-xori.verilog";
    inst_list[12] = "../isa/generated/rv32ui-p-ori.verilog";   inst_list[13] = "../isa/generated/rv32ui-p-andi.verilog"; inst_list[14] = "../isa/generated/rv32ui-p-slli.verilog";
    inst_list[15] = "../isa/generated/rv32ui-p-srli.verilog";  inst_list[16] = "../isa/generated/rv32ui-p-srai.verilog"; inst_list[17] = "../isa/generated/rv32ui-p-slti.verilog";
    inst_list[18] = "../isa/generated/rv32ui-p-sltiu.verilog"; inst_list[19] = "../isa/generated/rv32ui-p-beq.verilog";  inst_list[20] = "../isa/generated/rv32ui-p-bne.verilog";  
    inst_list[21] = "../isa/generated/rv32ui-p-blt.verilog";   inst_list[22] = "../isa/generated/rv32ui-p-bge.verilog";  inst_list[23] = "../isa/generated/rv32ui-p-bltu.verilog"; 
    inst_list[24] = "../isa/generated/rv32ui-p-bgeu.verilog";  inst_list[25] = "../isa/generated/rv32ui-p-jal.verilog";  inst_list[26] = "../isa/generated/rv32ui-p-jalr.verilog"; 
    inst_list[27] = "../isa/generated/rv32ui-p-lui.verilog";   inst_list[28] = "../isa/generated/rv32ui-p-auipc.verilog";inst_list[29] = "../isa/generated/rv32ui-p-sb.verilog";   
    inst_list[30] = "../isa/generated/rv32ui-p-sh.verilog";    inst_list[31] = "../isa/generated/rv32ui-p-sw.verilog";   inst_list[32] = "../isa/generated/rv32ui-p-lb.verilog";  
    inst_list[33] = "../isa/generated/rv32ui-p-lh.verilog";    inst_list[34] = "../isa/generated/rv32ui-p-lw.verilog";   inst_list[35] = "../isa/generated/rv32ui-p-lbu.verilog";   
    inst_list[36] = "../isa/generated/rv32ui-p-lhu.verilog";   inst_list[37] = "../isa/generated/rv32um-p-mul.verilog";  inst_list[38] = "../isa/generated/rv32um-p-mulh.verilog"; 
    inst_list[39] = "../isa/generated/rv32um-p-mulhu.verilog";inst_list[40] = "../isa/generated/rv32um-p-mulhsu.verilog";inst_list[41] = "../isa/generated/rv32um-p-div.verilog";  
    inst_list[42] = "../isa/generated/rv32um-p-divu.verilog";  inst_list[43] = "../isa/generated/rv32um-p-rem.verilog";  inst_list[44] = "../isa/generated/rv32um-p-remu.verilog";
end

initial begin
    #(2000 * 20000);
    $display("~~~~~~~~~~~~~~~~~~~ %s time_out ~~~~~~~~~~~~~~~~~~~~", inst_name); 
    $display("stop at %2d", gp_x3);
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
