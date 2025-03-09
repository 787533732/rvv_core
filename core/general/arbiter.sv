//RR轮询仲裁器=优先级更新+固定优先级仲裁器：输出优先级最高的值，向左依次循环递减
module arbiter
#(
   parameter int N = 4
)
(
   //Inputs
   input    logic [N-1:0]    request_i ,
   input    logic [N-1:0]    priority_i, 
   //Outputs
   output   logic [N-1:0]    grant_o   ,
   output   logic            anygnt_o
);	 

localparam int S = $clog2(N);

// Priority propagate and ganerate signals
logic [N-1:0] g [S:0];
logic [N-1:0] p [S-1:0];

logic [N-1:0] grant_s;
logic valid;

assign grant_o = grant_s;
	 
int i,j;
always_comb begin
   // initialize priority propagate 
   // and generate vectors
   p[0][0] = ~request_i[N-1];
   g[0][0] = priority_i[0];
   for(j=1; j < N; j=j+1) begin
      p[0][j] = ~request_i[j-1];
      g[0][j] = priority_i[j];
   end
   // implement first log2n-1 prefix levels
   for(i=1; i < S; i=i+1)
      for(j=0; j < N; j=j+1) begin
	      if((j-2**(i-1)) < 0) begin
            g[i][j] = g[i-1][j] | ( p[i-1][j] & g[i-1][N+j-2**(i-1)]);
            p[i][j] = p[i-1][j] & p[i-1][N+j-2**(i-1)];
         end
         else begin
            g[i][j] = g[i-1][j] | ( p[i-1][j] & g[i-1][ j-2**(i-1)]);
            p[i][j] = p[i-1][j] & p[i-1][ j-2**(i-1)];
         end
      end
   // last prefix level
   for(j=0; j < N; j=j+1) begin
      if ((j-2**(S-1)) < 0)
         g[S][j] = g[S-1][j] | ( p[S-1][j] & g[S-1][ N+j-2**(S-1)]);
      else
         g[S][j] = g[S-1][j] | ( p[S-1][j] & g[S-1][ j-2**(S-1)]);
   end
   // grant signal generation 
   for(j=0; j < N; j=j+1)
      grant_s[j] = request_i[j] & g[S][j];
end
// Any grant generation at last prefix level
assign valid = ~( p[S-1][N-1] & p[S-1][N/2-1]);
assign anygnt_o = valid;

endmodule
