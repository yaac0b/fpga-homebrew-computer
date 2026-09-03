`timescale 1ns/1ps

module tb_tmds_encoder;

    reg        clk;
    reg        rst;
    reg [7:0]  data_in;
    reg        c0;
    reg        c1;
    reg        de;

    wire [9:0] data_out;

    integer errors;

    // DUT
    tmds_encoder dut (
        .clk      (clk),
        .rst      (rst),
        .data_in  (data_in),
        .c0       (c0),
        .c1       (c1),
        .de       (de),
        .data_out (data_out)
    );

    // 27 MHz-like simulation clock
    always #18.518 clk = ~clk;

    // ------------------------------------------------------------
    // Check control symbol
    // ------------------------------------------------------------
    task check_control;
        input        tc0;
        input        tc1;
        input [9:0]  expected;
        begin
            @(negedge clk);

            c0 = tc0;
            c1 = tc1;
            de = 1'b0;
            data_in = 8'h00;

            @(posedge clk);
            #1;

            if (data_out !== expected) begin
                $display(
                    "FAIL: control c1c0=%b%b expected=%b got=%b",
                    tc1, tc0, expected, data_out
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS: control c1c0=%b%b = %b",
                    tc1, tc0, data_out
                );
            end
        end
    endtask

    // ------------------------------------------------------------
    // Check active video output is not a control symbol
    // ------------------------------------------------------------
    task check_video;
        input [7:0] pixel;
        begin
            @(negedge clk);

            data_in = pixel;
            c0 = 1'b0;
            c1 = 1'b0;
            de = 1'b1;

            @(posedge clk);
            #1;

            if (data_out === 10'b1101010100 ||
                data_out === 10'b0010101011 ||
                data_out === 10'b0101010100 ||
                data_out === 10'b1010101011) begin

                $display(
                    "FAIL: video pixel %h produced control symbol %b",
                    pixel, data_out
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS: video pixel %h -> %b",
                    pixel, data_out
                );
            end
        end
    endtask
    // ------------------------------------------------------------
    // Main test

    // ------------------------------------------------------------
    initial begin


        clk     = 1'b0;
        rst     = 1'b1;
        data_in = 8'h00;
        c0      = 1'b0;
        c1      = 1'b0;

        de      = 1'b0;
        errors  = 0;


        $dumpfile("tmds_encoder.vcd");
        $dumpvars(0, tb_tmds_encoder);


        // Hold reset for several clocks
        repeat (5) @(posedge clk);


        @(negedge clk);
        rst = 1'b0;


        // Allow DUT one clock after reset
        @(posedge clk);
        #1;


        $display("");
        $display("========================================");

        $display("       TMDS ENCODER VERIFICATION");

        $display("========================================");


        // --------------------------------------------------------
        // TMDS control symbols
        //

        // c1c0 = 00 -> 1101010100
        // c1c0 = 01 -> 0010101011
        // c1c0 = 10 -> 0101010100
        // c1c0 = 11 -> 1010101011
        // --------------------------------------------------------

        check_control(
            1'b0,
            1'b0,
            10'b1101010100
        );

        check_control(
            1'b1,
            1'b0,
            10'b0010101011
        );

        check_control(
            1'b0,
            1'b1,
            10'b0101010100
        );

        check_control(
            1'b1,
            1'b1,
            10'b1010101011
        );

        // --------------------------------------------------------
        // Active video tests
        // --------------------------------------------------------

        check_video(8'h00);
        check_video(8'hFF);
        check_video(8'h55);
        check_video(8'hAA);
        check_video(8'h12);
        check_video(8'h80);

        // --------------------------------------------------------
        // Final result
        // --------------------------------------------------------

        $display("");
        $display("========================================");

        if (errors == 0) begin
            $display("       RESULT: PASS");
            $display("All TMDS encoder checks passed.");
        end
        else begin
            $display("       RESULT: FAIL");
            $display("Total errors: %0d", errors);
        end

        $display("========================================");

        #100;
        $finish;
    end

endmodule
