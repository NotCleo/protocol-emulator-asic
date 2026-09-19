// Command-to-transaction adapter. The SPI frontend emits complete generic
// register transactions; this module is intentionally a one-to-one bridge to
// the canonical management bus.
module host_cmd_if (
    input  logic        cmd_valid_i,
    input  logic        cmd_write_i,
    input  logic [15:0] cmd_addr_i,
    input  logic [31:0] cmd_wdata_i,
    input  logic [3:0]  cmd_wstrb_i,
    output logic        cmd_ready_o,
    output logic [31:0] cmd_rdata_o,
    output logic        cmd_error_o,
    output logic        mgmt_valid_o,
    output logic        mgmt_write_o,
    output logic [15:0] mgmt_addr_o,
    output logic [31:0] mgmt_wdata_o,
    output logic [3:0]  mgmt_wstrb_o,
    input  logic        mgmt_ready_i,
    input  logic [31:0] mgmt_rdata_i,
    input  logic        mgmt_error_i
);
    always_comb begin
        cmd_ready_o = mgmt_ready_i;
        cmd_rdata_o = mgmt_rdata_i;
        cmd_error_o = mgmt_error_i;
        mgmt_valid_o = cmd_valid_i;
        mgmt_write_o = cmd_write_i;
        mgmt_addr_o = cmd_addr_i;
        mgmt_wdata_o = cmd_wdata_i;
        mgmt_wstrb_o = cmd_wstrb_i;
    end
endmodule
