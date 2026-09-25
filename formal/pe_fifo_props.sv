// Formal harness for pe_fifo: safety, dynamics, and FIFO-order data integrity.
// Engine: SymbiYosys (abc bmc3 / abc pdr). See formal/fifo.sby.
`default_nettype none
module pe_fifo_formal #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 4
) ();
    localparam int LEVEL_W = $clog2(DEPTH + 1);

    reg clk;
    reg rst_ni;
    reg soft_reset_i;
    reg push_i;
    reg pop_i;
    reg [WIDTH-1:0] push_data_i;

    wire [WIDTH-1:0] pop_data_o;
    wire empty_o, full_o;
    wire [LEVEL_W-1:0] level_o;

    pe_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_ni),
        .soft_reset_i(soft_reset_i),
        .push_i(push_i),
        .pop_i(pop_i),
        .push_data_i(push_data_i),
        .pop_data_o(pop_data_o),
        .empty_o(empty_o),
        .full_o(full_o),
        .level_o(level_o)
    );

    // Accepted-transfer conditions mirroring the RTL.
    wire push_ok = push_i && (!full_o || (pop_i && !empty_o));
    wire pop_ok  = pop_i  && (!empty_o || (push_i && full_o));

    reg f_past_valid = 0;

    always @(posedge clk) begin
        if (!f_past_valid) begin
            f_past_valid <= 1'b1;
            assume (!rst_ni);   // cycle 0 is the hardware reset cycle
        end else begin
            assume (rst_ni);    // no hardware reset afterwards
        end
    end

    // ------------------------------------------------------------------
    // Safety and dynamics
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (f_past_valid) begin
            // Output-flag consistency and bounds.
            assert (empty_o == (level_o == 0));
            assert (full_o == (level_o == DEPTH[LEVEL_W-1:0]));
            assert (!(empty_o && full_o));
            assert (level_o <= DEPTH[LEVEL_W-1:0]);

            if (!($past(rst_ni))) begin
                // Effect of the async reset.
                assert (level_o == 0);
                assert (empty_o && !full_o);
            end else if ($past(soft_reset_i)) begin
                // Synchronous soft reset clears everything.
                assert (level_o == 0);
                assert (empty_o && !full_o);
            end else begin
                // Level dynamics: +1 on accepted push only, -1 on accepted
                // pop only, unchanged otherwise (covers simultaneous
                // push+pop and blocked overflow/underflow attempts).
                case ({ $past(push_ok), $past(pop_ok) })
                    2'b10:   assert (level_o == $past(level_o) + 1'b1);
                    2'b01:   assert (level_o == $past(level_o) - 1'b1);
                    default: assert (level_o == $past(level_o));
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // Data integrity / FIFO ordering (bounded-proof task only: relating
    // the ghost word to memory contents is not inductive without internal
    // state visibility, so induction runs without these properties)
    //
    // Track one symbolic word: arm when a push is accepted while the
    // occupancy equals the free constant f_target, remember the data and
    // the number of older words ahead of it (f_ahead). Every accepted pop
    // decrements f_ahead; when the ghost word reaches the head (f_ahead
    // == 0) the next accepted pop must return exactly the recorded data.
    // ------------------------------------------------------------------
`ifdef FORMAL_DATA_INTEGRITY
    (* anyconst *) reg [LEVEL_W-1:0] f_target;
    reg f_armed = 0;
    reg [WIDTH-1:0] f_ghost;
    reg [LEVEL_W-1:0] f_ahead;

    always @(posedge clk) begin
        if (!f_past_valid) begin
            assume (f_target < DEPTH[LEVEL_W-1:0]);
        end else if (!rst_ni || soft_reset_i) begin
            f_armed <= 1'b0;
        end else begin
            if (!f_armed && push_ok && (level_o == f_target)) begin
                f_armed <= 1'b1;
                f_ghost <= push_data_i;
                // f_target older words are ahead; a simultaneous accepted
                // pop removes the oldest one in the same cycle. (pop_ok at
                // level_o == f_target implies f_target >= 1, since a pop is
                // never accepted from an empty FIFO.)
                if (pop_ok) f_ahead <= f_target - 1'b1;
                else        f_ahead <= f_target;
            end else if (f_armed && pop_ok) begin
                if (f_ahead == 0) begin
                    assert (pop_data_o == f_ghost);
                    f_armed <= 1'b0;
                end else begin
                    f_ahead <= f_ahead - 1'b1;
                end
            end
        end
    end

    // While armed, the ghost word is inside the FIFO.
    always @(posedge clk) begin
        if (f_past_valid && f_armed) begin
            assert (level_o >= 1);
        end
    end
`endif
endmodule
