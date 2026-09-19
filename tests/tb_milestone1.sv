`timescale 1ns/1ps

module tb_milestone1;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic host_valid = 1'b0;
    logic host_write = 1'b0;
    logic [15:0] host_addr = '0;
    logic [31:0] host_wdata = '0;
    logic [3:0] host_wstrb = 4'b0;
    logic [31:0] host_rdata;
    logic host_ready;
    logic [7:0] gpio_in = '0;
    logic [7:0] gpio_out;
    logic [7:0] gpio_oe;
    integer trace_file;
    integer trace_tick;
    integer divider_events;
    logic [15:0] trace_instruction;
    logic trace_delay;
    logic [1:0] trace_sideset;
    logic trace_wait;
    string trace_fifo_activity;
    logic [5:0] trace_pc;

    always #5 clk = ~clk;

    protocol_emulator_top dut (
        .clk_i(clk), .rst_ni(rst_n),
        .host_valid_i(host_valid), .host_write_i(host_write),
        .host_addr_i(host_addr), .host_wdata_i(host_wdata),
        .host_wstrb_i(host_wstrb), .host_rdata_o(host_rdata),
        .host_ready_o(host_ready), .gpio_in_i(gpio_in),
        .gpio_out_o(gpio_out), .gpio_oe_o(gpio_oe)
    );

    task automatic host_write_word(input logic [15:0] address, input logic [31:0] data);
        begin
            @(negedge clk);
            host_valid = 1'b1; host_write = 1'b1; host_addr = address;
            host_wdata = data; host_wstrb = 4'hf;
            @(negedge clk);
            host_valid = 1'b0; host_write = 1'b0; host_addr = '0;
            host_wdata = '0; host_wstrb = '0;
        end
    endtask

    task automatic host_read_word(input logic [15:0] address, output logic [31:0] data);
        begin
            @(negedge clk);
            host_valid = 1'b1; host_write = 1'b0; host_addr = address;
            #1 data = host_rdata;
            @(negedge clk);
            host_valid = 1'b0; host_addr = '0;
        end
    endtask

    task automatic expect_equal(input logic condition, input string message);
        begin
            if (!condition) $fatal(1, "FAIL %s", message);
        end
    endtask

    // Capture post-event architectural state while retaining the instruction
    // and PC that were present at the engine event boundary.
    always @(posedge clk) begin
        if (dut.engine_ce && (trace_tick < 12)) begin
            trace_tick = trace_tick + 1;
            trace_pc = dut.imem_pc;
            trace_delay = (dut.delay_count != 0);
            trace_instruction = trace_delay ? 16'hffff : dut.instr;
            trace_sideset = dut.sideset_we ? dut.sideset_value[1:0] : 2'b0;
            trace_wait = (dut.stall_reason == 3'd2);
            if (dut.tx_core_pop) trace_fifo_activity = "pull";
            else if (dut.rx_core_push) trace_fifo_activity = "push";
            else if (dut.stall_reason == 3'd3) trace_fifo_activity = "pull_block";
            else if (dut.stall_reason == 3'd4) trace_fifo_activity = "push_block";
            else trace_fifo_activity = "-";
            #1;
            if (trace_file != 0)
                $fwrite(trace_file, "%04d %04d %02d %s %04x %04x %08x %08x %02x %02x %02x %0d %0d %s %0d %02d %02x %0d %0d %s\n",
                    trace_tick, trace_tick, dut.imem_pc,
                    trace_delay ? "----" : $sformatf("%04x", trace_instruction),
                    dut.x, dut.y, dut.osr, dut.isr, dut.gpio_sampled, gpio_out, gpio_oe,
                    dut.tx_level, dut.rx_level, trace_fifo_activity, trace_wait,
                    dut.delay_count, trace_sideset, dut.running, dut.fault,
                    trace_delay ? "delay" : "-");
        end
    end

    logic [31:0] readback;
    logic [5:0] saved_pc;
    logic [15:0] saved_x;

    initial begin
        trace_tick = 0;
        trace_file = $fopen("sim/rtl_gpio_toggle.trace", "w");
        repeat (3) @(posedge clk); #1;
        expect_equal(!dut.running, "reset running");
        expect_equal(dut.imem_pc == 0, "reset PC");
        expect_equal(dut.x == 0 && dut.y == 0, "reset X/Y");
        expect_equal(gpio_out == 0 && gpio_oe == 0, "reset GPIO high impedance");
        rst_n = 1'b1;

        // gpio_toggle.pasm assembled by tools/assembler.py:
        // 0: e420, 1: e021, 2: e001, 3: 0010.
        host_write_word(16'h0100, 32'he021_e420);
        host_write_word(16'h0104, 32'h0010_e001);
        host_read_word(16'h0100, readback);
        expect_equal(readback == 32'he021_e420, "program readback word 0");
        host_read_word(16'h0104, readback);
        expect_equal(readback == 32'h0010_e001, "program readback word 1");

        host_write_word(16'h0008, 32'd0); // START_PC
        host_write_word(16'h000c, 32'd1); // CLKDIV=1
        host_write_word(16'h0010, 32'd0); // SET_BASE=0
        host_write_word(16'h0014, 32'd0); // SIDESET_BASE=0, COUNT=0
        host_write_word(16'h0000, 32'd1); // RUN
        repeat (12) @(posedge clk);
        expect_equal(gpio_oe[0] && gpio_out[0] == 1'b0, "gpio toggle low state");

        // HALT preserves state and no longer advances the engine.
        host_write_word(16'h0000, 32'd2);
        saved_pc = dut.imem_pc; saved_x = dut.x;
        repeat (5) @(posedge clk); #1;
        expect_equal(!dut.running && dut.imem_pc == saved_pc && dut.x == saved_x, "halt preserves state");

        // SET X/Y through the same host program window.
        host_write_word(16'h0100, 32'hed80_e8e0);
        host_write_word(16'h0008, 32'd0);
        host_write_word(16'h0000, 32'd1);
        repeat (4) @(posedge clk);
        expect_equal(dut.x == 16'd7 && dut.y == 16'd12, "SET X/Y");

        // Soft reset clears architectural state without rst_n.
        host_write_word(16'h0000, 32'd4);
        expect_equal(!dut.running && dut.imem_pc == 0 && dut.x == 0 && dut.y == 0,
                     "soft reset state");
        expect_equal(gpio_out == 0 && gpio_oe == 0, "soft reset GPIO");

        // Exact Milestone 0 delay program: SET PINS,1 [3]; SET PINS,0.
        host_write_word(16'h0100, 32'he000_e023);
        host_write_word(16'h0008, 32'd0);
        host_write_word(16'h000c, 32'd1);
        host_write_word(16'h0014, 32'd0);
        host_write_word(16'h0000, 32'd1);
        @(posedge clk); #1;
        expect_equal(gpio_out[0] && dut.delay_count == 5'd3, "delay execute once");
        repeat (3) @(posedge clk); #1;
        expect_equal(gpio_out[0] && dut.delay_count == 5'd0, "delay stalls three engine ticks");
        @(posedge clk); #1;
        expect_equal(!gpio_out[0], "delay next instruction");
        host_write_word(16'h0000, 32'd4);

        // Exact Milestone 0 side-set program: SET X,7 SIDE 1 [1]; NOP SIDE 0.
        host_write_word(16'h0100, 32'hc000_e8f1);
        host_write_word(16'h0008, 32'd0);
        host_write_word(16'h0014, 32'h0000_0101); // base=1, count=1
        host_write_word(16'h0000, 32'd1);
        @(posedge clk); #1;
        expect_equal(dut.x == 16'd7 && gpio_out[1], "side-set same event");
        repeat (2) @(posedge clk); #1;
        expect_equal(!gpio_out[1], "NOP side-set clear");
        host_write_word(16'h0000, 32'd4);

        // Exact Milestone 0 X-- jump program, including the X=2 boundary.
        host_write_word(16'h0100, 32'h0810_e840);
        host_write_word(16'h0104, 32'h0000_ec20);
        host_write_word(16'h0008, 32'd0);
        host_write_word(16'h0014, 32'd0);
        host_write_word(16'h000c, 32'd1);
        host_write_word(16'h0000, 32'd1);
        repeat (5) @(posedge clk); #1;
        expect_equal(dut.x == 16'd0 && dut.y == 16'd1, "X-- jump boundary");
        host_write_word(16'h0000, 32'd4);

        // Integer divider: twelve system clocks contain four engine events at N=3.
        host_write_word(16'h0100, 32'h0000_e8e0);
        host_write_word(16'h0008, 32'd0);
        host_write_word(16'h000c, 32'd3);
        host_write_word(16'h0000, 32'd1);
        divider_events = 0;
        repeat (12) begin
            @(posedge clk);
            if (dut.engine_ce && dut.running) divider_events = divider_events + 1;
        end
        expect_equal(divider_events == 4, "clock divider N=3");
        host_write_word(16'h0000, 32'd4);

        // A running program cannot be overwritten and must fault/halt.
        host_write_word(16'h0008, 32'd0);
        host_write_word(16'h0000, 32'd1);
        repeat (2) @(posedge clk);
        host_write_word(16'h0100, 32'h0000_0000);
        expect_equal(dut.fault && !dut.running, "running IMEM write fault");
        host_read_word(16'h0100, readback);
        expect_equal(readback[15:0] == 16'he8e0, "running IMEM write rejected");

        // Sequential execution at the last 64-word address faults; it does not wrap.
        host_write_word(16'h0000, 32'd4);
        host_write_word(16'h017c, 32'he820_0000); // instruction 63 is SET X,1
        host_write_word(16'h0008, 32'd63);
        host_write_word(16'h000c, 32'd1);
        host_write_word(16'h0000, 32'd1);
        repeat (3) @(posedge clk); #1;
        expect_equal(dut.imem_pc == 6'd63 && dut.x == 16'd1 && dut.fault && !dut.running,
                     "64-word PC end fault");

        $fclose(trace_file);
        $display("PASS milestone1 public-interface tests");
        $finish;
    end
endmodule
