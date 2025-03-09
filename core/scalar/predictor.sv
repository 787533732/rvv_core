module predictor
#(
	parameter int GSH_HISTORY_BITS = 12	,
	parameter int GSH_SIZE         = 256,
	parameter int BTB_SIZE         = 256,
	parameter int RAS_DEPTH        = 8	
)									
(
    input  logic 				clk				,
    input  logic 				rst_n			,
    //Control Interface
    input  logic 				must_flush		,
    input  logic 				is_branch		,
    input  logic 				branch_resolved	,
    //Update Interface
    input  logic                new_entry		,
    input  logic [31:0]         pc_orig			,
    input  logic [31:0]         target_pc		,
    input  logic                is_taken		,
    //RAS Interface
    input  logic                is_return		,
    input  logic                is_jumpl		,
    input  logic 			    invalidate		,
    input  logic [31:0]         old_pc			,
    //Access Interface          
    input  logic [31:0]         pc_in			,
    output logic				taken_branch_a	,
    output logic [31:0]         next_pc_a		,
    output logic				taken_branch_b	,
    output logic [31:0]         next_pc_b
);
	// #Internal Signals#
	logic [31:0] pc_in_2, next_pc_btb_a, next_pc_btb_b, pc_out_ras, new_entry_ras;
	logic hit_btb_a, hit_btb_b, pop, push, is_empty_ras, is_taken_out_a, is_taken_out_b;

	assign pc_in_2        = pc_in + 4;
	assign taken_branch_a = (hit_btb_a & is_taken_out_a);
	assign taken_branch_b = (hit_btb_b & is_taken_out_b);
	//Initialize the GShare
	gshare 
    #(
		.HISTORY_BITS(GSH_HISTORY_BITS),
		.SIZE        (GSH_SIZE        )
	)gshare 
    (
		.clk           (clk           ),
		.rst_n         (rst_n         ),
		//Update Interface
		.wr_en         (new_entry     ),
		.is_taken      (is_taken      ),
		.orig_pc       (pc_orig       ),
		//Access Interface
		.pc_in_a       (pc_in         ),
		.pc_in_b       (pc_in_2       ),
		//Output Interface
		.is_taken_out_a(is_taken_out_a),
		.is_taken_out_b(is_taken_out_b)
	);
	//Initialize the BTB
	btb //direct mapped 
	#(
		.SIZE   (BTB_SIZE)
	)btb 
	(
		.clk       		(clk          ),
		.rst_n     		(rst_n        ),
		//Update Interface
		.wr_en     		(new_entry    ),
		.orig_pc   		(pc_orig      ),
		.target_pc 		(target_pc    ),
		//Invalidation Interface
		.invalidate		(invalidate   ),
		.pc_invalid		(old_pc       ),
		//Access Interface
		.pc_in_a   		(pc_in        ),
		.pc_in_b   		(pc_in_2      ),
		//Output Ports 
		.hit_a     		(hit_btb_a    ),
		.next_pc_a 		(next_pc_btb_a),
		.hit_b     		(hit_btb_b    ),
		.next_pc_b 		(next_pc_btb_b)
	);

	//RAS Drive Signals
	assign pop  = (is_return & ~is_empty_ras);					
	assign push = is_jumpl;
	assign new_entry_ras = old_pc +4;
	//Initialize the RAS
	ras 
	#(
		.SIZE   		(RAS_DEPTH			  )
	)ras 
	(
		.clk            (clk                  ),
		.rst_n          (rst_n                ),
		
		.must_flush     (must_flush           ),
		.is_branch      (is_branch & ~is_jumpl),
		.branch_resolved(branch_resolved      ),
		
		.pop            (pop                  ),
		.push           (push                 ),
		.new_entry      (new_entry_ras        ),
		.pc_out         (pc_out_ras           ),
		.is_empty       (is_empty_ras         )
	);
	//push the Correct PC to the Output
	always_comb begin : PushOutputA
		if(pop) begin
			next_pc_a = pc_out_ras;
		end else if(hit_btb_a && is_taken_out_a) begin
			next_pc_a = next_pc_btb_a;
		end else begin
			next_pc_a = pc_in+8;
		end
	end
	always_comb begin : PushOutputB
		if(pop) begin
			next_pc_b = pc_out_ras;
		end else if(hit_btb_b && is_taken_out_b) begin
			next_pc_b = next_pc_btb_b;
		end else begin
			next_pc_b = pc_in_2+8;
		end
	end
	//assign next_pc_a = pc_in+8;
	//assign next_pc_b = pc_in_2+8;
endmodule