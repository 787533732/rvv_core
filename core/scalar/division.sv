module division #(
    parameter DATA_WIDTH  = 32,
    parameter CALC_CYCLES = 4
) (
    input  logic                    clk          ,
    input  logic                    rst_n        ,
    //Input Port
    input  logic                    enable       ,
    input  logic [1:0]              op_type      ,
    input  logic [5:0]              destination_i,
    input  logic [2:0]              ticket_i     ,
    input  logic [  DATA_WIDTH-1:0] dividend     ,//被除数
    input  logic [  DATA_WIDTH-1:0] divider      ,//除数
    //Output Port
    output logic                    ready        ,
    output logic                    valid        ,
    output logic [5:0]              destination_o,
    output logic [2:0]              ticket_o     ,
    output logic [DATA_WIDTH-1:0]   result        //商or余数
);

    logic [31:0] dividend_q;
    logic [62:0] divisor_q;
    logic [31:0] quotient_q;
    logic [31:0] q_mask_q;
    logic [31:0] wb_result_q;
    logic [31:0] div_result_r;
    logic        div_inst_q;
    logic        div_busy_q;
    logic        invert_res_q;
    logic        valid_q;
    logic        div_start_w;
    logic        div_complete_w;

    assign div_start_w    = enable;
    assign div_complete_w = !(|q_mask_q) & div_busy_q;

    always @(posedge clk or posedge rst_n) begin
        if (!rst_n) begin
            div_busy_q     <= 1'b0;
            dividend_q     <= 32'b0;
            divisor_q      <= 63'b0;
            invert_res_q   <= 1'b0;
            quotient_q     <= 32'b0;
            q_mask_q       <= 32'b0;
            div_inst_q     <= 1'b0;
            ticket_o       <= 'b0;
            destination_o  <= 'b0; 
        end
        else if (div_start_w) begin
            div_busy_q    <= 1'b1;
            div_inst_q    <= (op_type == 2'b00) || (op_type == 2'b01); 
            ticket_o      <= ticket_i;         
            destination_o <= destination_i;  
            invert_res_q <= ((op_type == 2'b00) && (dividend[31] != divider[31]) && |divider) || 
                            ((op_type == 2'b10) && dividend[31]);
            dividend_q    <= (((op_type == 2'b00) || (op_type == 2'b10)) && dividend[31]) ? -dividend : dividend;
            divisor_q     <= (((op_type == 2'b00) || (op_type == 2'b10)) && divider[31]) ? {-divider, 31'b0} : {divider, 31'b0};
        end
        else if(div_complete_w) begin
            div_busy_q <= 1'b0;
        end
        else if (div_busy_q) begin
            if (divisor_q <= {31'b0, dividend_q}) begin
                dividend_q <= dividend_q - divisor_q[31:0];
                quotient_q <= quotient_q | q_mask_q;
            end
            divisor_q <= {1'b0, divisor_q[62:1]};
            q_mask_q  <= {1'b0, q_mask_q[31:1]};
        end
        else begin
            div_busy_q   <= div_busy_q;
            quotient_q   <= 32'b0;
            q_mask_q     <= 32'h8000_0000;
        end
    end

    
    always @(*) begin
        if (div_inst_q)
            div_result_r = invert_res_q ? -quotient_q : quotient_q;
        else
            div_result_r = invert_res_q ? -dividend_q : dividend_q;
    end

    always @(posedge clk or posedge rst_n) begin
        if (!rst_n)
            valid_q <= 1'b0;
        else
            valid_q <= div_complete_w;
    end
    always @(posedge clk or posedge rst_n) begin
        if (!rst_n)
            wb_result_q <= 32'b0;
        else if (div_complete_w)
            wb_result_q <= div_result_r;
    end
    assign ready  = ~div_busy_q;
    assign valid  = valid_q;
    assign result = wb_result_q;

endmodule

