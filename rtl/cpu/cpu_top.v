`timescale 1ns / 1ps
`include "cpu_defs.vh"

module cpu_top (
    input clk,
    input reset,                   // Active-high, synchronous reset.
    output [31:0] imem_addr,
    input [31:0] imem_rdata,
    output [31:0] dmem_addr,        // Byte address; low bits select byte lanes.
    output [31:0] dmem_wdata,
    input [31:0] dmem_rdata,        // Aligned 32-bit word containing dmem_addr.
    output dmem_we,
    output [3:0] dmem_wstrb,
    output reg trap,               // Latched on fault; halted until reset.
    output reg [3:0] trap_cause
);
    wire [31:0] pc_value;
    wire [31:0] pc_plus4 = pc_value + 32'd4;
    wire [31:0] next_pc;
    wire [31:0] imm;
    wire [31:0] rs1_data, rs2_data;
    wire [31:0] alu_a, alu_b, alu_result;
    reg [31:0] wb_data;
    wire reg_write, rf_we;
    wire [3:0] alu_op;
    wire [1:0] alu_a_sel, wb_sel, mem_size;
    wire alu_b_imm;
    wire [2:0] imm_sel, branch_op;
    wire mem_read, mem_write, load_unsigned;
    wire branch, branch_taken, jump, jalr;
    wire illegal, system_trap;
    wire [3:0] system_cause;

    pc u_pc (.clk(clk), .reset(reset), .next_pc(next_pc), .pc(pc_value));
    assign imem_addr = pc_value;

    decoder u_decoder (
        .instr(imem_rdata), .reg_write(reg_write), .alu_op(alu_op),
        .alu_a_sel(alu_a_sel), .alu_b_imm(alu_b_imm), .imm_sel(imm_sel),
        .wb_sel(wb_sel), .mem_read(mem_read), .mem_write(mem_write),
        .mem_size(mem_size), .load_unsigned(load_unsigned), .branch(branch),
        .branch_op(branch_op), .jump(jump), .jalr(jalr), .illegal(illegal),
        .system_trap(system_trap), .system_cause(system_cause)
    );
    imm_gen u_imm (.instr(imem_rdata), .imm_sel(imm_sel), .imm(imm));
    regfile u_regfile (
        .clk(clk), .reset(reset), .rs1(imem_rdata[19:15]), .rs2(imem_rdata[24:20]),
        .rs1_data(rs1_data), .rs2_data(rs2_data), .we(rf_we),
        .rd(imem_rdata[11:7]), .rd_data(wb_data)
    );
    assign alu_a = (alu_a_sel == `SRC_PC) ? pc_value :
                   (alu_a_sel == `SRC_ZERO) ? 32'b0 : rs1_data;
    assign alu_b = alu_b_imm ? imm : rs2_data;
    alu u_alu (.a(alu_a), .b(alu_b), .op(alu_op), .result(alu_result));
    branch_unit u_branch (
        .a(rs1_data), .b(rs2_data), .branch_op(branch_op), .taken(branch_taken)
    );

    // Branch/JAL are PC-relative; JALR uses rs1+imm and clears only bit 0.
    wire redirect = jump || (branch && branch_taken);
    wire [31:0] target = jalr ? {alu_result[31:1], 1'b0} : (pc_value + imm);
    wire [31:0] normal_next_pc = redirect ? target : pc_plus4;

    // Little-endian load/store lanes. Memory must return the aligned word;
    // writes use these lane strobes on the rising clock edge, with no wait states.
    wire [4:0] lane_shift = {alu_result[1:0], 3'b000};
    wire [31:0] shifted_load = dmem_rdata >> lane_shift;
    reg [31:0] load_data;
    reg [3:0] store_mask;
    assign dmem_addr = alu_result;
    assign dmem_wdata = rs2_data << lane_shift;
    always @* begin
        load_data = shifted_load;
        store_mask = 4'b0000;
        case (mem_size)
            `MEM_BYTE: begin
                load_data = {{24{!load_unsigned && shifted_load[7]}}, shifted_load[7:0]};
                store_mask = 4'b0001 << alu_result[1:0];
            end
            `MEM_HALF: begin
                load_data = {{16{!load_unsigned && shifted_load[15]}}, shifted_load[15:0]};
                store_mask = 4'b0011 << alu_result[1:0];
            end
            `MEM_WORD: begin
                load_data = shifted_load;
                store_mask = 4'b1111;
            end
            default: begin
                load_data = 32'b0;
                store_mask = 4'b0000;
            end
        endcase
    end
    always @* begin
        case (wb_sel)
            `WB_MEM: wb_data = load_data;
            `WB_PC4: wb_data = pc_plus4;
            default: wb_data = alu_result;
        endcase
    end

    wire data_misaligned = ((mem_size == `MEM_HALF) && alu_result[0]) ||
                           ((mem_size == `MEM_WORD) && (alu_result[1:0] != 2'b00));
    reg fault;
    reg [3:0] fault_cause;
    always @* begin
        fault = 1'b1;
        fault_cause = `TRAP_INST_ALIGN;
        if (pc_value[1:0] != 2'b00) begin
            fault_cause = `TRAP_INST_ALIGN;
        end else if (illegal) begin
            fault_cause = `TRAP_ILLEGAL;
        end else if (system_trap) begin
            fault_cause = system_cause;
        end else if (redirect && (target[1:0] != 2'b00)) begin
            fault_cause = `TRAP_INST_ALIGN;
        end else if (mem_read && data_misaligned) begin
            fault_cause = `TRAP_LOAD_ALIGN;
        end else if (mem_write && data_misaligned) begin
            fault_cause = `TRAP_STORE_ALIGN;
        end else begin
            fault = 1'b0;
        end
    end

    // The faulting instruction never commits a register or memory write.
    assign rf_we = reg_write && !reset && !trap && !fault;
    assign dmem_we = mem_write && !reset && !trap && !fault;
    assign dmem_wstrb = dmem_we ? store_mask : 4'b0000;
    assign next_pc = (trap || fault) ? pc_value : normal_next_pc;
    always @(posedge clk) begin
        if (reset) begin
            trap <= 1'b0;
            trap_cause <= 4'b0;
        end else if (!trap && fault) begin
            trap <= 1'b1;
            trap_cause <= fault_cause;
        end
    end
endmodule
