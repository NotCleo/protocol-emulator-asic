// Replaceable program-memory boundary for the full management-plane design.
// The active Milestone 1 engine uses pe_imem.sv behind protocol_emulator_top.
module program_mem #(
    parameter IMEM_WIDTH = 16,
    parameter IMEM_DEPTH = 128
) (
    input wire clk_i,
    input wire we_i,
    input wire [$clog2(IMEM_DEPTH)-1:0] addr_i,
    input wire [IMEM_WIDTH-1:0] wdata_i,
    output wire [IMEM_WIDTH-1:0] rdata_o
);
    reg [IMEM_WIDTH-1:0] mem [0:IMEM_DEPTH-1];
    assign rdata_o = mem[addr_i];
    always @(posedge clk_i) if (we_i) mem[addr_i] <= wdata_i;
endmodule
