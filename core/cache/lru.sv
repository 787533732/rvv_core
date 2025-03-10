/*
 @param ASSOCIATIVITY: The cache assosiativity
 @param ENTRIES      : The total addressable entries.
 @param INDEX_BITS   : The address width
 @param OUTPUT_BITS  : The Output width
 */
module lru 
#(
	ASSOCIATIVITY 	= 2	,
	ENTRIES			= 256,
	INDEX_BITS		= 8	,
	OUTPUT_BITS		= 2
) 
(
    input	logic                   	clk           ,
    input  	logic                   	rst_n         ,
    input  	logic [ INDEX_BITS-1:0] 	line_selector ,
    input  	logic [OUTPUT_BITS-1:0] 	referenced_set,
    input  	logic                   	lru_update    ,
    output 	logic [OUTPUT_BITS-1:0] 	lru_way
);
	generate
		if(ASSOCIATIVITY==2) begin
			//instantiate the 2-way LRU module
			lru2 
			#(ENTRIES,INDEX_BITS) 
			LRU2
			(
				.clk            (clk),
				.rst_n          (rst_n),
				.line_selector  (line_selector),
				.referenced_set (referenced_set),
				.lru_update     (lru_update),
				.lru_way        (lru_way)
			);
		end else if(ASSOCIATIVITY>2) begin
			//instantiate the >2-way LRU module
			lrumore 
			#(ASSOCIATIVITY,ENTRIES,INDEX_BITS,OUTPUT_BITS) 
			LRUMORE
			(
				.clk            (clk),
				.rst_n          (rst_n),
				.line_selector  (line_selector),
				.referenced_set (referenced_set),
				.lru_update     (lru_update),
				.lru_way        (lru_way)
			);
		end
	endgenerate

endmodule