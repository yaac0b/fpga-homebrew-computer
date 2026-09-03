`timescale 1ns/1ps

module tb_gpu_pixel;

    reg clk;
    reg rst;

    reg [8:0] gpu_x;
    reg [7:0] gpu_y;
    reg [7:0] gpu_color;
    reg gpu_draw;

    wire [16:0] fb_addr;
    wire [7:0] fb_data;
    wire fb_we;

    integer errors;

    gpu_pixel dut (
        .clk(clk),
        .rst(rst),
        .gpu_x(gpu_x),
        .gpu_y(gpu_y),
        .gpu_color(gpu_color),
        .gpu_draw(gpu_draw),
        .fb_addr(fb_addr),
        .fb_data(fb_data),
        .fb_we(fb_we)
    );

    // Clock
    initial begin
        clk = 0;
        forever #18.518 clk = ~clk;
    end

    // Waveform
    initial begin
        $dumpfile("gpu_pixel.vcd");
        $dumpvars(0, tb_gpu_pixel);
    end

    initial begin

        errors = 0;

        gpu_x = 0;
        gpu_y = 0;
        gpu_color = 0;
        gpu_draw = 0;

        // Reset
        rst = 1;
        #100;
        rst = 0;

        // TEST 1: First pixel (0,0)
        gpu_x = 9'd0;
        gpu_y = 8'd0;
        gpu_color = 8'hAA;
        gpu_draw = 1;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd0) begin
            $display("FAIL 1: fb_addr = %0d, expected 0", fb_addr);
            errors = errors + 1;
        end

        if (fb_data !== 8'hAA) begin
            $display("FAIL 1: fb_data = %h, expected AA", fb_data);
            errors = errors + 1;
        end

        if (fb_we !== 1'b1) begin
            $display("FAIL 1: fb_we should be 1");
            errors = errors + 1;
        end


        // TEST 2: x = 1, y = 0
        gpu_x = 9'd1;
        gpu_y = 8'd0;
        gpu_color = 8'h55;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd1) begin
            $display("FAIL 2: fb_addr = %0d, expected 1", fb_addr);
            errors = errors + 1;
        end

        if (fb_data !== 8'h55) begin
            $display("FAIL 2: fb_data = %h, expected 55", fb_data);
            errors = errors + 1;
        end

        if (fb_we !== 1'b1) begin
            $display("FAIL 2: fb_we should be 1");
            errors = errors + 1;
        end


        // TEST 3: x = 0, y = 1
        gpu_x = 9'd0;
        gpu_y = 8'd1;
        gpu_color = 8'h12;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd512) begin
            $display("FAIL 3: fb_addr = %0d, expected 512", fb_addr);
            errors = errors + 1;
        end

        if (fb_data !== 8'h12) begin
            $display("FAIL 3: fb_data = %h, expected 12", fb_data);
            errors = errors + 1;
        end


        // TEST 4: x = 511, y = 255 (last framebuffer pixel)
        gpu_x = 9'd511;
        gpu_y = 8'd255;
        gpu_color = 8'hFF;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd131071) begin
            $display(
                "FAIL 4: fb_addr = %0d, expected 131071",
                fb_addr
            );
            errors = errors + 1;
        end

        if (fb_data !== 8'hFF) begin
            $display("FAIL 4: fb_data = %h, expected FF", fb_data);
            errors = errors + 1;
        end

        if (fb_we !== 1'b1) begin
            $display("FAIL 4: fb_we should be 1");
            errors = errors + 1;
        end


        // TEST 5: gpu_draw disabled
        gpu_x = 9'd100;
        gpu_y = 8'd50;
        gpu_color = 8'h77;
        gpu_draw = 0;

        @(posedge clk);
        #1;

        if (fb_we !== 1'b0) begin
            $display("FAIL 5: fb_we should be 0 when gpu_draw is 0");
            errors = errors + 1;
        end


        // TEST 6: Another draw after disabled
        gpu_x = 9'd100;
        gpu_y = 8'd50;
        gpu_color = 8'h77;
        gpu_draw = 1;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd25700) begin
            $display("FAIL 6: fb_addr = %0d, expected 25700", fb_addr);
            errors = errors + 1;
        end

        if (fb_data !== 8'h77) begin
            $display("FAIL 6: fb_data = %h, expected 77", fb_data);
            errors = errors + 1;
        end

        if (fb_we !== 1'b1) begin
            $display("FAIL 6: fb_we should be 1");
            errors = errors + 1;
        end


        // FINAL RESULT
        $display("");
        $display("========================================");
        $display("      GPU PIXEL VERIFICATION");
        $display("========================================");

        if (errors == 0) begin
            $display("RESULT: PASS");
            $display("All GPU pixel checks passed.");
        end
        else begin
            $display("RESULT: FAIL");
            $display("Total errors: %0d", errors);
        end

        $display("========================================");

        $finish;

    end

endmodule
