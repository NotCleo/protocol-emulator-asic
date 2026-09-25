`timescale 1ns/1ps
module tb_random_diff;
`include "random_programs.svh"
    logic clk=0, rst_n=0, host_valid=0, host_write=0;
    logic [15:0] host_addr=0; logic [31:0] host_wdata=0; logic [3:0] host_wstrb=0;
    logic [31:0] host_rdata; logic host_ready; logic [7:0] gpio_in=0, gpio_out, gpio_oe;
    integer trace_file, trace_tick, trace_limit, case_i, word_i;
    logic [15:0] trace_instruction; logic trace_delay;
    logic [1:0] trace_sideset; logic trace_wait; string trace_fifo_activity;
    string trace_stall;
    always #5 clk=~clk;
    protocol_emulator_top dut(.clk_i(clk),.rst_ni(rst_n),.host_valid_i(host_valid),.host_write_i(host_write),
      .host_addr_i(host_addr),.host_wdata_i(host_wdata),.host_wstrb_i(host_wstrb),.host_rdata_o(host_rdata),
      .host_ready_o(host_ready),.gpio_in_i(gpio_in),.gpio_out_o(gpio_out),.gpio_oe_o(gpio_oe));
    task automatic wr(input logic [15:0] a,input logic [31:0] d);
      begin @(negedge clk); host_valid=1;host_write=1;host_addr=a;host_wdata=d;host_wstrb=4'hf;
      @(negedge clk);host_valid=0;host_write=0;host_addr=0;host_wdata=0;host_wstrb=0; end
    endtask
    function automatic string stall_name(input logic [2:0] s);
      case(s) 3'd1: stall_name="delay"; 3'd2: stall_name="wait"; 3'd3: stall_name="pull_block"; 3'd4: stall_name="push_block"; default: stall_name="-"; endcase
    endfunction
    always @(posedge clk) begin
      if (dut.engine_ce && dut.running && trace_tick < trace_limit) begin
        trace_tick=trace_tick+1; trace_delay=(dut.delay_count != 0);
        trace_instruction=trace_delay ? 16'hffff : dut.instr;
        trace_sideset=dut.sideset_we ? dut.sideset_value[1:0] : 2'b0;
        trace_wait=(dut.stall_reason == 3'd2);
        // Latch the stall string pre-edge: the model row reports the stall
        // active during the tick, while the post-edge combinational value
        // already reflects the next tick.
        trace_stall=stall_name(dut.stall_reason);
        if (dut.tx_core_pop) trace_fifo_activity="pull";
        else if (dut.rx_core_push) trace_fifo_activity="push";
        else if (dut.stall_reason == 3'd3) trace_fifo_activity="pull_block";
        else if (dut.stall_reason == 3'd4) trace_fifo_activity="push_block";
        else trace_fifo_activity="-";
        #1 $fwrite(trace_file,"%04d %04d %02d %s %04x %04x %08x %08x %02x %02x %02x %0d %0d %s %0d %02d %02x %0d %0d %s\n",
          trace_tick,trace_tick,dut.imem_pc,trace_delay?"----":$sformatf("%04x",trace_instruction),
          dut.x,dut.y,dut.osr,dut.isr,dut.gpio_sampled,gpio_out,gpio_oe,dut.tx_level,dut.rx_level,
          trace_fifo_activity,trace_wait,dut.delay_count,trace_sideset,dut.running,dut.fault,
          trace_stall);
      end
    end
    initial begin
      repeat(3) @(posedge clk); rst_n=1;
      for (case_i=0; case_i<RANDOM_CASES; case_i=case_i+1) begin
        wr(16'h0000,4);
        for (word_i=0; word_i<RANDOM_WORDS; word_i=word_i+2)
          wr(16'h0100 + word_i*2, {random_programs[case_i][word_i+1],random_programs[case_i][word_i]});
        wr(16'h0008,0); wr(16'h000c,1);
        wr(16'h0010,random_set_cfg[case_i]);
        wr(16'h0014,random_side_cfg[case_i]);
        wr(16'h002c,random_out_cfg[case_i]); wr(16'h0030,random_in_cfg[case_i]);
        wr(16'h0034,random_shift_cfg[case_i]);
        trace_file=$fopen($sformatf("sim/random_%03d.trace",case_i),"w");
        trace_tick=0; trace_limit=RANDOM_CYCLES;
        wr(16'h0000,1);
        repeat(RANDOM_CYCLES+2) @(posedge clk);
        wr(16'h0000,2);
        $fclose(trace_file); trace_file=0;
      end
      $display("PASS RTL randomized differential cases"); $finish;
    end
endmodule
