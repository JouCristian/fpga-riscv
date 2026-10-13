`timescale 1ns / 1ps

module tb_imm_gen;
    reg [31:0] instr;
    reg [2:0] imm_sel;
    wire [31:0] imm;
    integer value, bit_index, checks;
    reg [31:0] offset;
    imm_gen dut (.instr(instr), .imm_sel(imm_sel), .imm(imm));

    task check;
        input [31:0] expected;
        begin
            #1;
            checks = checks + 1;
            if (imm !== expected) begin
                $display("FAIL tb_imm_gen sel=%d instr=%h got=%h expected=%h",
                         imm_sel, instr, imm, expected);
                $finish;
            end
        end
    endtask

    task check_jump;
        input [31:0] displacement;
        begin
            imm_sel = 4;
            instr = {displacement[20], displacement[10:1], displacement[11],
                     displacement[19:12], 5'd7, 7'h6f};
            check(displacement);
        end
    endtask

    initial begin
        $dumpfile("build/wave/tb_imm_gen.vcd");
        $dumpvars(0, tb_imm_gen);
        checks = 0;
        // Exhaust all 12-bit I/S immediates and all 13-bit even B offsets.
        // Non-immediate fields are deliberately nonzero.
        for (value = -2048; value < 2048; value = value + 1) begin
            imm_sel = 0;
            instr = {value[11:0], 5'd31, 3'b111, 5'd30, 7'h13};
            check(value);
            imm_sel = 1;
            instr = {value[11:5], 5'd31, 5'd30, 3'b010, value[4:0], 7'h23};
            check(value);
            offset = value * 2;
            imm_sel = 2;
            instr = {offset[12], offset[10:5], 5'd31, 5'd30, 3'b111,
                     offset[4:1], offset[11], 7'h63};
            check(offset);
        end
        // Walking bits and negative complements exercise every J bit position.
        check_jump(0);
        check_jump(1048574);
        check_jump(-1048576);
        check_jump(-2);
        for (bit_index = 1; bit_index < 20; bit_index = bit_index + 1) begin
            check_jump(32'd1 << bit_index);
            check_jump(32'hfffffffe ^ (32'd1 << bit_index));
        end
        // Literal encodings prevent an encoder/decoder copy mistake hiding.
        imm_sel = 2; instr = 32'hfe000ee3; check(-4);
        imm_sel = 4; instr = 32'hffdff36f; check(-4);
        imm_sel = 4; instr = 32'h8000006f; check(-1048576);
        imm_sel = 4; instr = 32'h7ffff06f; check(1048574);
        imm_sel = 3;
        for (bit_index = 12; bit_index < 32; bit_index = bit_index + 1) begin
            offset = 32'd1 << bit_index;
            instr = offset | 32'h00000fb7;
            check(offset);
        end
        instr = 32'hfffff037; check(32'hfffff000);
        instr = 32'h00000037; check(0);
        imm_sel = 7; instr = 32'hffffffff; check(0);
        $display("PASS tb_imm_gen: %0d checks (exhaustive I/S/B, J/U boundaries)", checks);
        $finish;
    end
endmodule
