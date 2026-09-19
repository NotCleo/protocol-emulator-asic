`timescale 1ns/1ps
module tb_mgmt_spi;
    logic [7:0] ui_in = 8'b0000_0100; // CS high, SCLK low, MOSI low
    wire [7:0] uo_out;
    logic [7:0] uio_in = 0;
    wire [7:0] uio_out, uio_oe;
    logic ena = 1;
    logic clk = 0, rst_n = 0;
    integer phase_delay = 0;

    always #10 clk = ~clk; // nominal 50 MHz system clock

    tt_um_protocol_emulator dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
        .uio_out(uio_out), .uio_oe(uio_oe), .ena(ena),
        .clk(clk), .rst_n(rst_n)
    );

    task automatic spi_begin;
        begin
            ui_in[1] = 1'b0;
            ui_in[2] = 1'b0;
            #(400);
        end
    endtask

    task automatic spi_end;
        begin
            ui_in[1] = 1'b0;
            ui_in[2] = 1'b1;
            #(400);
        end
    endtask

    task automatic spi_write_byte(input logic [7:0] value);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                ui_in[0] = value[i];
                #(80 + phase_delay);
                ui_in[1] = 1'b1;
                #(80);
                ui_in[1] = 1'b0;
                #(80);
            end
        end
    endtask

    task automatic spi_read_byte(output logic [7:0] value);
        integer i;
        begin
            value = 0;
            for (i = 7; i >= 0; i = i - 1) begin
                ui_in[0] = 1'b0;
                #(80 + phase_delay);
                ui_in[1] = 1'b1;
                #(40);
                value[i] = uo_out[0];
                #(40);
                ui_in[1] = 1'b0;
                #(80);
            end
        end
    endtask

    task automatic spi_write32(input logic [15:0] address, input logic [31:0] data);
        begin
            spi_begin; spi_write_byte(8'h01);
            spi_write_byte(address[15:8]); spi_write_byte(address[7:0]);
            spi_write_byte(data[31:24]); spi_write_byte(data[23:16]);
            spi_write_byte(data[15:8]); spi_write_byte(data[7:0]); spi_end;
        end
    endtask

    task automatic spi_read32(input logic [15:0] address, output logic [31:0] data);
        logic [7:0] b0, b1, b2, b3;
        begin
            spi_begin; spi_write_byte(8'h02);
            spi_write_byte(address[15:8]); spi_write_byte(address[7:0]);
            spi_read_byte(b0); spi_read_byte(b1); spi_read_byte(b2); spi_read_byte(b3);
            spi_end;
            data = {b0,b1,b2,b3};
        end
    endtask

    task automatic spi_burst_write2(input logic [15:0] address,
                                     input logic [31:0] word0,
                                     input logic [31:0] word1);
        begin
            spi_begin; spi_write_byte(8'h03);
            spi_write_byte(address[15:8]); spi_write_byte(address[7:0]);
            spi_write_byte(8'd2);
            spi_write_byte(word0[31:24]); spi_write_byte(word0[23:16]);
            spi_write_byte(word0[15:8]); spi_write_byte(word0[7:0]);
            spi_write_byte(word1[31:24]); spi_write_byte(word1[23:16]);
            spi_write_byte(word1[15:8]); spi_write_byte(word1[7:0]);
            spi_end;
        end
    endtask

    task automatic spi_burst_read2(input logic [15:0] address,
                                    output logic [31:0] word0,
                                    output logic [31:0] word1);
        logic [7:0] b0, b1, b2, b3;
        begin
            spi_begin; spi_write_byte(8'h04);
            spi_write_byte(address[15:8]); spi_write_byte(address[7:0]);
            spi_write_byte(8'd2);
            spi_read_byte(b0); spi_read_byte(b1); spi_read_byte(b2); spi_read_byte(b3);
            word0 = {b0,b1,b2,b3};
            spi_read_byte(b0); spi_read_byte(b1); spi_read_byte(b2); spi_read_byte(b3);
            word1 = {b0,b1,b2,b3};
            spi_end;
        end
    endtask

    task automatic spi_unknown_command;
        begin
            spi_begin; spi_write_byte(8'h99); spi_end;
        end
    endtask

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) $fatal(1, "FAIL: %s at time %0t", message, $time);
        end
    endtask

    logic [31:0] read_data, read_data2;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        check(uio_oe == 8'h00, "reset leaves protocol pins high impedance");

        // Status reads at deliberately different CFG_SCLK/clk phase offsets.
        phase_delay = 0;  spi_read32(16'h0004, read_data);
        check(read_data[0] == 1'b0, "status stopped at phase 0");
        phase_delay = 7;  spi_read32(16'h0004, read_data);
        check(read_data[0] == 1'b0, "status stopped at phase 7");
        phase_delay = 13; spi_read32(16'h0004, read_data);
        check(read_data[0] == 1'b0, "status stopped at phase 13");
        phase_delay = 19; spi_read32(16'h0004, read_data);
        check(read_data[0] == 1'b0, "status stopped at phase 19");

        // Exact gpio_toggle.pasm image: e420, e021, e001, 0010.
        phase_delay = 13;
        spi_burst_write2(16'h0100, 32'he021_e420, 32'h0010_e001);
        spi_read32(16'h0100, read_data);
        check(read_data == 32'he021_e420, "burst IMEM word 0 readback");
        spi_read32(16'h0104, read_data);
        check(read_data == 32'h0010_e001, "burst IMEM word 1 readback");
        spi_burst_read2(16'h0100, read_data, read_data2);
        check(read_data == 32'he021_e420 && read_data2 == 32'h0010_e001, "burst IMEM read");
        spi_unknown_command;
        spi_read32(16'h0004, read_data);
        check(read_data[0] == 1'b0, "malformed command recovery");
        spi_write32(16'h0004, 32'hffff_ffff);
        spi_read32(16'h0004, read_data);
        check(read_data[0] == 1'b0 && read_data[1] == 1'b0, "read-only CSR protection");
        spi_read32(16'h00f0, read_data);
        check(read_data == 32'hdead_beef, "invalid address response");

        spi_write32(16'h000c, 32'd1); // CLKDIV
        spi_write32(16'h0008, 32'd0); // START_PC
        spi_write32(16'h0000, 32'd1); // CTRL.RUN
        repeat (80) @(posedge clk);
        check(uio_oe[0] == 1'b1, "GPIO0 enabled by loaded program");
        check(uio_out[0] !== 1'bx, "GPIO0 has a defined output");
        spi_read32(16'h0004, read_data);
        check(read_data[0] == 1'b1, "status running after SPI RUN");

        spi_write32(16'h0100, 32'h0000_0000);
        repeat (5) @(posedge clk);
        spi_read32(16'h0004, read_data);
        check(read_data[0] == 1'b0 && read_data[1] == 1'b1, "running IMEM write faults and halts");
        spi_write32(16'h0000, 32'd4); // CTRL.SOFT_RESET
        spi_burst_write2(16'h0100, 32'he8e0_8800, 32'he003_e420);
        spi_burst_write2(16'h0108, 32'h0840_6023, 32'h0000_e023);
        spi_write32(16'h0018, 32'h0000_0000); // TX_DATA
        spi_write32(16'h0008, 32'd0);
        spi_write32(16'h0000, 32'd1); // CTRL.RUN
        repeat (8) @(posedge clk);
        check(uio_oe[0] == 1'b1 && uio_out[0] == 1'b0, "UART microcode starts a low frame");
        spi_write32(16'h0000, 32'd2); // CTRL.HALT
        repeat (5) @(posedge clk);
        check(uio_oe[0] == 1'b1, "HALT preserves GPIO OE");
        $display("PASS management SPI phase, burst-load, register, and GPIO tests");
        $finish;
    end
endmodule
