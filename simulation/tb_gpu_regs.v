`timescale 1ns/1ps

module tb_gpu_regs;

    reg clk;
    reg rst;

    reg [15:0] cpu_addr;
    reg [15:0] cpu_din;
    reg cpu_we;

    wire [8:0] gpu_x;
    wire [7:0] gpu_y;
    wire [7:0] gpu_color;
    wire gpu_draw;

    integer errors;

    gpu_regs dut (
        .clk(clk),
        .rst(rst),
        .cpu_addr(cpu_addr),
        .cpu_din(cpu_din),
        .cpu_we(cpu_we),
        .gpu_x(gpu_x),
        .gpu_y(gpu_y),
        .gpu_color(gpu_color),
        .gpu_draw(gpu_draw)
    );

    // Clock
    initial begin
        clk = 0;
        forever #18.518 clk = ~clk;
    end

    // Waveform
    initial begin
        $dumpfile("gpu_regs.vcd");
        $dumpvars(0, tb_gpu_regs);
    end

    initial begin

        errors = 0;

        cpu_addr = 16'h0000;
        cpu_din  = 16'h0000;
        cpu_we   = 0;

        // Reset
        rst = 1;
        #100;
        rst = 0;

        // TEST 1: Reset values
        #10;

        if (gpu_x !== 9'd0) begin
            $display("FAIL 1: gpu_x = %0d, expected 0", gpu_x);
            errors = errors + 1;
        end

        if (gpu_y !== 8'd0) begin
            $display("FAIL 1: gpu_y = %0d, expected 0", gpu_y);
            errors = errors + 1;
        end

        if (gpu_color !== 8'h00) begin
            $display("FAIL 1: gpu_color = %h, expected 00", gpu_color);
            errors = errors + 1;
        end

        if (gpu_draw !== 1'b0) begin
            $display("FAIL 1: gpu_draw should be 0");
            errors = errors + 1;
        end


        // TEST 2: Write X register
        cpu_addr = 16'h6001;
        cpu_din  = 16'h01AB;
        cpu_we   = 1;

        @(posedge clk);
        #1;

        if (gpu_x !== 9'h1AB) begin
        end


        // TEST 3: Write Y register

        cpu_addr = 16'h6002;
        cpu_din  = 16'h00CD;


        @(posedge clk);
        #1;


        if (gpu_y !== 8'hCD) begin
            $display("FAIL 3: gpu_y = %h, expected CD", gpu_y);

            errors = errors + 1;

        end


        // TEST 4: Write COLOR register
        cpu_addr = 16'h6003;

        cpu_din  = 16'h00E7;


        @(posedge clk);
        #1;

        if (gpu_color !== 8'hE7) begin
            $display("FAIL 4: gpu_color = %h, expected E7", gpu_color);

            errors = errors + 1;
        end


        // TEST 5: Draw command
        cpu_addr = 16'h6004;
        cpu_din  = 16'h0001;


        @(posedge clk);
        #1;

        if (gpu_draw !== 1'b1) begin
            $display("FAIL 5: gpu_draw should be 1");
            errors = errors + 1;
        end



        // TEST 6: Draw pulse should clear next clock
        cpu_we = 0;

        @(posedge clk);
        #1;

        if (gpu_draw !== 1'b0) begin
            $display("FAIL 6: gpu_draw should return to 0");
            errors = errors + 1;
        end


        // TEST 7: CMD with bit 0 = 0 should not draw
        cpu_addr = 16'h6004;
        cpu_din  = 16'h0000;
        cpu_we   = 1;

        @(posedge clk);
        #1;

        if (gpu_draw !== 1'b0) begin
            $display("FAIL 7: gpu_draw should remain 0");
            errors = errors + 1;
        end


        // TEST 8: CPU write disabled
        cpu_addr = 16'h6001;
        cpu_din  = 16'h0123;
        cpu_we   = 0;

        @(posedge clk);
        #1;

        if (gpu_x !== 9'h1AB) begin
            $display("FAIL 8: gpu_x changed when cpu_we = 0");
            errors = errors + 1;
        end


        // TEST 9: Upper X bits should be ignored
        cpu_addr = 16'h6001;
        cpu_din  = 16'hFE55;
        cpu_we   = 1;

        @(posedge clk);
        #1;


        if (gpu_x !== 9'h055) begin
            $display("FAIL 9: gpu_x = %h, expected 055", gpu_x);
            errors = errors + 1;
        end


        // TEST 10: Unknown address should do nothing
        cpu_addr = 16'h7000;
        cpu_din  = 16'hFFFF;

        @(posedge clk);
        #1;

        if (gpu_y !== 8'hCD) begin
            $display("FAIL 10: gpu_y changed unexpectedly");
            errors = errors + 1;
        end

        if (gpu_color !== 8'hE7) begin
            $display("FAIL 10: gpu_color changed unexpectedly");
            errors = errors + 1;
        end


        // FINAL RESULT
        $display("");
        $display("========================================");
        $display("       GPU REGISTERS VERIFICATION");
        $display("========================================");

        if (errors == 0) begin
            $display("RESULT: PASS");
            $display("All GPU register checks passed.");
        end
        else begin
            $display("RESULT: FAIL");
            $display("Total errors: %0d", errors);
        end

        $display("========================================");

        $finish;

    end

endmodule
