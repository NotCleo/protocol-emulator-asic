`timescale 1ns/1ps
module tb_clkdiv;
  logic clk=0,rst_n=0,soft_reset=0,enable=0;
  logic [15:0] div;
  logic ce;
  integer n, cyc, events, last, delta;
  always #5 clk=~clk;
  pe_clkdiv dut(.clk_i(clk),.rst_ni(rst_n),.soft_reset_i(soft_reset),.enable_i(enable),.clkdiv_i(div),.engine_ce_o(ce));
  task automatic check(input logic c,input string m); if(!c) $fatal(1,"FAIL %s divisor=%0d cycle=%0d",m,n,cyc); endtask
  initial begin
    repeat(2) @(posedge clk); rst_n=1;
    for (n=1;n<=15;n=n+1) begin
      if (!(n==1 || n==2 || n==3 || n==4 || n==15)) continue;
      div=n; enable=0; soft_reset=1; @(posedge clk); soft_reset=0; enable=1;
      events=0; last=-1; cyc=0;
      while(events<6 && cyc<200) begin
        @(posedge clk); cyc=cyc+1;
        if (ce) begin
          if (last>=0) begin delta=cyc-last; check(delta==n,"engine_ce spacing"); end
          last=cyc; events=events+1;
        end
      end
      check(events==6,"engine_ce event count");
    end
    $display("PASS clock divider divisors 1,2,3,4,15"); $finish;
  end
endmodule
