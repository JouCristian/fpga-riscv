`timescale 1ns / 1ps

module tb_pc;

    reg clk;
    reg reset;

    wire [31:0] pc;
    reg [31:0] next_pc;

    pc dut (
        .clk(clk),
        .reset(reset),
        .next_pc(next_pc),
        .pc(pc)
    );

    initial begin
        clk = 1'b0;
    end

    always #5 clk = ~clk;

    initial begin
        reset = 1'b1;
        next_pc = 32'h12345678;
        @(posedge clk); #1;
        if (pc !== 32'b0) begin
            $display("FAIL tb_pc reset"); $finish;
        end
        @(negedge clk);
        reset = 1'b0;
        next_pc = 32'd4;
        @(posedge clk); #1;
        if (pc !== 32'd4) begin
            $display("FAIL tb_pc sequential"); $finish;
        end
        @(negedge clk); next_pc = 32'h80;
        @(posedge clk); #1;
        if (pc !== 32'h80) begin
            $display("FAIL tb_pc redirect"); $finish;
        end
        @(posedge clk); #1;
        if (pc !== 32'h80) begin
            $display("FAIL tb_pc hold"); $finish;
        end
        @(negedge clk); reset = 1'b1;
        @(posedge clk); #1;
        if (pc !== 32'b0) begin
            $display("FAIL tb_pc reset again"); $finish;
        end
        $display("PASS tb_pc: reset, sequential, redirect, hold");
        $finish;
    end

    initial begin
        $dumpfile("build/wave/tb_pc.vcd");
        $dumpvars(0, tb_pc);
    end

    initial begin
        $monitor(
            "time=%0t reset=%b pc=0x%08h",
            $time, reset, pc
        );
    end

endmodule
