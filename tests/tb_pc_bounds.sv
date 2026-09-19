`timescale 1ns/1ps
module tb_pc_bounds;
    logic clk=0,rst_n=0,host_valid=0,host_write=0;
    logic [15:0] host_addr=0; logic [31:0] host_wdata=0; logic [3:0] host_wstrb=0;
    logic [31:0] host_rdata; logic host_ready; logic [7:0] gpio_in=0,gpio_out,gpio_oe;
    always #5 clk=~clk;
    protocol_emulator_top #(.IMEM_DEPTH(128)) dut(
      .clk_i(clk),.rst_ni(rst_n),.host_valid_i(host_valid),.host_write_i(host_write),
      .host_addr_i(host_addr),.host_wdata_i(host_wdata),.host_wstrb_i(host_wstrb),
      .host_rdata_o(host_rdata),.host_ready_o(host_ready),.gpio_in_i(gpio_in),
      .gpio_out_o(gpio_out),.gpio_oe_o(gpio_oe));
    task automatic wr(input logic [15:0] a,input logic [31:0] d);
      begin @(negedge clk); host_valid=1;host_write=1;host_addr=a;host_wdata=d;host_wstrb=4'hf;
      @(negedge clk); host_valid=0;host_write=0;host_addr=0;host_wdata=0;host_wstrb=0; end
    endtask
    initial begin
      repeat(3) @(posedge clk); rst_n=1;
      wr(16'h01fc,32'he820_0000); // upper half: instruction 127 = SET X,1
      wr(16'h0008,127); wr(16'h000c,1); wr(16'h0000,1);
      repeat(3) @(posedge clk); #1;
      if (!(dut.imem_pc == 7'd127 && dut.x == 16'd1 && dut.fault && !dut.running))
        $fatal(1,"FAIL parameterized 128-word PC end fault pc=%0d x=%0d fault=%0d run=%0d",dut.imem_pc,dut.x,dut.fault,dut.running);
      $display("PASS parameterized 128-word PC width and end fault"); $finish;
    end
endmodule
