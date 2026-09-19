// Canonical management-bus boundary. Address ownership and side effects live
// in the single pe_host_if target inside protocol_emulator_top; this module
// provides the named integration boundary without duplicating storage/decode.
module management_decode (
    input  logic        mgmt_valid_i,
    input  logic        mgmt_write_i,
    input  logic [15:0] mgmt_addr_i,
    input  logic [31:0] mgmt_wdata_i,
    input  logic [3:0]  mgmt_wstrb_i,
    output logic        mgmt_ready_o,
    output logic [31:0] mgmt_rdata_o,
    output logic        mgmt_error_o,
    output logic        target_valid_o,
    output logic        target_write_o,
    output logic [15:0] target_addr_o,
    output logic [31:0] target_wdata_o,
    output logic [3:0]  target_wstrb_o,
    input  logic        target_ready_i,
    input  logic [31:0] target_rdata_i,
    input  logic        target_error_i
);
    always_comb begin
        target_valid_o = mgmt_valid_i;
        target_write_o = mgmt_write_i;
        target_addr_o = mgmt_addr_i;
        target_wdata_o = mgmt_wdata_i;
        target_wstrb_o = mgmt_wstrb_i;
        mgmt_ready_o = target_ready_i;
        mgmt_rdata_o = target_rdata_i;
        mgmt_error_o = target_error_i;
    end
endmodule
