`timescale 1ns/1ps
module tb_fifo_stress;
    logic clk=0, rst_n=0, soft_reset=0, push=0, pop=0;
    logic [31:0] push_data=0, pop_data;
    logic empty, full;
    logic [2:0] level;
    integer i, head, tail, count;
    logic [31:0] model [0:3];
    logic [31:0] expected_pop;
    logic [31:0] rnd;
    always #5 clk=~clk;
    pe_fifo #(.WIDTH(32),.DEPTH(4)) dut(
        .clk_i(clk),.rst_ni(rst_n),.soft_reset_i(soft_reset),
        .push_i(push),.pop_i(pop),.push_data_i(push_data),.pop_data_o(pop_data),
        .empty_o(empty),.full_o(full),.level_o(level));
    task automatic check(input logic c, input string m);
        if (!c) $fatal(1,"FAIL %s at iteration %0d level=%0d",m,i,level);
    endtask
    initial begin
        repeat(2) @(posedge clk); rst_n=1; head=0; tail=0; count=0;
        for (i=0; i<100000; i=i+1) begin
            @(negedge clk);
            rnd = 32'h9e3779b9 ^ (i * 32'h45d9f3b);
            push = rnd[0]; pop = rnd[1]; push_data = rnd ^ i;
            expected_pop = (count != 0) ? model[head] : 0;
            @(posedge clk); #1;
            if (pop && count != 0) begin
                if (head == 3) head=0; else head=head+1;
                count=count-1;
            end
            if (push && count < 4) begin
                model[tail]=push_data;
                if (tail == 3) tail=0; else tail=tail+1;
                count=count+1;
            end
            check(level == count, "FIFO level");
            check(empty == (count==0), "FIFO empty");
            check(full == (count==4), "FIFO full");
            if (count != 0) check(pop_data == model[head], "FIFO head");
        end
        $display("PASS RTL FIFO randomized 100000 operations");
        $finish;
    end
endmodule
