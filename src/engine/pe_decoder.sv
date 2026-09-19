module pe_decoder (
    input  logic [15:0] instr_i,
    output logic [2:0]  major_o,
    output logic [2:0]  endpoint_a_o,
    output logic [2:0]  endpoint_b_o,
    output logic [4:0]  field5_o,
    output logic [5:0]  target_o,
    output logic [4:0]  timing_o,
    output logic        supported_o
);
    localparam logic [2:0] MAJOR_JMP = 3'b000;
    localparam logic [2:0] MAJOR_WAIT = 3'b001;
    localparam logic [2:0] MAJOR_IN = 3'b010;
    localparam logic [2:0] MAJOR_OUT = 3'b011;
    localparam logic [2:0] MAJOR_PUSH_PULL = 3'b100;
    localparam logic [2:0] MAJOR_MOV = 3'b101;
    localparam logic [2:0] MAJOR_EXT = 3'b110;
    localparam logic [2:0] MAJOR_SET = 3'b111;

    always_comb begin
        major_o = instr_i[15:13];
        endpoint_a_o = instr_i[12:10];
        endpoint_b_o = instr_i[9:7];
        field5_o = instr_i[9:5];
        target_o = instr_i[9:4];
        timing_o = instr_i[4:0];
        supported_o = 1'b0;
        case (major_o)
            MAJOR_JMP: supported_o = (endpoint_a_o <= 3'd6);
            MAJOR_WAIT: supported_o = (endpoint_a_o <= 3'd5);
            MAJOR_IN, MAJOR_OUT: supported_o = (endpoint_a_o <= 3'd5);
            MAJOR_PUSH_PULL: supported_o = 1'b1;
            MAJOR_MOV: supported_o = (endpoint_a_o <= 3'd5) && (endpoint_b_o <= 3'd5);
            MAJOR_EXT: supported_o = (endpoint_a_o == 3'd0);
            MAJOR_SET: supported_o = (endpoint_a_o <= 3'd3);
            default: supported_o = 1'b0;
        endcase
    end
endmodule
