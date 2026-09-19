// Management-plane TX FIFO boundary. Functional FIFO integration is a later
// milestone; this module is intentionally inert rather than a second engine.
module tx_fifo (
    input wire clk_i, input wire rst_ni, input wire push_i, input wire pop_i,
    input wire [31:0] data_i, output wire [31:0] data_o,
    output wire empty_o, output wire full_o
);
    assign data_o = 32'b0;
    assign empty_o = 1'b1;
    assign full_o = 1'b0;
    wire _unused = &{clk_i, rst_ni, push_i, pop_i, data_i[0]};
endmodule
