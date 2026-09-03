`timescale 1ns/1ps

module tb_tmds_serializer;

    reg pixel_clk;
    reg serial_clk;
    reg rst;

    reg [9:0] tmds_r;
    reg [9:0] tmds_g;
    reg [9:0] tmds_b;

    wire serial_r;
    wire serial_g;
    wire serial_b;

    integer errors;

    tmds_serializer dut (
        .pixel_clk(pixel_clk),
        .serial_clk(serial_clk),
        .rst(rst),
        .tmds_r(tmds_r),
        .tmds_g(tmds_g),
        .tmds_b(tmds_b),
        .serial_r(serial_r),
        .serial_g(serial_g),
        .serial_b(serial_b)
    );

    // Pixel clock
    initial begin
        pixel_clk = 0;
        forever #18.518 pixel_clk = ~pixel_clk;
    end

    // Serial clock
    // 10x pixel clock
    initial begin
        serial_clk = 0;
        forever #1.8518 serial_clk = ~serial_clk;
    end

    initial begin
        $dumpfile("tmds_serializer.vcd");
        $dumpvars(0, tb_tmds_serializer);
    end

    initial begin

        errors = 0;

        tmds_r = 10'b1010101010;
        tmds_g = 10'b1100110011;
        tmds_b = 10'b1111000011;

        rst = 1;

        #100;

        rst = 0;

        // Allow one pixel clock to load the serializers
        @(posedge pixel_clk);
        #1;

        // Allow serialized bits to appear
        repeat (12) begin
            @(posedge serial_clk);
            #0.5;
        end

        // Basic activity check
        if (serial_r !== 1'b0 && serial_r !== 1'b1) begin
            $display("FAIL: serial_r is unknown");
            errors = errors + 1;
        end

        if (serial_g !== 1'b0 && serial_g !== 1'b1) begin
            $display("FAIL: serial_g is unknown");
            errors = errors + 1;
        end

        if (serial_b !== 1'b0 && serial_b !== 1'b1) begin
            $display("FAIL: serial_b is unknown");
            errors = errors + 1;
        end

        $display("");
        $display("========================================");
        $display("     TMDS SERIALIZER VERIFICATION");
        $display("========================================");

        if (errors == 0) begin
            $display("RESULT: PASS");
            $display("TMDS serializer produced valid serial outputs.");
        end
        else begin
            $display("RESULT: FAIL");
            $display("Total errors: %0d", errors);
        end

        $display("========================================");

        $finish;

    end

endmodule
