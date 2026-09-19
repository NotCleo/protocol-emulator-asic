module pe_core #(
    parameter int IMEM_DEPTH = 64,
    parameter int N_PINS = 8
) (
    input logic clk_i, input logic rst_ni,
    input logic soft_reset_i, input logic run_cmd_i, input logic halt_cmd_i,
    input logic imem_write_fault_i, input logic config_fault_i,
    input logic engine_ce_i, input logic [15:0] start_pc_i,
    output logic [$clog2(IMEM_DEPTH)-1:0] imem_instr_addr_o,
    input logic [15:0] instr_i,
    input logic [$clog2(N_PINS)-1:0] set_base_i,
    input logic [$clog2(N_PINS)-1:0] sideset_base_i,
    input logic [$clog2(N_PINS)-1:0] out_base_i,
    input logic [$clog2(N_PINS)-1:0] in_base_i,
    input logic [1:0] sideset_count_i,
    input logic [1:0] shift_cfg_i,
    input logic [N_PINS-1:0] gpio_in_i,
    input logic [N_PINS-1:0] rising_i,
    input logic [N_PINS-1:0] falling_i,
    input logic tx_empty_i, input logic rx_full_i,
    input logic [31:0] tx_data_i,
    output logic tx_pop_o, output logic rx_push_o, output logic [31:0] rx_data_o,
    output logic running_o, output logic fault_o,
    output logic [$clog2(IMEM_DEPTH)-1:0] pc_o,
    output logic [15:0] x_o, output logic [15:0] y_o,
    output logic [31:0] osr_o, output logic [31:0] isr_o,
    output logic [4:0] delay_count_o,
    output logic [5:0] osr_count_o, output logic [5:0] isr_count_o,
    output logic [2:0] stall_reason_o,
    output logic io_event_o,
    output logic set_pins_we_o, output logic [N_PINS-1:0] set_pins_value_o,
    output logic set_oe_we_o, output logic [N_PINS-1:0] set_oe_value_o,
    output logic out_pins_we_o, output logic [N_PINS-1:0] out_pins_value_o,
    output logic [5:0] out_pins_count_o,
    output logic sideset_we_o, output logic [N_PINS-1:0] sideset_value_o
);
    localparam int PC_W = $clog2(IMEM_DEPTH);
    localparam logic [2:0] JMP = 3'b000, WAIT = 3'b001, IN_OP = 3'b010,
                           OUT_OP = 3'b011, PUSH_PULL = 3'b100, MOV = 3'b101,
                           EXT = 3'b110, SET = 3'b111;
    localparam logic [2:0] PINS = 3'd0, X = 3'd1, Y = 3'd2, OSR = 3'd3,
                           ISR = 3'd4, NULL_EP = 3'd5;
    localparam logic [2:0] WAIT_HIGH = 3'd0, WAIT_LOW = 3'd1, WAIT_RISE = 3'd2,
                           WAIT_FALL = 3'd3, WAIT_TX = 3'd4, WAIT_RX = 3'd5;

    logic [PC_W-1:0] pc_q;
    logic [15:0] x_q, y_q;
    logic [31:0] osr_q, isr_q;
    logic [5:0] osr_count_q, isr_count_q;
    logic [4:0] delay_count_q;
    logic running_q, fault_q;
    logic [2:0] major, endpoint_a, endpoint_b;
    logic [4:0] field5, timing, delay_field;
    logic [5:0] target;
    logic [1:0] side_field;
    logic supported, wait_ok, fifo_ok, execute_now, branch_taken;
    logic [5:0] shift_count;
    logic [31:0] source_value, shifted_value;
    logic [5:0] source_count;
    logic [2:0] source_endpoint;
    logic [31:0] masked_value, shift_mask;
    integer k;

    assign imem_instr_addr_o = pc_q;
    assign running_o = running_q;
    assign fault_o = fault_q;
    assign pc_o = pc_q;
    assign x_o = x_q; assign y_o = y_q;
    assign osr_o = osr_q; assign isr_o = isr_q;
    assign delay_count_o = delay_count_q;
    assign osr_count_o = osr_count_q; assign isr_count_o = isr_count_q;
    assign rx_data_o = isr_q;

    pe_decoder decoder (
        .instr_i(instr_i), .major_o(major), .endpoint_a_o(endpoint_a),
        .endpoint_b_o(endpoint_b), .field5_o(field5), .target_o(target),
        .timing_o(timing), .supported_o(supported)
    );

    always_comb begin
        shift_count = (field5 == 0) ? 6'd32 : {1'b0, field5};
        case (sideset_count_i)
            2'd0: begin side_field = 2'b0; delay_field = timing; end
            2'd1: begin side_field = {1'b0, timing[4]}; delay_field = {1'b0, timing[3:0]}; end
            2'd2: begin side_field = timing[4:3]; delay_field = {2'b0, timing[2:0]}; end
            default: begin side_field = 2'b0; delay_field = 5'b0; end
        endcase
    end

    function automatic [31:0] mapped_read(
        input logic [N_PINS-1:0] value,
        input logic [$clog2(N_PINS)-1:0] base,
        input logic [5:0] count
    );
        integer i, p;
        begin
            mapped_read = 32'b0;
            for (i = 0; i < N_PINS; i = i + 1) begin
                p = base + i;
                if ((i < count) && (p < N_PINS)) mapped_read[i] = value[p];
            end
        end
    endfunction

    always_comb begin
        source_endpoint = (major == MOV) ? endpoint_b : endpoint_a;
        source_count = (major == IN_OP) ? shift_count : 6'd8;
        source_value = 32'b0;
        case (source_endpoint)
            PINS: source_value = mapped_read(gpio_in_i, in_base_i, source_count);
            X: source_value = {16'b0, x_q};
            Y: source_value = {16'b0, y_q};
            OSR: source_value = osr_q;
            ISR: source_value = isr_q;
            NULL_EP: source_value = 32'b0;
            default: source_value = 32'b0;
        endcase
    end

    always_comb begin
        wait_ok = 1'b1;
        if (major == WAIT) begin
            case (endpoint_a)
                WAIT_HIGH: wait_ok = gpio_in_i[endpoint_b];
                WAIT_LOW: wait_ok = !gpio_in_i[endpoint_b];
                WAIT_RISE: wait_ok = rising_i[endpoint_b];
                WAIT_FALL: wait_ok = falling_i[endpoint_b];
                WAIT_TX: wait_ok = !tx_empty_i;
                WAIT_RX: wait_ok = !rx_full_i;
                default: wait_ok = 1'b0;
            endcase
        end
        fifo_ok = 1'b1;
        if (major == PUSH_PULL) begin
            if (instr_i[12]) fifo_ok = !rx_full_i || !instr_i[11];
            else fifo_ok = !tx_empty_i || !instr_i[11];
        end
        execute_now = running_q && engine_ce_i && (delay_count_q == 0) &&
                      !halt_cmd_i && !soft_reset_i && !imem_write_fault_i &&
                      !config_fault_i && supported && wait_ok && fifo_ok;
        io_event_o = execute_now && (major != JMP);
        sideset_we_o = io_event_o && (sideset_count_i != 0);
        sideset_value_o = '0; sideset_value_o[1:0] = side_field;
        set_pins_we_o = io_event_o && major == SET && endpoint_a == 0;
        set_oe_we_o = io_event_o && major == SET && endpoint_a == 1;
        set_pins_value_o = '0; set_oe_value_o = '0;
        set_pins_value_o[4:0] = field5; set_oe_value_o[4:0] = field5;
        out_pins_we_o = 1'b0; out_pins_value_o = '0; out_pins_count_o = 6'd0;
        if (io_event_o && major == OUT_OP && endpoint_a == PINS) begin
            out_pins_we_o = 1'b1; out_pins_value_o = shifted_value[N_PINS-1:0];
            out_pins_count_o = shift_count;
        end else if (io_event_o && major == MOV && endpoint_a == PINS) begin
            out_pins_we_o = 1'b1; out_pins_value_o = source_value[N_PINS-1:0];
            out_pins_count_o = 6'd8;
        end
        tx_pop_o = execute_now && major == PUSH_PULL && !instr_i[12] && !tx_empty_i;
        rx_push_o = execute_now && major == PUSH_PULL && instr_i[12] && !rx_full_i;
        stall_reason_o = 3'd0;
        if (running_q && engine_ce_i && delay_count_q != 0) stall_reason_o = 3'd1;
        else if (running_q && engine_ce_i && major == WAIT && !wait_ok) stall_reason_o = 3'd2;
        else if (running_q && engine_ce_i && major == PUSH_PULL && !fifo_ok) stall_reason_o = instr_i[12] ? 3'd4 : 3'd3;
    end

    always_comb begin
        shift_mask = (shift_count == 32) ? 32'hffff_ffff : ((32'b1 << shift_count) - 1'b1);
        shifted_value = shift_cfg_i[1] ? (osr_q & shift_mask) : (osr_q >> (32-shift_count)) & shift_mask;
    end

    always_comb begin
        branch_taken = 1'b0;
        if (major == JMP) begin
            case (endpoint_a)
                3'd0: branch_taken = 1'b1;
                3'd1: branch_taken = (x_q == 0);
                3'd2: branch_taken = (x_q != 0);
                3'd3: branch_taken = (y_q == 0);
                3'd4: branch_taken = (y_q != 0);
                3'd5: branch_taken = gpio_in_i[0];
                3'd6: branch_taken = !gpio_in_i[0];
                default: branch_taken = 1'b0;
            endcase
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_q <= '0; x_q <= 0; y_q <= 0; osr_q <= 0; isr_q <= 0;
            osr_count_q <= 0; isr_count_q <= 0; delay_count_q <= 0;
            running_q <= 0; fault_q <= 0;
        end else if (soft_reset_i) begin
            pc_q <= '0; x_q <= 0; y_q <= 0; osr_q <= 0; isr_q <= 0;
            osr_count_q <= 0; isr_count_q <= 0; delay_count_q <= 0;
            running_q <= 0; fault_q <= 0;
        end else if (imem_write_fault_i || config_fault_i) begin
            fault_q <= 1'b1; running_q <= 1'b0;
        end else if (halt_cmd_i) begin
            running_q <= 1'b0;
        end else if (run_cmd_i && !running_q) begin
            pc_q <= (start_pc_i < IMEM_DEPTH) ? start_pc_i[PC_W-1:0] : '0;
            running_q <= (start_pc_i < IMEM_DEPTH);
            if (start_pc_i >= IMEM_DEPTH) fault_q <= 1'b1;
        end else if (running_q && engine_ce_i) begin
            if (delay_count_q != 0) begin
                delay_count_q <= delay_count_q - 1'b1;
            end else if (!supported) begin
                fault_q <= 1'b1; running_q <= 1'b0;
            end else if ((major == WAIT && !wait_ok) || (major == PUSH_PULL && !fifo_ok)) begin
                // Blocking WAIT/PULL/PUSH holds all architectural state.
            end else if (major == JMP) begin
                if (endpoint_a == 2 && x_q != 0) x_q <= x_q - 1'b1;
                if (endpoint_a == 4 && y_q != 0) y_q <= y_q - 1'b1;
                if (branch_taken) begin
                    if (target < IMEM_DEPTH) pc_q <= target[PC_W-1:0];
                    else begin fault_q <= 1'b1; running_q <= 1'b0; end
                end else if (pc_q == IMEM_DEPTH-1) begin
                    fault_q <= 1'b1; running_q <= 1'b0;
                end else pc_q <= pc_q + 1'b1;
            end else begin
                case (major)
                    IN_OP: begin
                        if (shift_cfg_i[0]) isr_q <= (isr_q >> shift_count) | ((source_value & shift_mask) << (32-shift_count));
                        else isr_q <= (isr_q << shift_count) | (source_value & shift_mask);
                        isr_count_q <= (isr_count_q + shift_count > 32) ? 32 : isr_count_q + shift_count;
                    end
                    OUT_OP: begin
                        if (shift_cfg_i[1]) osr_q <= osr_q >> shift_count;
                        else osr_q <= osr_q << shift_count;
                        osr_count_q <= (osr_count_q > shift_count) ? osr_count_q - shift_count : 0;
                        case (endpoint_a)
                            X: x_q <= shifted_value[15:0];
                            Y: y_q <= shifted_value[15:0];
                            OSR: begin osr_q <= shifted_value; osr_count_q <= 32; end
                            ISR: begin isr_q <= shifted_value; isr_count_q <= 32; end
                            default: begin end
                        endcase
                    end
                    PUSH_PULL: begin
                        if (instr_i[12] && !rx_full_i) isr_count_q <= 0;
                        if (!instr_i[12] && !tx_empty_i) begin osr_q <= tx_data_i; osr_count_q <= 32; end
                    end
                    MOV: begin
                        case (endpoint_a)
                            X: x_q <= source_value[15:0];
                            Y: y_q <= source_value[15:0];
                            OSR: begin osr_q <= source_value; osr_count_q <= 32; end
                            ISR: begin isr_q <= source_value; isr_count_q <= 32; end
                            default: begin end
                        endcase
                    end
                    SET: begin
                        if (endpoint_a == 2) x_q <= field5;
                        if (endpoint_a == 3) y_q <= field5;
                    end
                    default: begin end
                endcase
                delay_count_q <= delay_field;
                if (pc_q == IMEM_DEPTH-1) begin
                    fault_q <= 1'b1; running_q <= 1'b0;
                end else pc_q <= pc_q + 1'b1;
            end
        end
    end
endmodule
