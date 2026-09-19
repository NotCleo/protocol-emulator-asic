module pe_clkdiv (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        soft_reset_i,
    input  logic        enable_i,
    input  logic [15:0] clkdiv_i,
    output logic        engine_ce_o
);
    logic [15:0] count_q;
    logic [15:0] divisor;

    always_comb begin
        divisor = (clkdiv_i == 16'd0) ? 16'd1 : clkdiv_i;
        engine_ce_o = enable_i && ((divisor == 16'd1) || (count_q == divisor - 16'd1));
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_q <= 16'd0;
        end else if (soft_reset_i || !enable_i) begin
            count_q <= 16'd0;
        end else if (engine_ce_o) begin
            count_q <= 16'd0;
        end else begin
            count_q <= count_q + 16'd1;
        end
    end
endmodule
