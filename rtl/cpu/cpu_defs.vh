`ifndef CPU_DEFS_VH
`define CPU_DEFS_VH

// Internal control encodings, shared by the decoder and datapath.
`define ALU_ADD  4'd0
`define ALU_SUB  4'd1
`define ALU_SLL  4'd2
`define ALU_SLT  4'd3
`define ALU_SLTU 4'd4
`define ALU_XOR  4'd5
`define ALU_SRL  4'd6
`define ALU_SRA  4'd7
`define ALU_OR   4'd8
`define ALU_AND  4'd9

`define IMM_I 3'd0
`define IMM_S 3'd1
`define IMM_B 3'd2
`define IMM_U 3'd3
`define IMM_J 3'd4

`define SRC_RS1  2'd0
`define SRC_PC   2'd1
`define SRC_ZERO 2'd2
`define WB_ALU   2'd0
`define WB_MEM   2'd1
`define WB_PC4   2'd2
`define MEM_BYTE 2'd0
`define MEM_HALF 2'd1
`define MEM_WORD 2'd2

// These numbers match the synchronous RISC-V exception cause values.
// They are debug outputs only: this core has no CSRs or trap vector.
`define TRAP_INST_ALIGN 4'd0
`define TRAP_ILLEGAL    4'd2
`define TRAP_BREAKPOINT 4'd3
`define TRAP_LOAD_ALIGN 4'd4
`define TRAP_STORE_ALIGN 4'd6
`define TRAP_ECALL      4'd11
`endif
