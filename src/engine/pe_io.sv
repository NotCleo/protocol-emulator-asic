module pe_io #(
    parameter int N_PINS = 8
) (
    input logic clk_i, input logic rst_ni, input logic soft_reset_i,
    input logic event_i,
    input logic set_pins_we_i, input logic [N_PINS-1:0] set_pins_value_i,
    input logic set_oe_we_i, input logic [N_PINS-1:0] set_oe_value_i,
    input logic [$clog2(N_PINS)-1:0] set_base_i,
    input logic out_pins_we_i, input logic [N_PINS-1:0] out_pins_value_i,
    input logic [5:0] out_pins_count_i,
    input logic [$clog2(N_PINS)-1:0] out_base_i,
    input logic sideset_we_i, input logic [N_PINS-1:0] sideset_value_i,
    input logic [$clog2(N_PINS)-1:0] sideset_base_i,
    input logic [1:0] sideset_count_i,
    output logic [N_PINS-1:0] gpio_out_o, output logic [N_PINS-1:0] gpio_oe_o
);
    localparam int PIN_W = $clog2(N_PINS);
    function automatic [N_PINS-1:0] mapped_write(
        input logic [N_PINS-1:0] current, input logic [N_PINS-1:0] value,
        input logic [PIN_W-1:0] base, input logic [5:0] count
    );
        logic [N_PINS-1:0] result;
        integer bit_index, pin_index;
        begin
            result = current;
            for (bit_index = 0; bit_index < N_PINS; bit_index = bit_index + 1) begin
                pin_index = base + bit_index;
                if ((bit_index < count) && (pin_index < N_PINS)) result[pin_index] = value[bit_index];
            end
            mapped_write = result;
        end
    endfunction

    logic [N_PINS-1:0] gpio_out_next, gpio_oe_next;
    always_comb begin
        gpio_out_next = gpio_out_o;
        gpio_oe_next = gpio_oe_o;
        if (event_i) begin
            if (set_pins_we_i) gpio_out_next = mapped_write(gpio_out_next, set_pins_value_i, set_base_i, 6'd5);
            if (out_pins_we_i) gpio_out_next = mapped_write(gpio_out_next, out_pins_value_i, out_base_i, out_pins_count_i);
            if (sideset_we_i) gpio_out_next = mapped_write(gpio_out_next, sideset_value_i, sideset_base_i, {4'b0, sideset_count_i});
            if (set_oe_we_i) gpio_oe_next = mapped_write(gpio_oe_next, set_oe_value_i, set_base_i, 6'd5);
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni || soft_reset_i) begin gpio_out_o <= '0; gpio_oe_o <= '0; end
        else begin gpio_out_o <= gpio_out_next; gpio_oe_o <= gpio_oe_next; end
    end
endmodule
