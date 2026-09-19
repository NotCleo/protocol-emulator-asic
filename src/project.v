/* Tiny Tapeout CMOS5L top-level wrapper. */
`default_nettype none

module tt_um_protocol_emulator (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // The physical management pins are sampled into clk by cfg_spi_slave.
    wire cfg_miso;
    wire cmd_valid, cmd_write, cmd_ready, cmd_error;
    wire [15:0] cmd_addr;
    wire [31:0] cmd_wdata, cmd_rdata;
    wire [3:0] cmd_wstrb;

    wire mgmt_valid, mgmt_write, mgmt_ready, mgmt_error;
    wire [15:0] mgmt_addr;
    wire [31:0] mgmt_wdata, mgmt_rdata;
    wire [3:0] mgmt_wstrb;

    wire target_valid, target_write, target_ready, target_error;
    wire [15:0] target_addr;
    wire [31:0] target_wdata, target_rdata;
    wire [3:0] target_wstrb;

    cfg_spi_slave cfg_spi (
        .clk_i(clk), .rst_ni(rst_n),
        .cfg_mosi(ui_in[0]), .cfg_sclk(ui_in[1]), .cfg_cs_n(ui_in[2]),
        .cfg_miso(cfg_miso),
        .cmd_valid_o(cmd_valid), .cmd_write_o(cmd_write),
        .cmd_addr_o(cmd_addr), .cmd_wdata_o(cmd_wdata),
        .cmd_wstrb_o(cmd_wstrb), .cmd_ready_i(cmd_ready),
        .cmd_rdata_i(cmd_rdata), .cmd_error_i(cmd_error)
    );

    host_cmd_if cmd_bridge (
        .cmd_valid_i(cmd_valid), .cmd_write_i(cmd_write),
        .cmd_addr_i(cmd_addr), .cmd_wdata_i(cmd_wdata),
        .cmd_wstrb_i(cmd_wstrb), .cmd_ready_o(cmd_ready),
        .cmd_rdata_o(cmd_rdata), .cmd_error_o(cmd_error),
        .mgmt_valid_o(mgmt_valid), .mgmt_write_o(mgmt_write),
        .mgmt_addr_o(mgmt_addr), .mgmt_wdata_o(mgmt_wdata),
        .mgmt_wstrb_o(mgmt_wstrb), .mgmt_ready_i(mgmt_ready),
        .mgmt_rdata_i(mgmt_rdata), .mgmt_error_i(mgmt_error)
    );

    management_decode mgmt_decode (
        .mgmt_valid_i(mgmt_valid), .mgmt_write_i(mgmt_write),
        .mgmt_addr_i(mgmt_addr), .mgmt_wdata_i(mgmt_wdata),
        .mgmt_wstrb_i(mgmt_wstrb), .mgmt_ready_o(mgmt_ready),
        .mgmt_rdata_o(mgmt_rdata), .mgmt_error_o(mgmt_error),
        .target_valid_o(target_valid), .target_write_o(target_write),
        .target_addr_o(target_addr), .target_wdata_o(target_wdata),
        .target_wstrb_o(target_wstrb), .target_ready_i(target_ready),
        .target_rdata_i(target_rdata), .target_error_i(target_error)
    );

    protocol_emulator_top engine (
        .clk_i(clk), .rst_ni(rst_n),
        // The legacy host adapter is retained for direct RTL verification;
        // the physical chip uses only the canonical management bus below.
        .host_valid_i(1'b0), .host_write_i(1'b0),
        .host_addr_i(16'b0), .host_wdata_i(32'b0),
        .host_wstrb_i(4'b0), .host_rdata_o(), .host_ready_o(),
        .mgmt_valid_i(target_valid), .mgmt_write_i(target_write),
        .mgmt_addr_i(target_addr), .mgmt_wdata_i(target_wdata),
        .mgmt_wstrb_i(target_wstrb), .mgmt_ready_o(target_ready),
        .mgmt_rdata_o(target_rdata), .mgmt_error_o(target_error),
        .gpio_in_i(uio_in), .gpio_out_o(uio_out), .gpio_oe_o(uio_oe)
    );

    assign uo_out[0] = cfg_miso;
    assign uo_out[1] = 1'b0;
    assign uo_out[7:2] = 6'b0;

    wire _unused = &{ena, ui_in[7:3]};
endmodule

`default_nettype wire
