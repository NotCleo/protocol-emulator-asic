// CSR ownership boundary. Functional CSRs remain in the Milestone 1 engine
// host interface until management SPI framing is frozen.
module csr_block (
    input wire clk_i,
    input wire rst_ni,
    input wire write_i,
    input wire read_i,
    input wire [15:0] addr_i,
    input wire [31:0] wdata_i,
    output wire [31:0] rdata_o
);
    assign rdata_o = 32'b0;
    wire _unused = &{clk_i, rst_ni, write_i, read_i, addr_i[0], wdata_i[0]};
endmodule
