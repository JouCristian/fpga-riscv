`timescale 1ns / 1ps

module tb_cpu;
    reg clk = 1'b0;
    reg reset = 1'b1;
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire dmem_we, trap;
    wire [3:0] dmem_wstrb, trap_cause;
    reg [31:0] imem [0:4095];
    reg [7:0] memory [0:255];
    reg [7:0] expected_memory [0:255];
    reg [31:0] expected_regs [0:31];
    wire [31:0] aligned_addr = {dmem_addr[31:2], 2'b00};
    integer i, lane, steps, seed, n, op;
    reg [31:0] a, b, expected, old_pc, signed_imm, shift_imm;
    reg [6:0] f7;
    reg [2:0] f3;
    reg expect_store;
    reg [31:0] expected_addr, expected_wdata;
    reg [3:0] expected_strobe;
    reg [255:0] test_name;

    cpu_top dut (
        .clk(clk), .reset(reset), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .dmem_we(dmem_we), .dmem_wstrb(dmem_wstrb), .trap(trap), .trap_cause(trap_cause)
    );
    always #5 clk = ~clk;
    assign imem_rdata = (imem_addr < 32'd16384) ? imem[imem_addr[13:2]] : 32'b0;
    assign dmem_rdata = (aligned_addr < 32'd256) ?
        {memory[aligned_addr+3], memory[aligned_addr+2],
         memory[aligned_addr+1], memory[aligned_addr]} : 32'b0;

    // Only the memory model writes real memory. The scoreboard is separate.
    always @(posedge clk) begin
        if (dmem_we) begin
            if (aligned_addr >= 32'd256) begin
                $display("FAIL store outside test memory"); $finish;
            end
            for (lane = 0; lane < 4; lane = lane + 1)
                if (dmem_wstrb[lane])
                    memory[aligned_addr+lane] <= dmem_wdata[lane*8 +: 8];
        end
    end

    // Encoders construct instructions only. Expected results never use the DUT
    // decoder or its constants. Literal machine instructions also appear below.
    function [31:0] enc_i;
        input [6:0] opcode;
        input [2:0] funct3;
        input [4:0] rd, rs1;
        input [31:0] immediate;
        begin enc_i = {immediate[11:0], rs1, funct3, rd, opcode}; end
    endfunction
    function [31:0] enc_r;
        input [6:0] funct7;
        input [2:0] funct3;
        input [4:0] rd, rs1, rs2;
        begin enc_r = {funct7, rs2, rs1, funct3, rd, 7'h33}; end
    endfunction
    function [31:0] enc_s;
        input [2:0] funct3;
        input [4:0] rs1, rs2;
        input [31:0] immediate;
        begin enc_s = {immediate[11:5], rs2, rs1, funct3, immediate[4:0], 7'h23}; end
    endfunction
    function [31:0] enc_b;
        input [2:0] funct3;
        input [4:0] rs1, rs2;
        input [31:0] immediate;
        begin
            enc_b = {immediate[12], immediate[10:5], rs2, rs1, funct3,
                     immediate[4:1], immediate[11], 7'h63};
        end
    endfunction
    function [31:0] enc_j;
        input [4:0] rd;
        input [31:0] immediate;
        begin enc_j = {immediate[20], immediate[10:1], immediate[11], immediate[19:12], rd, 7'h6f}; end
    endfunction

    task check_state;
        input [31:0] next_addr;
        input integer cause; // -1 means no trap.
        integer r, m;
        begin
            if ((imem_addr !== next_addr) || (trap !== (cause >= 0))) begin
                $display("FAIL %0s step=%0d PC=%h expected=%h trap=%b cause=%d",
                         test_name, steps, imem_addr, next_addr, trap, trap_cause);
                $finish;
            end
            if ((cause >= 0) && (trap_cause !== cause[3:0])) begin
                $display("FAIL %0s trap cause: got=%d expected=%d", test_name, trap_cause, cause);
                $finish;
            end
            for (r = 0; r < 32; r = r + 1) begin
                if (dut.u_regfile.regs[r] !== expected_regs[r]) begin
                    $display("FAIL %0s step=%0d x%0d=%h expected=%h", test_name,
                             steps, r, dut.u_regfile.regs[r], expected_regs[r]);
                    $finish;
                end
            end
            for (m = 0; m < 256; m = m + 1) begin
                if (memory[m] !== expected_memory[m]) begin
                    $display("FAIL %0s memory[%0d]=%h expected=%h", test_name,
                             m, memory[m], expected_memory[m]);
                    $finish;
                end
            end
        end
    endtask

    task reset_core;
        integer r;
        begin
            @(negedge clk); reset = 1'b1;
            #1;
            if ((dmem_we !== 1'b0) || (dmem_wstrb !== 4'b0)) begin
                $display("FAIL reset must suppress memory writes"); $finish;
            end
            @(posedge clk); #1;
            for (r = 0; r < 32; r = r + 1) expected_regs[r] = 32'b0;
            test_name = "reset";
            check_state(32'b0, -1);
            if (trap_cause !== 4'b0) begin
                $display("FAIL reset trap_cause"); $finish;
            end
            reset = 1'b0;
        end
    endtask

    task execute;
        input [255:0] name;
        input [31:0] instr;
        input [4:0] rd;
        input [31:0] result;
        input [31:0] next_addr;
        input integer cause;
        begin
            @(negedge clk);
            test_name = name;
            if (imem_addr >= 32'd16384) begin
                $display("FAIL instruction outside test memory"); $finish;
            end
            imem[imem_addr[13:2]] = instr;
            #1;
            if ((dmem_we !== expect_store) ||
                (dmem_wstrb !== (expect_store ? expected_strobe : 4'b0))) begin
                $display("FAIL %0s write enable/strobe: we=%b strobe=%b", name, dmem_we, dmem_wstrb);
                $finish;
            end
            if (expect_store && ((dmem_addr !== expected_addr) || (dmem_wdata !== expected_wdata))) begin
                $display("FAIL %0s store address/data: addr=%h data=%h", name, dmem_addr, dmem_wdata);
                $finish;
            end
            if ((rd != 0) && (cause < 0)) expected_regs[rd] = result;
            @(posedge clk); #1;
            steps = steps + 1;
            check_state(next_addr, cause);
            expect_store = 1'b0;
        end
    endtask

    task ordinary;
        input [255:0] name;
        input [31:0] instr;
        input [4:0] rd;
        input [31:0] result;
        begin execute(name, instr, rd, result, imem_addr + 32'd4, -1); end
    endtask

    // Load operands with real instructions; never modify the DUT registers.
    task set_reg;
        input [4:0] rd;
        input [31:0] value;
        reg [31:0] upper;
        begin
            upper = (value + 32'h800) & 32'hfffff000;
            ordinary("operand LUI", {upper[31:12], rd, 7'h37}, rd, upper);
            ordinary("operand ADDI", enc_i(7'h13, 0, rd, rd, value), rd, value);
        end
    endtask

    task store;
        input [255:0] name;
        input [2:0] size;
        input [31:0] offset, address;
        input integer bytes;
        integer k;
        begin
            expect_store = 1'b1;
            expected_addr = address;
            expected_wdata = expected_regs[2] << (address[1:0] * 8);
            expected_strobe = ((1 << bytes) - 1) << address[1:0];
            for (k = 0; k < bytes; k = k + 1)
                expected_memory[address+k] = expected_regs[2] >> (8*k);
            ordinary(name, enc_s(size, 1, 2, offset), 0, 0);
        end
    endtask

    task branch_test;
        input [2:0] kind;
        input [4:0] rs1, rs2;
        input take;
        begin
            execute("branch outcome", enc_b(kind, rs1, rs2, 8), 0, 0,
                    imem_addr + (take ? 32'd8 : 32'd4), -1);
        end
    endtask

    task fault_test;
        input [255:0] name;
        input [31:0] instr;
        input integer cause;
        reg [31:0] fault_pc;
        begin
            reset_core;
            set_reg(1, 32'd65);
            set_reg(2, 32'h89abcdef);
            fault_pc = imem_addr;
            execute(name, instr, 0, 0, fault_pc, cause);
            // Changing the instruction bus must not release a latched trap.
            execute("trap holds store", enc_s(0, 1, 2, 0), 0, 0, fault_pc, cause);
            execute("trap holds register", 32'h00100093, 0, 0, fault_pc, cause);
        end
    endtask

    initial begin
        $dumpfile("build/wave/tb_cpu.vcd");
        $dumpvars(0, tb_cpu);
        steps = 0; seed = 32'h13572468; expect_store = 1'b0;
        expected_addr = 0; expected_wdata = 0; expected_strobe = 0;
        for (i = 0; i < 4096; i = i + 1) imem[i] = 32'h00000013;
        for (i = 0; i < 256; i = i + 1) begin
            memory[i] = 8'ha5; expected_memory[i] = 8'ha5;
        end
        reset_core;

        ordinary("literal ADDI", 32'hfff00093, 1, 32'hffffffff);
        ordinary("ADDI negative limit", enc_i(7'h13, 0, 2, 0, -2048), 2, 32'hfffff800);
        ordinary("ADDI positive limit", enc_i(7'h13, 0, 3, 0, 2047), 3, 2047);
        ordinary("ADDI wraparound", enc_i(7'h13, 0, 4, 1, 1), 4, 0);
        ordinary("x0 write ignored", enc_i(7'h13, 0, 0, 0, 123), 0, 0);
        ordinary("x0 read", enc_r(0, 0, 4, 0, 0), 4, 0);
        ordinary("SLTI signed", enc_i(7'h13, 2, 4, 1, 0), 4, 1);
        ordinary("SLTIU sign extension", enc_i(7'h13, 3, 4, 3, -1), 4, 1);
        ordinary("SLTIU equality", enc_i(7'h13, 3, 4, 1, -1), 4, 0);
        ordinary("XORI", enc_i(7'h13, 4, 4, 1, -1), 4, 0);
        ordinary("ORI", enc_i(7'h13, 6, 4, 3, -2048), 4, 32'hffffffff);
        ordinary("ANDI", enc_i(7'h13, 7, 4, 1, 2047), 4, 2047);
        set_reg(1, 32'h80000001);
        ordinary("SLLI 31", enc_i(7'h13, 1, 4, 1, 31), 4, 32'h80000000);
        ordinary("SRLI 31", enc_i(7'h13, 5, 4, 1, 31), 4, 1);
        ordinary("SRAI 31", enc_i(7'h13, 5, 4, 1, 12'h41f), 4, 32'hffffffff);
        ordinary("SRAI zero", enc_i(7'h13, 5, 4, 1, 12'h400), 4, 32'h80000001);
        ordinary("LUI high bit", 32'h876542b7, 5, 32'h87654000);
        ordinary("AUIPC", 32'h00001297, 5, imem_addr + 32'h1000);
        ordinary("AUIPC negative", 32'hfffff297, 5, imem_addr - 32'h1000);

        // Deterministic arithmetic oracle: include extreme signed values and
        // rs2[31:5] != 0, so register shifts must mask to five bits.
        for (n = 0; n < 48; n = n + 1) begin
            a = $random(seed); b = $random(seed);
            case (n)
                0: begin a = 32'h80000000; b = 32'hffffffff; end
                1: begin a = 32'h7fffffff; b = 32'hffffffff; end
                2: begin a = 32'hffffffff; b = 32'd32; end
                3: begin a = 32'h80000001; b = 32'd63; end
                4: begin a = 32'h80000000; b = 32'h80000000; end
                default: begin end
            endcase
            set_reg(1, a); set_reg(2, b);
            for (op = 0; op < 10; op = op + 1) begin
                f7 = 0;
                case (op)
                    0: begin f3 = 0; expected = a + b; end
                    1: begin f3 = 0; f7 = 7'h20; expected = a - b; end
                    2: begin f3 = 1; expected = a << (b % 32); end
                    3: begin f3 = 2; expected = ($signed(a) < $signed(b)) ? 1 : 0; end
                    4: begin f3 = 3; expected = (a < b) ? 1 : 0; end
                    5: begin f3 = 4; expected = a ^ b; end
                    6: begin f3 = 5; expected = a >> (b % 32); end
                    7: begin f3 = 5; f7 = 7'h20; expected = $signed(a) >>> (b % 32); end
                    8: begin f3 = 6; expected = a | b; end
                    9: begin f3 = 7; expected = a & b; end
                    default: begin f3 = 0; expected = 0; end
                endcase
                ordinary("ALU register oracle", enc_r(f7, f3, 3, 1, 2), 3, expected);
            end
            signed_imm = {{20{b[11]}}, b[11:0]};
            for (op = 0; op < 9; op = op + 1) begin
                shift_imm = {27'b0, b[4:0]};
                case (op)
                    0: begin f3 = 0; expected = a + signed_imm; end
                    1: begin f3 = 2; expected = ($signed(a) < $signed(signed_imm)) ? 1 : 0; end
                    2: begin f3 = 3; expected = (a < signed_imm) ? 1 : 0; end
                    3: begin f3 = 4; expected = a ^ signed_imm; end
                    4: begin f3 = 6; expected = a | signed_imm; end
                    5: begin f3 = 7; expected = a & signed_imm; end
                    6: begin f3 = 1; expected = a << (b % 32); end
                    7: begin f3 = 5; expected = a >> (b % 32); end
                    8: begin
                        f3 = 5; shift_imm = shift_imm + 32'h400;
                        expected = $signed(a) >>> (b % 32);
                    end
                    default: begin f3 = 0; expected = 0; end
                endcase
                ordinary("ALU immediate oracle", enc_i(7'h13, f3, 3, 1,
                         (op < 6) ? signed_imm : shift_imm), 3, expected);
            end
        end
        $display("OK arithmetic, logical, shifts, comparisons, U-type and x0");

        set_reg(1, 64); set_reg(2, 32'h80ff7f01);
        store("SW negative offset", 2, -4, 60, 4);
        ordinary("LW negative offset", enc_i(7'h03, 2, 3, 1, -4), 3, 32'h80ff7f01);
        ordinary("LB lane 0", enc_i(7'h03, 0, 3, 1, -4), 3, 1);
        ordinary("LB lane 1", enc_i(7'h03, 0, 3, 1, -3), 3, 127);
        ordinary("LB lane 2", enc_i(7'h03, 0, 3, 1, -2), 3, 32'hffffffff);
        ordinary("LB lane 3", enc_i(7'h03, 0, 3, 1, -1), 3, 32'hffffff80);
        ordinary("LBU lane 3", enc_i(7'h03, 4, 3, 1, -1), 3, 128);
        ordinary("LH lower", enc_i(7'h03, 1, 3, 1, -4), 3, 32'h7f01);
        ordinary("LH upper", enc_i(7'h03, 1, 3, 1, -2), 3, 32'hffff80ff);
        ordinary("LHU upper", enc_i(7'h03, 5, 3, 1, -2), 3, 32'h80ff);
        set_reg(2, 32'hdeadbe80);
        for (n = 0; n < 4; n = n + 1) begin
            store("SB each lane", 0, n, 64+n, 1);
            ordinary("LB after SB", enc_i(7'h03, 0, 3, 1, n), 3, 32'hffffff80);
            ordinary("LBU after SB", enc_i(7'h03, 4, 3, 1, n), 3, 128);
        end
        store("SH lower", 1, 4, 68, 2);
        store("SH upper", 1, 6, 70, 2);
        ordinary("LW after SH", enc_i(7'h03, 2, 3, 1, 4), 3, 32'hbe80be80);
        ordinary("load x0", enc_i(7'h03, 2, 0, 1, 4), 0, 0);
        $display("OK loads/stores: sign extension, all byte lanes, partial writes");

        set_reg(1, 32'h80000000); set_reg(2, 32'h7fffffff);
        branch_test(0, 1, 1, 1); branch_test(0, 1, 2, 0);
        branch_test(1, 1, 2, 1); branch_test(1, 1, 1, 0);
        branch_test(4, 1, 2, 1); branch_test(4, 2, 1, 0);
        branch_test(5, 2, 1, 1); branch_test(5, 1, 2, 0);
        branch_test(6, 2, 1, 1); branch_test(6, 1, 2, 0);
        branch_test(7, 1, 2, 1); branch_test(7, 2, 1, 0);
        branch_test(4, 1, 1, 0); branch_test(5, 1, 1, 1);
        branch_test(6, 1, 1, 0); branch_test(7, 1, 1, 1);
        execute("backward BEQ literal", 32'hfe000ee3, 0, 0, imem_addr-4, -1);
        execute("branch +2048 bit11", enc_b(0, 0, 0, 2048), 0, 0, imem_addr+2048, -1);
        execute("branch -2048", enc_b(0, 0, 0, -2048), 0, 0, imem_addr-2048, -1);
        ordinary("untaken misaligned branch", enc_b(1, 0, 0, 2), 0, 0);
        old_pc = imem_addr;
        execute("JAL forward", enc_j(5, 12), 5, old_pc+4, old_pc+12, -1);
        old_pc = imem_addr;
        execute("JAL backward literal", 32'hffdff36f, 6, old_pc+4, old_pc-4, -1);
        execute("JAL x0", enc_j(0, 4), 0, 0, imem_addr+4, -1);
        set_reg(1, 1029);
        old_pc = imem_addr;
        execute("JALR bit0 and rd=rs1", enc_i(7'h67, 0, 1, 1, -4), 1, old_pc+4, 1024, -1);
        ordinary("FENCE", 32'h0ff0000f, 0, 0);
        ordinary("FENCE reserved fields", 32'hfff0808f, 0, 0);
        $display("OK all branch outcomes, backward offsets, JAL/JALR, FENCE");

        // An uninterrupted program: sum 1+2+3+4+5, call/return, store.
        reset_core;
        imem[0] = 32'h00500093; // addi x1,x0,5
        imem[1] = 32'h00000113; // addi x2,x0,0
        imem[2] = 32'h00110133; // add x2,x2,x1
        imem[3] = 32'hfff08093; // addi x1,x1,-1
        imem[4] = 32'hfe009ce3; // bne x1,x0,-8
        imem[5] = 32'h010002ef; // jal x5,+16
        imem[6] = 32'h0c202023; // sw x2,192(x0)
        imem[7] = 32'h00000073; // ecall
        imem[8] = 32'h00000013;
        imem[9] = 32'h00110113; // addi x2,x2,1
        imem[10] = 32'h00028067;// jalr x0,x5,0
        for (n = 0; n < 22; n = n + 1) begin @(posedge clk); #1; end
        expected_regs[1] = 0; expected_regs[2] = 16; expected_regs[5] = 24;
        expected_memory[192] = 16; expected_memory[193] = 0;
        expected_memory[194] = 0; expected_memory[195] = 0;
        test_name = "uninterrupted program";
        check_state(28, 11);
        $display("OK uninterrupted loop + call/return + store program (22 clocks)");

        fault_test("ECALL", 32'h00000073, 11);
        fault_test("EBREAK", 32'h00100073, 3);
        fault_test("invalid opcode", 32'hffffffff, 2);
        fault_test("M extension rejected", enc_r(1, 0, 3, 1, 2), 2);
        fault_test("bad OP funct7", enc_r(7'h20, 1, 3, 1, 2), 2);
        fault_test("bad SLLI upper bits", enc_i(7'h13, 1, 3, 1, 12'h020), 2);
        fault_test("bad SRLI upper bits", enc_i(7'h13, 5, 3, 1, 12'h200), 2);
        fault_test("bad load funct3", enc_i(7'h03, 3, 3, 1, 0), 2);
        fault_test("bad store funct3", enc_s(4, 1, 2, 0), 2);
        fault_test("bad branch funct3", enc_b(2, 1, 2, 4), 2);
        fault_test("bad JALR funct3", enc_i(7'h67, 1, 3, 1, 0), 2);
        fault_test("CSR rejected", 32'h300091f3, 2);
        fault_test("FENCE.I rejected", 32'h0000100f, 2);
        fault_test("C extension rejected", 32'h00000001, 2);
        fault_test("LH misaligned", enc_i(7'h03, 1, 3, 1, 0), 4);
        fault_test("LHU misaligned", enc_i(7'h03, 5, 3, 1, 0), 4);
        fault_test("LW misaligned", enc_i(7'h03, 2, 3, 1, 0), 4);
        fault_test("load x0 still traps", enc_i(7'h03, 2, 0, 1, 0), 4);
        fault_test("SH misaligned", enc_s(1, 1, 2, 0), 6);
        fault_test("SW misaligned", enc_s(2, 1, 2, 0), 6);
        fault_test("taken branch alignment", enc_b(0, 1, 1, 2), 0);
        fault_test("JAL alignment no link", enc_j(3, 2), 0);
        fault_test("JALR preserves bit1", enc_i(7'h67, 0, 3, 1, 2), 0);
        reset_core;
        ordinary("reset resumes execution", 32'h00700093, 1, 7);
        $display("PASS tb_cpu: %0d checked instruction cycles + 22 program clocks; 23 trap cases", steps);
        $finish;
    end
    initial begin
        #100000;
        $display("FAIL tb_cpu timeout"); $finish;
    end
endmodule
