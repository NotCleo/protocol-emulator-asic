`timescale 1ns/1ps
module tb_milestone13;
    logic clk=0, rst_n=0, host_valid=0, host_write=0;
    logic [15:0] host_addr=0; logic [31:0] host_wdata=0; logic [3:0] host_wstrb=0;
    logic [31:0] host_rdata; logic host_ready; logic [7:0] gpio_in=0, gpio_out, gpio_oe;
    always #5 clk = ~clk;
    protocol_emulator_top dut (
        .clk_i(clk), .rst_ni(rst_n), .host_valid_i(host_valid), .host_write_i(host_write),
        .host_addr_i(host_addr), .host_wdata_i(host_wdata), .host_wstrb_i(host_wstrb),
        .host_rdata_o(host_rdata), .host_ready_o(host_ready), .gpio_in_i(gpio_in),
        .gpio_out_o(gpio_out), .gpio_oe_o(gpio_oe));

    task automatic wr(input logic [15:0] a, input logic [31:0] d);
        begin @(negedge clk); host_valid=1; host_write=1; host_addr=a; host_wdata=d; host_wstrb=4'hf;
        @(negedge clk); host_valid=0; host_write=0; host_addr=0; host_wdata=0; host_wstrb=0; end
    endtask
    task automatic rd(input logic [15:0] a, output logic [31:0] d);
        begin @(negedge clk); host_valid=1; host_write=0; host_addr=a; #1 d=host_rdata;
        @(negedge clk); host_valid=0; host_addr=0; end
    endtask
    task automatic check(input logic c, input string m); begin if (!c) $fatal(1,"FAIL %s",m); end endtask
    task automatic reset_engine; begin wr(16'h0000,32'd4); gpio_in=0; repeat(2) @(posedge clk); end endtask
    task automatic load2(input logic [15:0] a, input logic [15:0] lo, input logic [15:0] hi);
        begin wr(a,{hi,lo}); end
    endtask
    logic [31:0] rddata;
    initial begin
        repeat(3) @(posedge clk); rst_n=1;
        // IN PINS,8 with the default left-accumulating ISR direction.
        load2(16'h0100,16'h4100,16'ha600); // in pins,8; mov x,isr
        load2(16'h0104,16'h0000,16'h0000);
        wr(16'h0030,0); wr(16'h0034,0); wr(16'h0008,0); wr(16'h000c,1);
        gpio_in=8'ha5; repeat(4) @(posedge clk); wr(16'h0000,1); repeat(3) @(posedge clk); #1;
        wr(16'h0000,2);
        rd(16'h0044,rddata); check(rddata==32'ha5,"IN GPIO / ISR");
        rd(16'h0038,rddata); check(rddata[15:0]==16'ha5,"MOV ISR to X");
        reset_engine;

        // OUT PINS,8 after a blocking PULL, plus output enable.
        load2(16'h0100,16'h8800,16'h6100); // pull block; out pins,8
        load2(16'h0104,16'he7e0,16'h0000); // set pindirs,31; loop
        wr(16'h0010,0); wr(16'h0034,2); wr(16'h0018,32'h000000a5); wr(16'h0008,0); wr(16'h0000,1);
        repeat(5) @(posedge clk); #1; check(gpio_out[7:0]==8'ha5,"OUT GPIO"); check(gpio_oe[4:0]==5'h1f,"PINDIRS");
        wr(16'h0000,2); reset_engine;

        // Blocking PULL holds PC until host data arrives.
        load2(16'h0100,16'h8800,16'h0000); wr(16'h0008,0); wr(16'h0000,1);
        repeat(3) @(posedge clk); #1; check(dut.imem_pc==0,"PULL stall PC");
        wr(16'h0018,32'h12345678); @(posedge clk); #1; check(dut.imem_pc==1,"PULL resumes");
        rd(16'h0040,rddata); check(rddata==32'h12345678,"PULL OSR");
        wr(16'h0000,2); reset_engine;

        // Blocking PUSH stores ISR into RX FIFO; host read pops it.
        load2(16'h0100,16'h4100,16'h9800); load2(16'h0104,16'h0000,16'h0000);
        gpio_in=8'h3c; repeat(4) @(posedge clk); wr(16'h0008,0); wr(16'h0000,1);
        repeat(4) @(posedge clk); rd(16'h001c,rddata); check(rddata[7:0]==8'h3c,"PUSH RX data");
        wr(16'h0000,2); reset_engine;

        // WAIT observes the synchronized GPIO input and resumes once.
        load2(16'h0100,16'h2010,16'he820); // wait pin_high,0 side 1; set x,1
        wr(16'h0014,32'h0000_0101); // side-set base=1,count=1
        gpio_in=8'h00; wr(16'h0008,0); wr(16'h0000,1);
        repeat(4) @(posedge clk); #1;
        check(dut.imem_pc==0 && dut.x==0 && !gpio_out[1],"WAIT blocks");
        gpio_in=8'h01; repeat(3) @(posedge clk); #1;
        check(dut.imem_pc==1 && gpio_out[1],"WAIT resumes with side-set");
        @(posedge clk); #1; check(dut.x==1,"WAIT successor executes once");
        wr(16'h0000,2); reset_engine;

        // TX full and RX full status/edge conditions.
        wr(16'h0018,1); wr(16'h0018,2); wr(16'h0018,3); wr(16'h0018,4); wr(16'h0018,5);
        rd(16'h0020,rddata); check(rddata[1] && rddata[7:4]==4,"TX full");
        wr(16'h0000,4); reset_engine;
        load2(16'h0100,16'h4100,16'h9800); gpio_in=8'h55; repeat(4) @(posedge clk); wr(16'h0008,0); wr(16'h0000,1);
        repeat(20) @(posedge clk); rd(16'h0020,rddata); check(rddata[3],"RX full");
        $display("PASS M1.1-M1.3 directed RTL tests"); $finish;
    end
endmodule
