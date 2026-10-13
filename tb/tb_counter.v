`timescale 1ns/1ps

module tb_counter;

    reg clk;
    reg reset;
    reg enable;

    wire [3:0] count;

    counter dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .count(count)
    );

    initial begin
        clk = 1'b0;
    end

    always #5 clk = ~clk;

    initial begin
        reset = 1'b1;
        enable = 1'b0;

        #12;
        reset = 1'b0;
        enable = 1'b1;

        #40;
        enable = 1'b0;

        #20;
        enable = 1'b1;

        #20 
        reset = 1'b1;

        #20
        reset = 1'b0;

        #20;
        $finish;
    end

    initial begin
        $monitor("At time %t, count = %d, reset = %b, enable = %b", $time, count, reset, enable);
    end

    initial begin
        $dumpfile("build/wave/tb_counter.vcd");
        $dumpvars(0, tb_counter);
    end

endmodule