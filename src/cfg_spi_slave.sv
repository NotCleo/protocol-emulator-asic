// Sampled management SPI slave. CFG_SCLK is an asynchronous input; it is
// never used as a clock. All state changes occur on clk_i.
//
// SPI restriction: Mode 0, MSB first, and CFG_SCLK <= 5 MHz for the nominal
// 50 MHz clk_i. The two-flop input synchronizers and sampled edge detector add
// deterministic latency but preserve one logical edge per external edge under
// that oversampling constraint.
module cfg_spi_slave (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic cfg_mosi,
    input  logic cfg_sclk,
    input  logic cfg_cs_n,
    output logic cfg_miso,
    output logic cmd_valid_o,
    output logic cmd_write_o,
    output logic [15:0] cmd_addr_o,
    output logic [31:0] cmd_wdata_o,
    output logic [3:0] cmd_wstrb_o,
    input  logic cmd_ready_i,
    input logic [31:0] cmd_rdata_i,
    input logic cmd_error_i
);
    logic sclk_meta_q, sclk_sync_q, sclk_prev_q;
    logic mosi_meta_q, mosi_sync_q;
    logic cs_meta_q, cs_sync_q, cs_prev_q;
    wire sclk_rise = sclk_sync_q && !sclk_prev_q;
    wire sclk_fall = !sclk_sync_q && sclk_prev_q;
    wire cs_start = cs_prev_q && !cs_sync_q;
    wire cs_active = !cs_sync_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sclk_meta_q <= 1'b0; sclk_sync_q <= 1'b0; sclk_prev_q <= 1'b0;
            mosi_meta_q <= 1'b0; mosi_sync_q <= 1'b0;
            cs_meta_q <= 1'b1; cs_sync_q <= 1'b1; cs_prev_q <= 1'b1;
        end else begin
            sclk_meta_q <= cfg_sclk;
            sclk_sync_q <= sclk_meta_q;
            sclk_prev_q <= sclk_sync_q;
            mosi_meta_q <= cfg_mosi;
            mosi_sync_q <= mosi_meta_q;
            cs_meta_q <= cfg_cs_n;
            cs_sync_q <= cs_meta_q;
            cs_prev_q <= cs_sync_q;
        end
    end

    localparam logic [2:0] PH_CMD = 3'd0;
    localparam logic [2:0] PH_ADDR_HI = 3'd1;
    localparam logic [2:0] PH_ADDR_LO = 3'd2;
    localparam logic [2:0] PH_COUNT = 3'd3;
    localparam logic [2:0] PH_DATA = 3'd4;

    localparam logic [7:0] CMD_WRITE32 = 8'h01;
    localparam logic [7:0] CMD_READ32 = 8'h02;
    localparam logic [7:0] CMD_BWRITE32 = 8'h03;
    localparam logic [7:0] CMD_BREAD32 = 8'h04;

    logic [2:0] phase_q;
    logic [7:0] opcode_q;
    logic [7:0] addr_hi_q;
    logic [15:0] address_q;
    logic [31:0] data_shift_q;
    logic [1:0] data_byte_count_q;
    logic [7:0] burst_left_q;
    logic [7:0] rx_shift_q;
    logic [2:0] rx_bit_count_q;
    logic [7:0] read_remaining_q;
    logic [15:0] read_address_q;
    logic read_pending_q;
    logic ignore_next_fall_q;
    logic [31:0] tx_shift_q;
    logic [5:0] tx_bits_q;
    logic transaction_error_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            phase_q <= PH_CMD;
            opcode_q <= 0; addr_hi_q <= 0; address_q <= 0;
            data_shift_q <= 0; data_byte_count_q <= 0; burst_left_q <= 0;
            rx_shift_q <= 0; rx_bit_count_q <= 0;
            read_remaining_q <= 0; read_address_q <= 0; read_pending_q <= 1'b0;
            ignore_next_fall_q <= 1'b0;
            tx_shift_q <= 0; tx_bits_q <= 0; transaction_error_q <= 1'b0;
            cmd_valid_o <= 1'b0; cmd_write_o <= 1'b0;
            cmd_addr_o <= 0; cmd_wdata_o <= 0; cmd_wstrb_o <= 0;
            cfg_miso <= 1'b0;
        end else begin
            cmd_valid_o <= 1'b0;

            if (!cs_active) begin
                phase_q <= PH_CMD;
                rx_shift_q <= 0; rx_bit_count_q <= 0;
                data_shift_q <= 0; data_byte_count_q <= 0; burst_left_q <= 0;
                read_remaining_q <= 0; read_pending_q <= 1'b0;
                ignore_next_fall_q <= 1'b0;
                tx_shift_q <= 0; tx_bits_q <= 0;
                transaction_error_q <= 1'b0;
                cfg_miso <= 1'b0;
            end else begin
                if (cs_start) begin
                    phase_q <= PH_CMD;
                    rx_shift_q <= 0; rx_bit_count_q <= 0;
                    data_shift_q <= 0; data_byte_count_q <= 0; burst_left_q <= 0;
                    read_remaining_q <= 0; read_pending_q <= 1'b0;
                    ignore_next_fall_q <= 1'b0;
                    tx_shift_q <= 0; tx_bits_q <= 0;
                    transaction_error_q <= 1'b0;
                    cfg_miso <= 1'b0;
                end

                // A read request is presented for one clk cycle. Capture its
                // response on the following clk before any new SPI edge is
                // expected at the supported management rate.
                if (read_pending_q && cmd_ready_i) begin
                    read_pending_q <= 1'b0;
                    tx_shift_q <= cmd_error_i ? 32'hDEAD_BEEF : cmd_rdata_i;
                    tx_bits_q <= 6'd32;
                    cfg_miso <= cmd_error_i ? 1'b1 : cmd_rdata_i[31];
                    if (read_remaining_q != 0)
                        read_remaining_q <= read_remaining_q - 1'b1;
                end

                // Mode 0: output changes on sampled falling edges.
                if (sclk_fall) begin
                    if (ignore_next_fall_q) begin
                        ignore_next_fall_q <= 1'b0;
                    end else if (tx_bits_q > 1) begin
                        tx_shift_q <= {tx_shift_q[30:0], 1'b0};
                        tx_bits_q <= tx_bits_q - 1'b1;
                        cfg_miso <= tx_shift_q[30];
                    end else if (tx_bits_q == 1) begin
                        tx_shift_q <= 0;
                        tx_bits_q <= 0;
                        cfg_miso <= 1'b0;
                        // Burst reads request the next word as soon as the
                        // current 32 response bits have been consumed.
                        if ((read_remaining_q != 0) && !read_pending_q) begin
                            cmd_valid_o <= 1'b1;
                            cmd_write_o <= 1'b0;
                            cmd_addr_o <= read_address_q + 16'd4;
                            cmd_wdata_o <= 0;
                            cmd_wstrb_o <= 0;
                            read_address_q <= read_address_q + 16'd4;
                            read_pending_q <= 1'b1;
                        end
                    end
                end

                // Mode 0: sample MOSI on sampled rising edges.
                if (sclk_rise) begin
                    if (rx_bit_count_q == 3'd7) begin
                        rx_bit_count_q <= 0;
                        case (phase_q)
                            PH_CMD: begin
                                opcode_q <= {rx_shift_q[6:0], mosi_sync_q};
                                if (({rx_shift_q[6:0], mosi_sync_q} >= CMD_WRITE32) &&
                                    ({rx_shift_q[6:0], mosi_sync_q} <= CMD_BREAD32)) begin
                                    phase_q <= PH_ADDR_HI;
                                end else begin
                                    phase_q <= PH_CMD;
                                    transaction_error_q <= 1'b1;
                                end
                            end
                            PH_ADDR_HI: begin
                                addr_hi_q <= {rx_shift_q[6:0], mosi_sync_q};
                                phase_q <= PH_ADDR_LO;
                            end
                            PH_ADDR_LO: begin
                                address_q <= {addr_hi_q, {rx_shift_q[6:0], mosi_sync_q}};
                                if (opcode_q == CMD_READ32) begin
                                    cmd_valid_o <= 1'b1; cmd_write_o <= 1'b0;
                                    cmd_addr_o <= {addr_hi_q, {rx_shift_q[6:0], mosi_sync_q}};
                                    cmd_wdata_o <= 0; cmd_wstrb_o <= 0;
                                    read_address_q <= {addr_hi_q, {rx_shift_q[6:0], mosi_sync_q}};
                                    read_remaining_q <= 8'd1; read_pending_q <= 1'b1;
                                    ignore_next_fall_q <= 1'b1;
                                    phase_q <= PH_CMD;
                                end else if (opcode_q == CMD_BREAD32 || opcode_q == CMD_BWRITE32) begin
                                    phase_q <= PH_COUNT;
                                end else begin
                                    phase_q <= PH_DATA;
                                    burst_left_q <= 8'd1;
                                    data_byte_count_q <= 0;
                                    data_shift_q <= 0;
                                end
                            end
                            PH_COUNT: begin
                                if ({rx_shift_q[6:0], mosi_sync_q} == 0) begin
                                    phase_q <= PH_CMD;
                                    transaction_error_q <= 1'b1;
                                end else if (opcode_q == CMD_BREAD32) begin
                                    cmd_valid_o <= 1'b1; cmd_write_o <= 1'b0;
                                    cmd_addr_o <= address_q; cmd_wdata_o <= 0; cmd_wstrb_o <= 0;
                                    read_address_q <= address_q;
                                    read_remaining_q <= {rx_shift_q[6:0], mosi_sync_q};
                                    read_pending_q <= 1'b1;
                                    ignore_next_fall_q <= 1'b1;
                                    phase_q <= PH_CMD;
                                end else begin
                                    burst_left_q <= {rx_shift_q[6:0], mosi_sync_q};
                                    data_byte_count_q <= 0; data_shift_q <= 0;
                                    phase_q <= PH_DATA;
                                end
                            end
                            PH_DATA: begin
                                data_shift_q <= {data_shift_q[23:0], {rx_shift_q[6:0], mosi_sync_q}};
                                if (data_byte_count_q == 2'd3) begin
                                    cmd_valid_o <= 1'b1; cmd_write_o <= 1'b1;
                                    cmd_addr_o <= address_q;
                                    cmd_wdata_o <= {data_shift_q[23:0], {rx_shift_q[6:0], mosi_sync_q}};
                                    cmd_wstrb_o <= 4'hf;
                                    data_byte_count_q <= 0; data_shift_q <= 0;
                                    if (burst_left_q > 1) begin
                                        burst_left_q <= burst_left_q - 1'b1;
                                        address_q <= address_q + 16'd4;
                                    end else begin
                                        burst_left_q <= 0;
                                        phase_q <= PH_CMD;
                                    end
                                end else begin
                                    data_byte_count_q <= data_byte_count_q + 1'b1;
                                end
                            end
                            default: phase_q <= PH_CMD;
                        endcase
                    end else begin
                        rx_shift_q <= {rx_shift_q[6:0], mosi_sync_q};
                        rx_bit_count_q <= rx_bit_count_q + 1'b1;
                    end
                end
            end
        end
    end
endmodule
