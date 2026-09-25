// Formal harness for pe_clkdiv: tick generation and divider invariants.
// Engine: SymbiYosys (smtbmc z3). See formal/clkdiv.sby.
//
// The DUT's internal counter is not referenced hierarchically (unsupported
// by the Yosys frontend); instead a ghost counter models the intended
// behavior and the observable tick output is asserted equal to the ghost
// tick every cycle. Both counters start at zero out of reset and receive
// identical increment/reset control whenever the equality assertion holds,
// so a violation is the only possible outcome of a behavioral deviation.
`default_nettype none
module pe_clkdiv_formal ();
    reg clk;
    reg rst_ni;
    reg soft_reset_i;
    reg enable_i;

    // The CLKDIV CSR is halted-only writable, so the divisor is stable
    // during engine operation: model it as a free constant.
    (* anyconst *) reg [15:0] clkdiv_c;
    wire [15:0] divisor = (clkdiv_c == 16'd0) ? 16'd1 : clkdiv_c;

    wire engine_ce_o;

    pe_clkdiv dut (
        .clk_i(clk),
        .rst_ni(rst_ni),
        .soft_reset_i(soft_reset_i),
        .enable_i(enable_i),
        .clkdiv_i(clkdiv_c),
        .engine_ce_o(engine_ce_o)
    );

    reg f_past_valid = 0;

    always @(posedge clk) begin
        if (!f_past_valid) begin
            f_past_valid <= 1'b1;
            assume (!rst_ni);   // cycle 0 is the hardware reset cycle
        end else begin
            assume (rst_ni);
        end
    end

    // Ghost model of the divider counter.
    reg [15:0] f_count = 0;
    wire f_tick = enable_i && ((divisor == 16'd1) || (f_count == divisor - 16'd1));

    always @(posedge clk) begin
        if (!rst_ni || soft_reset_i || !enable_i || f_tick)
            f_count <= 16'd0;
        else
            f_count <= f_count + 16'd1;
    end

    // ------------------------------------------------------------------
    // Properties
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (f_past_valid) begin
            // Observable tick output equals the model tick every cycle:
            // no early ticks, no late ticks, no missed ticks.
            assert (engine_ce_o == f_tick);

            // A tick only fires while enabled (combinational contract).
            assert (!engine_ce_o || enable_i);

            // Model facts; together with the equality above they prove the
            // exact tick period of one tick per `divisor` enabled cycles.
            if (enable_i) assert (f_count < divisor);
            if (!enable_i) assert (!engine_ce_o);

            // Enable low or soft reset in the previous cycle cleared the
            // counter this cycle.
            if ($past(rst_ni) && ($past(soft_reset_i) || !$past(enable_i)))
                assert (f_count == 16'd0);
        end
    end
endmodule
