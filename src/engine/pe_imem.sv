module pe_imem #(
    parameter int IMEM_DEPTH = 64
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [$clog2(IMEM_DEPTH)-1:0] pc_i,
    output logic [15:0]                  instr_o,
    input  logic                         host_we_i,
    input  logic [$clog2(IMEM_DEPTH/2)-1:0] host_word_addr_i,
    input  logic [31:0]                  host_wdata_i,
    input  logic [3:0]                   host_wstrb_i,
    output logic [31:0]                  host_rdata_o
);
    localparam int PC_W = $clog2(IMEM_DEPTH);
    localparam int HOST_W = $clog2(IMEM_DEPTH/2);
    logic [15:0] imem [0:IMEM_DEPTH-1];

    always_comb begin
        instr_o = imem[pc_i];
        host_rdata_o = 32'b0;
        host_rdata_o[15:0] = imem[{host_word_addr_i, 1'b0}];
        host_rdata_o[31:16] = imem[{host_word_addr_i, 1'b0} + 1'b1];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < IMEM_DEPTH; i = i + 1)
                imem[i] <= 16'b0;
        end else if (host_we_i) begin
            if (host_wstrb_i[0]) imem[{host_word_addr_i, 1'b0}][7:0] <= host_wdata_i[7:0];
            if (host_wstrb_i[1]) imem[{host_word_addr_i, 1'b0}][15:8] <= host_wdata_i[15:8];
            if (host_wstrb_i[2]) imem[{host_word_addr_i, 1'b0} + 1'b1][7:0] <= host_wdata_i[23:16];
            if (host_wstrb_i[3]) imem[{host_word_addr_i, 1'b0} + 1'b1][15:8] <= host_wdata_i[31:24];
        end
    end
endmodule
