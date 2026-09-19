module pe_sync #(parameter int N_PINS = 8) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [N_PINS-1:0] async_i,
    output logic [N_PINS-1:0] sampled_o,
    output logic [N_PINS-1:0] rising_o,
    output logic [N_PINS-1:0] falling_o
);
    logic [N_PINS-1:0] ff1_q;
    logic [N_PINS-1:0] ff2_q;
    logic [N_PINS-1:0] previous_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ff1_q <= '0;
            ff2_q <= '0;
            previous_q <= '0;
        end else begin
            ff1_q <= async_i;
            ff2_q <= ff1_q;
            previous_q <= ff2_q;
        end
    end

    assign sampled_o = ff2_q;
    assign rising_o = ff2_q & ~previous_q;
    assign falling_o = ~ff2_q & previous_q;
endmodule
