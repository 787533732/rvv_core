module register_file 
#(
    parameter int DATA_WIDTH = 32 , 
    parameter int ADDR_WIDTH = 6  , 
    parameter int SIZE       = 64 , 
    parameter int READ_PORTS = 2
) 
(
	input  logic                                  clk         ,
	input  logic                                  rst_n       ,
	// Write Port
	input  logic                                  write_En    ,
	input  logic [ADDR_WIDTH-1:0]                 write_Addr  ,
	input  logic [DATA_WIDTH-1:0]                 write_Data  ,
	// Write Port
	input  logic                                  write_En_2  ,
	input  logic [ADDR_WIDTH-1:0]                 write_Addr_2,
	input  logic [DATA_WIDTH-1:0]                 write_Data_2,
	// Read Port
	input  logic [READ_PORTS-1:0][ADDR_WIDTH-1:0] read_Addr   ,
	output logic [READ_PORTS-1:0][DATA_WIDTH-1:0] data_Out
);
	// #Internal Signals#
	logic [SIZE-1:0][DATA_WIDTH-1 : 0] RegFile;
	//debug
	logic [DATA_WIDTH-1 : 0] x1_ra_w,x2_sp_w,x4_tp_w,x26_s10_w,x27_s11_w,x29_t4_w,x3_gp_w,x17_a7_w,x10_a0_w;
	logic [DATA_WIDTH-1 : 0] x5_t0_w,x6_t1_w,x30_t5_w,s2,s3;
	logic [DATA_WIDTH-1 : 0] x11_a1_w,x12_a2_w,x14_a4_w,x7_t2_w;
	assign x10_a0_w  = RegFile[10];
	assign x11_a1_w = RegFile[11];
	assign x12_a2_w = RegFile[12];
	assign x14_a4_w = RegFile[14];
	assign x7_t2_w  = RegFile[7];
	assign s2       = RegFile[18];
	assign s3       = RegFile[19];
	
	assign x5_t0_w   = RegFile[5];
	assign x6_t1_w   = RegFile[6];
	assign x30_t5_w  = RegFile[30];
	assign x29_t4_w	 = RegFile[29];
	assign x1_ra_w   = RegFile[1];
	assign x2_sp_w   = RegFile[2];
	assign x4_tp_w   = RegFile[4];
	assign x3_gp_w   = RegFile[3];
	assign x26_s10_w = RegFile[26];
	assign x27_s11_w = RegFile[27];
	assign x17_a7_w  = RegFile[17];

    //x0 is not allow to write
	logic not_zero, not_zero_2;
    assign not_zero   = |write_Addr;
	assign not_zero_2 = |write_Addr_2;
	//Create OH signals
	logic [SIZE-1:0] address_1, address_2;
	assign address_1 = 1 << write_Addr;
	assign address_2 = 1 << write_Addr_2;
	//Write Data
	always_ff @(posedge clk or negedge rst_n) begin : WriteData
		if(!rst_n) begin
			for (int i = 0; i < SIZE; i++) begin
				RegFile[i] <= 'b0;
			end
		end else begin
			for (int i = 0; i < SIZE; i++) begin
				if(write_En_2 && not_zero_2 && address_2[i]) begin
					RegFile[i] <= write_Data_2;
				end else if(write_En && not_zero && address_1[i]) begin
					RegFile[i] <= write_Data;
				end
			end
		end
	end
	//Output Data
	always_comb begin : ReadData
		for (int i = 0; i < READ_PORTS; i++) begin		
			data_Out[i] = RegFile[read_Addr[i]];		
		end
	end
endmodule