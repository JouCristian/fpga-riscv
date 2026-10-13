`timescale 1ns / 1ps

module regfile (
    input clk,
    input reset,
    input [4:0] rs1,
    input [4:0] rs2,
    output [31:0] rs1_data,
    output [31:0] rs2_data,
    input we,
    input [4:0] rd,
    input [31:0] rd_data
);
    reg [31:0] regs [0:31];
    integer i;

    // Two asynchronous(异步) reads, one synchronous(同步) write. No forwarding(转发) is needed
    // in this single-cycle core. Resetting all registers helps teaching/debug.
    assign rs1_data = (rs1 == 5'd0) ? 32'b0 : regs[rs1];
    assign rs2_data = (rs2 == 5'd0) ? 32'b0 : regs[rs2];

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (we && (rd != 5'd0)) begin
            regs[rd] <= rd_data;
        end
    end
endmodule
