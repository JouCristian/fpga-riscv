`timescale 1ns / 1ps
`include "cpu_defs.vh"

module decoder (
    input [31:0] instr,
    output reg reg_write,
    output reg [3:0] alu_op,
    output reg [1:0] alu_a_sel,
    output reg alu_b_imm,
    output reg [2:0] imm_sel,
    output reg [1:0] wb_sel,
    output reg mem_read,
    output reg mem_write,
    output reg [1:0] mem_size,
    output reg load_unsigned,
    output reg branch,
    output [2:0] branch_op,
    output reg jump,
    output reg jalr,
    output reg illegal,
    output reg system_trap,
    output reg [3:0] system_cause
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire is_reg_op = opcode[5]; // OP vs OP-IMM, only used in that case arm.
    assign branch_op = funct3;

    always @* begin
        reg_write = 1'b0;
        alu_op = `ALU_ADD;
        alu_a_sel = `SRC_RS1;
        alu_b_imm = 1'b0;
        imm_sel = `IMM_I;
        wb_sel = `WB_ALU;
        mem_read = 1'b0;
        mem_write = 1'b0;
        mem_size = `MEM_BYTE;
        load_unsigned = 1'b0;
        branch = 1'b0;
        jump = 1'b0;
        jalr = 1'b0;
        illegal = 1'b0;
        system_trap = 1'b0;
        system_cause = `TRAP_ECALL;

        case (opcode)
            7'b0110111, 7'b0010111: begin // LUI / AUIPC
                reg_write = 1'b1;
                alu_a_sel = (opcode == 7'b0110111) ? `SRC_ZERO : `SRC_PC;
                alu_b_imm = 1'b1;
                imm_sel = `IMM_U;
            end
            7'b1101111: begin // JAL
                reg_write = 1'b1;
                wb_sel = `WB_PC4;
                jump = 1'b1;
                imm_sel = `IMM_J;
            end
            7'b1100111: begin // JALR
                reg_write = 1'b1;
                wb_sel = `WB_PC4;
                jump = 1'b1;
                jalr = 1'b1;
                alu_b_imm = 1'b1;
                if (funct3 != 3'b000) illegal = 1'b1;
            end
            7'b1100011: begin // Branches
                branch = 1'b1;
                imm_sel = `IMM_B;
                if ((funct3 == 3'b010) || (funct3 == 3'b011))
                    illegal = 1'b1;
            end
            7'b0000011, 7'b0100011: begin // Loads / stores share address/size decode.
                mem_write = opcode[5];
                mem_read = !opcode[5];
                reg_write = !opcode[5];
                alu_b_imm = 1'b1;
                imm_sel = opcode[5] ? `IMM_S : `IMM_I;
                wb_sel = `WB_MEM;
                load_unsigned = funct3[2];
                case (funct3)
                    3'b000, 3'b100: mem_size = `MEM_BYTE;
                    3'b001, 3'b101: mem_size = `MEM_HALF;
                    3'b010: mem_size = `MEM_WORD;
                    default: illegal = 1'b1;
                endcase
                if (opcode[5] && funct3[2]) illegal = 1'b1;
            end
            7'b0010011, 7'b0110011: begin // OP-IMM / OP: one ALU decode table.
                reg_write = 1'b1;
                alu_b_imm = !is_reg_op;
                case (funct3)
                    3'b000: alu_op = (is_reg_op && funct7[5]) ? `ALU_SUB : `ALU_ADD;
                    3'b001: alu_op = `ALU_SLL;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    default: alu_op = `ALU_ADD;
                endcase
                // Non-shift immediates use all 12 bits as data, not funct7.
                if (is_reg_op || (funct3 == 3'b001) || (funct3 == 3'b101)) begin
                    if (funct7 != 7'b0000000) begin
                        if (!((funct7 == 7'b0100000) &&
                              ((funct3 == 3'b101) ||
                               (is_reg_op && (funct3 == 3'b000)))))
                            illegal = 1'b1;
                    end
                end
            end
            7'b0001111: begin // FENCE: NOP in this ordered single-core memory model.
                // FENCE.I (funct3=001) is not part of the implemented ISA.
                if (funct3 != 3'b000) illegal = 1'b1;
            end
            7'b1110011: begin
                case (instr)
                    32'h00000073: system_trap = 1'b1; // ECALL
                    32'h00100073: begin              // EBREAK
                        system_trap = 1'b1;
                        system_cause = `TRAP_BREAKPOINT;
                    end
                    default: illegal = 1'b1;         // Includes CSR instructions.
                endcase
            end
            default: illegal = 1'b1;
        endcase
    end
endmodule
