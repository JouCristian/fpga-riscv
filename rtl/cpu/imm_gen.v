`timescale 1ns / 1ps
`include "cpu_defs.vh"

module imm_gen (
    input [31:0] instr,
    input [2:0] imm_sel,
    output reg [31:0] imm
);
    // R-type has no immediate. I/S/B/U/J are the five immediate formats.
    always @* begin
        case (imm_sel)
            `IMM_I: imm = {{20{instr[31]}}, instr[31:20]};
            `IMM_S: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `IMM_B: imm = {{19{instr[31]}}, instr[31], instr[7],
                          instr[30:25], instr[11:8], 1'b0};
            `IMM_U: imm = {instr[31:12], 12'b0};
            `IMM_J: imm = {{11{instr[31]}}, instr[31], instr[19:12],
                          instr[20], instr[30:21], 1'b0};
            default: imm = 32'b0;
        endcase
    end
endmodule
