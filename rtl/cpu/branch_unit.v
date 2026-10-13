`timescale 1ns / 1ps

module branch_unit (
    input [31:0] a,
    input [31:0] b,
    input [2:0] branch_op,
    output reg taken
);
    // branch_op is the validated branch funct3 from the central decoder.
    always @* begin
        case (branch_op)
            3'b000: taken = (a == b);                 // BEQ
            3'b001: taken = (a != b);                 // BNE
            3'b100: taken = ($signed(a) < $signed(b)); // BLT
            3'b101: taken = ($signed(a) >= $signed(b));// BGE
            3'b110: taken = (a < b);                  // BLTU
            3'b111: taken = (a >= b);                 // BGEU
            default: taken = 1'b0;
        endcase
    end
endmodule
