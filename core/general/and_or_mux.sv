module and_or_mux
#(
    parameter int INPUTS    = 4,
    parameter int DW        = 16
)
(
    input  logic[INPUTS-1:0][DW-1:0]    data_in,
    input  logic[INPUTS-1:0]            sel,
    output logic[DW-1:0]                data_out
);

// version 2, and using variable like operation.
// using 1-bit logic temp exactly as in VHDL. 
// When assignments are = (and not <=) in always blocks 
// temp signal behaves exactly as a variable in VHDL
logic tmp;

always_comb begin: mux
    for(int w=0; w < DW; w=w+1) begin
        tmp = 0;
        for(int i=0; i < INPUTS; i=i+1) begin
            tmp = tmp | ( sel[i] & data_in[i][w] );
        end
        data_out[w] = tmp;
    end
end

endmodule