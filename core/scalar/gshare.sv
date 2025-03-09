module gshare 
#(
	parameter int	HISTORY_BITS = 12		,
	parameter int	SIZE		   = 1024
) 
(
	input  logic               	clk           ,
	input  logic               	rst_n         ,
	//Update Interface
	input  logic               	wr_en         ,
	input  logic [31:0] 		orig_pc       ,
	input  logic               	is_taken	  ,
	//Access Interface
	input  logic [31:0] 		pc_in_a       ,//是否需要对两个PC进行分支预测
	input  logic [31:0] 		pc_in_b       ,//是否需要对两个PC进行分支预测
	//Output Interface
	output logic               	is_taken_out_a,
	output logic               	is_taken_out_b

);
	localparam SEL_BITS = $clog2(SIZE);
	// #Internal Signals#
	logic [    SEL_BITS+1 : 0] counter_selector_a, counter_selector_b;
	logic [    SEL_BITS-1 : 0] line_selector_a, line_selector_b;
	//logic [HISTORY_BITS-1 : 0] counter_selector_a, counter_selector_b;
	logic [HISTORY_BITS-1 : 0] gl_history;
	logic [             1 : 0] retrieved_counter_a, retrieved_counter_b, old_counter, final_value;
	logic [             7 : 0] retrieved_data_a, retrieved_data_b, write_retrieved_data, new_counter_vector;

	logic [    SEL_BITS+1 : 0] write_counter_selector;
	logic [    SEL_BITS-1 : 0] write_line_selector;
	//logic [HISTORY_BITS-1 : 0] write_counter_selector;

	//logic [HISTORY_BITS +1: 0] starting_bit_a, starting_bit_b, write_counter_start_bit;
	logic [2:0] starting_bit_a, starting_bit_b;
	logic [2:0] write_counter_start_bit;
	logic [2:0][SEL_BITS-1 : 0]read_addresses;
	logic [2:0][7 :0] 		   data_out;

	localparam int GS_SIZE = 8*SIZE + $bits(gl_history);

//-------------------------------寻址饱和计数器进行分支预测--------------------------------------//
	//assign counter_selector_a = gl_history ^ pc_in_a[HISTORY_BITS : 1];
	//assign counter_selector_b = gl_history ^ pc_in_b[HISTORY_BITS : 1];
	assign counter_selector_a = gl_history ^ pc_in_a[HISTORY_BITS+1 : 2];
	assign counter_selector_b = gl_history ^ pc_in_b[HISTORY_BITS+1 : 2];
	//直接选中PHT的某行
	//assign line_selector_a = pc_in_a[SEL_BITS : 1];
	//assign line_selector_b = pc_in_b[SEL_BITS : 1];
	assign line_selector_a = counter_selector_a[SEL_BITS+1 : 2];
	assign line_selector_b = counter_selector_b[SEL_BITS+1 : 2];
	//从一行PHT(2个)中选中其中一个
	assign starting_bit_a      = {{counter_selector_a[1:0]}, 1'b0};
	assign starting_bit_b      = {{counter_selector_b[1:0]}, 1'b0};
	assign retrieved_counter_a = retrieved_data_a[starting_bit_a +: 2];
	assign retrieved_counter_b = retrieved_data_b[starting_bit_b +: 2];
	//MSB of counter is our output
	assign is_taken_out_a = retrieved_counter_a[1];
	assign is_taken_out_b = retrieved_counter_b[1];

	assign read_addresses[0] = line_selector_a;
	assign read_addresses[1] = line_selector_b;
	assign read_addresses[2] = write_line_selector;

	//-------PHT-------// 
	//------sram-------// 
	//------8bit-------// 
	//  xx  xx  xx  xx // 
	//.................//
	//.................//
	//.................//
	//.................//
	//  xx  xx  xx  xx //
	sram 
	#(
		.SIZE      (SIZE),
		.DATA_WIDTH(8   ),
		.RD_PORTS  (3   ),
		.WR_PORTS  (1   ),
		.RESETABLE (1   )
	)u_sram 
	(
		.clk          (clk                ),
		.rst_n        (rst_n              ),
		.wr_en        (wr_en              ),
		.read_address (read_addresses     ),
		.data_out     (data_out           ),
		.write_address(write_line_selector),
		.new_data     (new_counter_vector )
	);

	assign retrieved_data_a     = data_out[0];
	assign retrieved_data_b     = data_out[1];
	assign write_retrieved_data = data_out[2];
//-------------------------------update PHT--------------------------------------//
//to do: GHR可以设置两个，一个用于预测，在该周期得到预测结果就马上更新；
//					    一个用于预测失败的恢复，在退休时更新
	//assign write_line_selector       = orig_pc[SEL_BITS : 1];
	//assign write_counter_selector    = gl_history ^ orig_pc[HISTORY_BITS : 1];
	//assign write_counter_start_bit = write_counter_selector[0] << 1;
	assign write_counter_selector    = gl_history ^ orig_pc[HISTORY_BITS+1 : 2];
	assign write_line_selector       = write_counter_selector[SEL_BITS+1 : 2];
	assign write_counter_start_bit = {{write_counter_selector[1:0]}, 1'b0};
	//Get the old Counter Value
	assign old_counter = write_retrieved_data[write_counter_start_bit +: 2];
	//2bit counter
	always_comb begin 
		if(is_taken) begin
			if(old_counter<2'b11) begin
				final_value = old_counter+1;
			end else begin
				final_value = old_counter;
			end
		end else begin
			if(old_counter>2'b00) begin
				final_value = old_counter-1;
			end else begin
				final_value = old_counter;
			end
		end
	end
	always_comb begin 
		// Only one counter is modified
		new_counter_vector                             = write_retrieved_data;
		new_counter_vector[write_counter_start_bit+:2] = final_value;
	end
//-------------------------------update GHR--------------------------------------//
	always_ff @(posedge clk or negedge rst_n) begin 
		if(!rst_n) begin//reset global history
			gl_history <= 'b0;
		end else begin
			if(wr_en) begin//Update Global History by sliding
				gl_history <= {is_taken,gl_history[HISTORY_BITS-1:1]};
			end
		end
	end

endmodule