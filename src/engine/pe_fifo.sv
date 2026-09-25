module pe_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 4
) (
    input  logic clk_i,
    input  logic rst_ni,
    input logic soft_reset_i,
    input  logic push_i,
    input  logic pop_i,
    input  logic [WIDTH-1:0] push_data_i,
    output logic [WIDTH-1:0] pop_data_o,
    output logic empty_o,
    output logic full_o,
    output logic [$clog2(DEPTH+1)-1:0] level_o
);
    localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int LEVEL_W = $clog2(DEPTH+1);
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0] rd_ptr_q;
    logic [PTR_W-1:0] wr_ptr_q;
    logic [LEVEL_W-1:0] level_q;

    assign empty_o = (level_q == 0);
    assign full_o = (level_q == DEPTH);
    assign level_o = level_q;
    assign pop_data_o = mem[rd_ptr_q];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_ptr_q <= '0;
            wr_ptr_q <= '0;
            level_q <= '0;
            for (int i = 0; i < DEPTH; i = i + 1) mem[i] <= '0;
        end else if (soft_reset_i) begin
            // synchronous soft reset: same state clear, sampled on clk
            rd_ptr_q <= '0;
            wr_ptr_q <= '0;
            level_q <= '0;
            for (int i = 0; i < DEPTH; i = i + 1) mem[i] <= '0;
        end else begin
            if (push_i && (!full_o || (pop_i && !empty_o))) begin
                mem[wr_ptr_q] <= push_data_i;
                if (wr_ptr_q == DEPTH-1) wr_ptr_q <= '0;
                else wr_ptr_q <= wr_ptr_q + 1'b1;
            end
            if (pop_i && (!empty_o || (push_i && full_o))) begin
                if (rd_ptr_q == DEPTH-1) rd_ptr_q <= '0;
                else rd_ptr_q <= rd_ptr_q + 1'b1;
            end
            case ({push_i && (!full_o || (pop_i && !empty_o)), pop_i && (!empty_o || (push_i && full_o))})
                2'b10: level_q <= level_q + 1'b1;
                2'b01: level_q <= level_q - 1'b1;
                default: level_q <= level_q;
            endcase
        end
    end
endmodule
