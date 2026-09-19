module protocol_emulator_top #(
    parameter int IMEM_DEPTH = 64,
    parameter int N_PINS = 8,
    parameter int FIFO_DEPTH = 4
) (
    input logic clk_i, input logic rst_ni,
    input logic host_valid_i, input logic host_write_i,
    input logic [15:0] host_addr_i, input logic [31:0] host_wdata_i,
    input logic [3:0] host_wstrb_i,
    output logic [31:0] host_rdata_o, output logic host_ready_o,
    input logic [N_PINS-1:0] gpio_in_i,
    output logic [N_PINS-1:0] gpio_out_o, output logic [N_PINS-1:0] gpio_oe_o,
    // Canonical management bus. The legacy host_* ports are an internal
    // verification adapter into this same transaction path.
    input logic mgmt_valid_i, input logic mgmt_write_i,
    input logic [15:0] mgmt_addr_i, input logic [31:0] mgmt_wdata_i,
    input logic [3:0] mgmt_wstrb_i,
    output logic mgmt_ready_o, output logic [31:0] mgmt_rdata_o,
    output logic mgmt_error_o
);
    localparam int PC_W = $clog2(IMEM_DEPTH);
    localparam int PIN_W = $clog2(N_PINS);
    localparam int HOST_W = $clog2(IMEM_DEPTH/2);
    localparam int FIFO_LEVEL_W = $clog2(FIFO_DEPTH+1);

    logic run_cmd, halt_cmd, soft_reset_cmd, imem_write_fault, config_fault;
    logic bus_valid, bus_write, bus_error, bus_ready;
    logic [15:0] bus_addr;
    logic [31:0] bus_wdata, bus_rdata;
    logic [3:0] bus_wstrb;
    logic mgmt_selected;
    logic imem_we;
    logic [HOST_W-1:0] imem_word_addr;
    logic [31:0] imem_wdata, imem_host_rdata;
    logic [3:0] imem_wstrb;
    logic [15:0] start_pc, clkdiv;
    logic [PIN_W-1:0] set_base, sideset_base, out_base, in_base;
    logic [1:0] sideset_count, shift_cfg;
    logic [15:0] x, y;
    logic [31:0] osr, isr;
    logic [4:0] delay_count;
    logic [5:0] osr_count, isr_count;
    logic [2:0] stall_reason;
    logic running, fault, engine_ce;
    logic [PC_W-1:0] imem_pc;
    logic [15:0] instr;

    logic [N_PINS-1:0] gpio_sampled, rising, falling;
    // Select the canonical management transaction when it is asserted.
    // Case equality keeps legacy verification benches, which omit the new
    // ports, on the original direct host path rather than propagating X.
    always_comb begin
        mgmt_selected = (mgmt_valid_i === 1'b1);
        bus_valid = mgmt_selected ? mgmt_valid_i : host_valid_i;
        bus_write = mgmt_selected ? mgmt_write_i : host_write_i;
        bus_addr = mgmt_selected ? mgmt_addr_i : host_addr_i;
        bus_wdata = mgmt_selected ? mgmt_wdata_i : host_wdata_i;
        bus_wstrb = mgmt_selected ? mgmt_wstrb_i : host_wstrb_i;

        host_rdata_o = bus_rdata;
        host_ready_o = bus_ready;
        mgmt_rdata_o = bus_rdata;
        mgmt_ready_o = bus_ready;
        mgmt_error_o = bus_error;
    end

    logic [31:0] tx_data, rx_data;
    logic tx_empty, tx_full, rx_empty, rx_full;
    logic [FIFO_LEVEL_W-1:0] tx_level, rx_level;
    logic tx_host_push, tx_core_pop, rx_host_pop, rx_core_push;
    logic [31:0] tx_host_data, rx_core_data;
    logic io_event, set_pins_we, set_oe_we, out_pins_we, sideset_we;
    logic [N_PINS-1:0] set_pins_value, set_oe_value, out_pins_value, sideset_value;
    logic [5:0] out_pins_count;

    pe_sync #(.N_PINS(N_PINS)) gpio_sync (
        .clk_i(clk_i), .rst_ni(rst_ni), .async_i(gpio_in_i),
        .sampled_o(gpio_sampled), .rising_o(rising), .falling_o(falling)
    );

    pe_host_if #(.IMEM_DEPTH(IMEM_DEPTH), .N_PINS(N_PINS)) host_if (
        .clk_i(clk_i), .rst_ni(rst_ni), .host_valid_i(bus_valid),
        .host_write_i(bus_write), .host_addr_i(bus_addr),
        .host_wdata_i(bus_wdata), .host_wstrb_i(bus_wstrb),
        .host_rdata_o(bus_rdata), .host_ready_o(bus_ready), .host_error_o(bus_error),
        .running_i(running), .fault_i(fault), .pc_i(imem_pc), .x_i(x), .y_i(y),
        .osr_i(osr), .isr_i(isr), .delay_count_i(delay_count), .gpio_in_i(gpio_sampled),
        .tx_empty_i(tx_empty), .tx_full_i(tx_full), .rx_empty_i(rx_empty),
        .rx_full_i(rx_full), .tx_level_i(tx_level), .rx_level_i(rx_level),
        .rx_data_i(rx_data), .imem_host_rdata_i(imem_host_rdata),
        .run_cmd_o(run_cmd), .halt_cmd_o(halt_cmd), .soft_reset_cmd_o(soft_reset_cmd),
        .imem_write_fault_o(imem_write_fault), .imem_we_o(imem_we),
        .imem_word_addr_o(imem_word_addr), .imem_wdata_o(imem_wdata),
        .imem_wstrb_o(imem_wstrb), .start_pc_o(start_pc), .clkdiv_o(clkdiv),
        .set_base_o(set_base), .sideset_base_o(sideset_base),
        .sideset_count_o(sideset_count), .out_base_o(out_base), .in_base_o(in_base),
        .shift_cfg_o(shift_cfg), .config_fault_o(config_fault),
        .tx_host_push_o(tx_host_push), .tx_host_data_o(tx_host_data),
        .rx_host_pop_o(rx_host_pop)
    );

    pe_imem #(.IMEM_DEPTH(IMEM_DEPTH)) imem (
        .clk_i(clk_i), .rst_ni(rst_ni), .pc_i(imem_pc), .instr_o(instr),
        .host_we_i(imem_we), .host_word_addr_i(imem_word_addr),
        .host_wdata_i(imem_wdata), .host_wstrb_i(imem_wstrb),
        .host_rdata_o(imem_host_rdata)
    );

    pe_fifo #(.WIDTH(32), .DEPTH(FIFO_DEPTH)) tx_fifo (
        .clk_i(clk_i), .rst_ni(rst_ni), .soft_reset_i(soft_reset_cmd), .push_i(tx_host_push), .pop_i(tx_core_pop),
        .push_data_i(tx_host_data), .pop_data_o(tx_data), .empty_o(tx_empty),
        .full_o(tx_full), .level_o(tx_level)
    );
    pe_fifo #(.WIDTH(32), .DEPTH(FIFO_DEPTH)) rx_fifo (
        .clk_i(clk_i), .rst_ni(rst_ni), .soft_reset_i(soft_reset_cmd), .push_i(rx_core_push), .pop_i(rx_host_pop),
        .push_data_i(rx_core_data), .pop_data_o(rx_data), .empty_o(rx_empty),
        .full_o(rx_full), .level_o(rx_level)
    );

    pe_clkdiv clkdiv_unit (
        .clk_i(clk_i), .rst_ni(rst_ni), .soft_reset_i(soft_reset_cmd),
        .enable_i(running), .clkdiv_i(clkdiv), .engine_ce_o(engine_ce)
    );

    pe_core #(.IMEM_DEPTH(IMEM_DEPTH), .N_PINS(N_PINS)) core (
        .clk_i(clk_i), .rst_ni(rst_ni), .soft_reset_i(soft_reset_cmd),
        .run_cmd_i(run_cmd), .halt_cmd_i(halt_cmd),
        .imem_write_fault_i(imem_write_fault), .config_fault_i(config_fault),
        .engine_ce_i(engine_ce), .start_pc_i(start_pc), .imem_instr_addr_o(imem_pc),
        .instr_i(instr), .set_base_i(set_base), .sideset_base_i(sideset_base),
        .out_base_i(out_base), .in_base_i(in_base), .sideset_count_i(sideset_count),
        .shift_cfg_i(shift_cfg), .gpio_in_i(gpio_sampled), .rising_i(rising),
        .falling_i(falling), .tx_empty_i(tx_empty), .rx_full_i(rx_full),
        .tx_data_i(tx_data), .tx_pop_o(tx_core_pop), .rx_push_o(rx_core_push),
        .rx_data_o(rx_core_data), .running_o(running), .fault_o(fault),
        .pc_o(), .x_o(x), .y_o(y), .osr_o(osr), .isr_o(isr),
        .delay_count_o(delay_count), .osr_count_o(osr_count),
        .isr_count_o(isr_count), .stall_reason_o(stall_reason),
        .io_event_o(io_event), .set_pins_we_o(set_pins_we),
        .set_pins_value_o(set_pins_value), .set_oe_we_o(set_oe_we),
        .set_oe_value_o(set_oe_value), .out_pins_we_o(out_pins_we),
        .out_pins_value_o(out_pins_value), .out_pins_count_o(out_pins_count),
        .sideset_we_o(sideset_we), .sideset_value_o(sideset_value)
    );

    pe_io #(.N_PINS(N_PINS)) io (
        .clk_i(clk_i), .rst_ni(rst_ni), .soft_reset_i(soft_reset_cmd),
        .event_i(io_event), .set_pins_we_i(set_pins_we),
        .set_pins_value_i(set_pins_value), .set_oe_we_i(set_oe_we),
        .set_oe_value_i(set_oe_value), .set_base_i(set_base),
        .out_pins_we_i(out_pins_we), .out_pins_value_i(out_pins_value),
        .out_pins_count_i(out_pins_count), .out_base_i(out_base),
        .sideset_we_i(sideset_we), .sideset_value_i(sideset_value),
        .sideset_base_i(sideset_base), .sideset_count_i(sideset_count),
        .gpio_out_o(gpio_out_o), .gpio_oe_o(gpio_oe_o)
    );
endmodule
