// Canonical synchronous management-bus target for the execution plane.
// The legacy host_* port names are retained only because the internal
// verification harness drives this same transaction interface directly.
module pe_host_if #(
    parameter int IMEM_DEPTH = 64,
    parameter int N_PINS = 8
) (
    input  logic clk_i, input logic rst_ni,
    input  logic host_valid_i, input logic host_write_i,
    input  logic [15:0] host_addr_i, input logic [31:0] host_wdata_i,
    input logic [3:0] host_wstrb_i,
    output logic [31:0] host_rdata_o, output logic host_ready_o,
    output logic host_error_o,
    input logic running_i, input logic fault_i,
    input logic [$clog2(IMEM_DEPTH)-1:0] pc_i,
    input logic [15:0] x_i, input logic [15:0] y_i,
    input logic [31:0] osr_i, input logic [31:0] isr_i,
    input logic [4:0] delay_count_i,
    input logic [N_PINS-1:0] gpio_in_i,
    input logic tx_empty_i, input logic tx_full_i,
    input logic rx_empty_i, input logic rx_full_i,
    input logic [2:0] tx_level_i, input logic [2:0] rx_level_i,
    input logic [31:0] rx_data_i,
    input logic [31:0] imem_host_rdata_i,
    output logic run_cmd_o, output logic halt_cmd_o, output logic soft_reset_cmd_o,
    output logic imem_write_fault_o, output logic imem_we_o,
    output logic [$clog2(IMEM_DEPTH/2)-1:0] imem_word_addr_o,
    output logic [31:0] imem_wdata_o, output logic [3:0] imem_wstrb_o,
    output logic [15:0] start_pc_o, output logic [15:0] clkdiv_o,
    output logic [$clog2(N_PINS)-1:0] set_base_o,
    output logic [$clog2(N_PINS)-1:0] sideset_base_o,
    output logic [1:0] sideset_count_o,
    output logic [$clog2(N_PINS)-1:0] out_base_o,
    output logic [$clog2(N_PINS)-1:0] in_base_o,
    output logic [1:0] shift_cfg_o,
    output logic config_fault_o,
    output logic tx_host_push_o, output logic [31:0] tx_host_data_o,
    output logic rx_host_pop_o
);
    localparam int PC_W = $clog2(IMEM_DEPTH);
    localparam int PIN_W = $clog2(N_PINS);
    localparam int HOST_W = $clog2(IMEM_DEPTH/2);

    logic host_write, host_read, imem_window, cfg_write;
    logic valid_addr, read_only_addr, write_full_error;
    logic [15:0] addr_offset;

    always_comb begin
        host_ready_o = 1'b1;
        host_write = host_valid_i && host_write_i;
        host_read = host_valid_i && !host_write_i;

        imem_window = (host_addr_i >= 16'h0100) &&
                      (host_addr_i < (16'h0100 + (IMEM_DEPTH/2)*16'd4)) &&
                      (host_addr_i[1:0] == 2'b00);
        addr_offset = host_addr_i - 16'h0100;

        // 0x018/01c/020 are the FIFO data/status registers.  The remaining
        // execution configuration/debug registers are kept explicit so the
        // protocol engine remains programmable without hidden pin mappings.
        cfg_write = host_write && ((host_addr_i == 16'h0008) ||
                    (host_addr_i == 16'h000c) || (host_addr_i == 16'h0010) ||
                    (host_addr_i == 16'h0014) || (host_addr_i == 16'h002c) ||
                    (host_addr_i == 16'h0030) || (host_addr_i == 16'h0034));

        valid_addr = imem_window ||
                     (host_addr_i == 16'h0000) || (host_addr_i == 16'h0004) ||
                     (host_addr_i == 16'h0008) || (host_addr_i == 16'h000c) ||
                     (host_addr_i == 16'h0010) || (host_addr_i == 16'h0014) ||
                     (host_addr_i == 16'h0018) || (host_addr_i == 16'h001c) ||
                     (host_addr_i == 16'h0020) || (host_addr_i == 16'h0024) ||
                     (host_addr_i == 16'h0028) || (host_addr_i == 16'h002c) ||
                     (host_addr_i == 16'h0030) || (host_addr_i == 16'h0034) ||
                     (host_addr_i == 16'h0038) || (host_addr_i == 16'h003c) ||
                     (host_addr_i == 16'h0040) || (host_addr_i == 16'h0044);

        read_only_addr = (host_addr_i == 16'h0004) || (host_addr_i == 16'h0020) ||
                         (host_addr_i == 16'h0024) || (host_addr_i == 16'h0028) ||
                         (host_addr_i == 16'h0038) || (host_addr_i == 16'h003c) ||
                         (host_addr_i == 16'h0040) || (host_addr_i == 16'h0044) ||
                         (host_addr_i == 16'h001c);
        write_full_error = (host_addr_i == 16'h0018) && tx_full_i;

        run_cmd_o = host_write && (host_addr_i == 16'h0000) && host_wdata_i[0];
        halt_cmd_o = host_write && (host_addr_i == 16'h0000) && host_wdata_i[1];
        soft_reset_cmd_o = host_write && (host_addr_i == 16'h0000) && host_wdata_i[2];

        imem_write_fault_o = host_write && imem_window && running_i;
        imem_we_o = host_write && imem_window && !running_i;
        imem_word_addr_o = addr_offset[HOST_W+1:2];
        imem_wdata_o = host_wdata_i;
        imem_wstrb_o = host_wstrb_i;

        config_fault_o = (cfg_write && running_i) ||
                         (host_write && (host_addr_i == 16'h0014) &&
                          (host_wdata_i[9:8] > 2'd2));
        tx_host_push_o = host_write && (host_addr_i == 16'h0018) && !tx_full_i;
        tx_host_data_o = host_wdata_i;
        // RX is popped when the read transaction is accepted by this bus.
        rx_host_pop_o = host_read && (host_addr_i == 16'h001c) && !rx_empty_i;

        host_error_o = host_valid_i &&
                       ((!valid_addr) || (host_write_i && read_only_addr) ||
                        imem_write_fault_o || config_fault_o || write_full_error ||
                        (host_read && host_addr_i == 16'h001c && rx_empty_i));

        host_rdata_o = 32'b0;
        case (host_addr_i)
            16'h0004: begin
                host_rdata_o[0] = running_i;
                host_rdata_o[1] = fault_i;
                host_rdata_o[2] = tx_empty_i;
                host_rdata_o[3] = tx_full_i;
                host_rdata_o[4] = rx_empty_i;
                host_rdata_o[5] = rx_full_i;
                host_rdata_o[PC_W+5:6] = pc_i;
            end
            16'h0008: host_rdata_o[15:0] = start_pc_o;
            16'h000c: host_rdata_o[15:0] = clkdiv_o;
            16'h0010: host_rdata_o[PIN_W-1:0] = set_base_o;
            16'h0014: begin
                host_rdata_o[PIN_W-1:0] = sideset_base_o;
                host_rdata_o[9:8] = sideset_count_o;
            end
            16'h001c: host_rdata_o = rx_data_i;
            16'h0020: begin
                host_rdata_o[0] = tx_empty_i; host_rdata_o[1] = tx_full_i;
                host_rdata_o[2] = rx_empty_i; host_rdata_o[3] = rx_full_i;
                host_rdata_o[7:4] = tx_level_i; host_rdata_o[11:8] = rx_level_i;
            end
            16'h0024: host_rdata_o[PC_W-1:0] = pc_i;
            16'h0028: host_rdata_o[N_PINS-1:0] = gpio_in_i;
            16'h002c: host_rdata_o[PIN_W-1:0] = out_base_o;
            16'h0030: host_rdata_o[PIN_W-1:0] = in_base_o;
            16'h0034: host_rdata_o[1:0] = shift_cfg_o;
            16'h0038: host_rdata_o[15:0] = x_i;
            16'h003c: host_rdata_o[15:0] = y_i;
            16'h0040: host_rdata_o = osr_i;
            16'h0044: host_rdata_o = isr_i;
            default: if (imem_window) host_rdata_o = imem_host_rdata_i;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            start_pc_o <= '0; clkdiv_o <= 16'd1;
            set_base_o <= '0; sideset_base_o <= '0; sideset_count_o <= '0;
            out_base_o <= '0; in_base_o <= '0; shift_cfg_o <= 2'b10;
        end else if (!running_i) begin
            if (host_write && host_addr_i == 16'h0008 && host_wstrb_i[0])
                start_pc_o <= host_wdata_i[15:0];
            if (host_write && host_addr_i == 16'h000c && host_wstrb_i[0])
                clkdiv_o <= (host_wdata_i[15:0] == 0) ? 16'd1 : host_wdata_i[15:0];
            if (host_write && host_addr_i == 16'h0010 && host_wstrb_i[0])
                set_base_o <= host_wdata_i[PIN_W-1:0];
            if (host_write && host_addr_i == 16'h0014 && host_wstrb_i[0]) begin
                sideset_base_o <= host_wdata_i[PIN_W-1:0];
                sideset_count_o <= (host_wdata_i[9:8] <= 2'd2) ? host_wdata_i[9:8] : 2'd0;
            end
            if (host_write && host_addr_i == 16'h002c && host_wstrb_i[0])
                out_base_o <= host_wdata_i[PIN_W-1:0];
            if (host_write && host_addr_i == 16'h0030 && host_wstrb_i[0])
                in_base_o <= host_wdata_i[PIN_W-1:0];
            if (host_write && host_addr_i == 16'h0034 && host_wstrb_i[0])
                shift_cfg_o <= host_wdata_i[1:0];
        end
    end
endmodule
