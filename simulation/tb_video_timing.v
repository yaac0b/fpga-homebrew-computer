`timescale 1ns/1ps

module tb_video_timing;

    reg clk;
    reg rst;

    wire hsync;
    wire vsync;
    wire video_active;
    wire [10:0] h_count;
    wire [9:0]  v_count;

    integer errors;
    integer h_wraps;
    integer v_wraps;

    // Previous coordinates.
    // The outputs from video_timing are registered,
    // so they correspond to the previous counter values.
    reg [10:0] prev_h;
    reg [9:0]  prev_v;
    reg        have_prev;


    // ============================================================
    // DUT
    // ============================================================

    video_timing dut (
        .clk          (clk),
        .rst          (rst),
        .hsync        (hsync),
        .vsync        (vsync),
        .video_active (video_active),
        .h_count      (h_count),
        .v_count      (v_count)
    );


    // ============================================================
    // 27 MHz clock
    // Period = 37.037 ns
    // ============================================================

    initial begin
        clk = 1'b0;

        forever #18.518 clk = ~clk;
    end


    // ============================================================
    // Reset and simulation control
    // ============================================================

    initial begin

        errors    = 0;
        h_wraps   = 0;
        v_wraps   = 0;

        prev_h    = 11'd0;
        prev_v    = 10'd0;
        have_prev = 1'b0;

        // Apply reset
        rst = 1'b1;

        #100;

        // Release reset
        rst = 1'b0;

        // Run slightly more than one complete frame
        #17000000;


        // ========================================================
        // RESULTS
        // ========================================================

        $display("");
        $display("========================================");
        $display("       VIDEO TIMING VERIFICATION");
        $display("========================================");

        $display("Horizontal wrap events: %0d", h_wraps);
        $display("Vertical wrap events:   %0d", v_wraps);

        // At least one complete frame should have occurred
        if (h_wraps < 500) begin
            $display("FAIL: Too few horizontal lines detected.");
            errors = errors + 1;
        end

        if (v_wraps < 1) begin
            $display("FAIL: No complete frame detected.");
            errors = errors + 1;
        end


        if (errors == 0) begin

            $display("RESULT: PASS");
            $display("All video timing checks passed.");

        end
        else begin

            $display("RESULT: FAIL");
            $display("Total errors: %0d", errors);

        end

        $display("========================================");

        $finish;

    end


    // ============================================================
    // Waveform dump for GTKWave
    // ============================================================

    initial begin

        $dumpfile("video_timing.vcd");

        $dumpvars(0, tb_video_timing);

    end


    // ============================================================
    // Verification
    // ============================================================

    always @(posedge clk) begin

        // Wait until all nonblocking assignments in the DUT
        // have completed.
        #1;

        if (!rst) begin


            // ----------------------------------------------------
            // Counter range checks
            // ----------------------------------------------------

            if (h_count > 11'd857) begin

                $display(
                    "FAIL: h_count exceeded 857 at %0t ns",
                    $time
                );

                errors = errors + 1;

            end


            if (v_count > 10'd524) begin

                $display(
                    "FAIL: v_count exceeded 524 at %0t ns",
                    $time
                );

                errors = errors + 1;

            end


            // ----------------------------------------------------
            // Count horizontal lines
            // ----------------------------------------------------

            if (h_count == 11'd0) begin

                h_wraps = h_wraps + 1;

            end


            // ----------------------------------------------------
            // Count complete frames
            // ----------------------------------------------------

            if ((h_count == 11'd0) &&
                (v_count == 10'd0)) begin

                v_wraps = v_wraps + 1;

            end


            // ----------------------------------------------------
            // Check registered video_active
            //
            // video_active corresponds to prev_h / prev_v
            // because the DUT registers the output.
            // ----------------------------------------------------

            if (have_prev) begin

                if ((prev_h < 11'd720) &&
                    (prev_v < 10'd480)) begin

                    // Active video area
                    if (video_active !== 1'b1) begin

                        $display(
                            "FAIL: video_active should be HIGH at H=%0d V=%0d",
                            prev_h,
                            prev_v
                        );

                        errors = errors + 1;

                    end

                end
                else begin

                    // Blanking area
                    if (video_active !== 1'b0) begin

                        $display(
                            "FAIL: video_active should be LOW at H=%0d V=%0d",
                            prev_h,
                            prev_v
                        );

                        errors = errors + 1;

                    end

                end


                // ------------------------------------------------
                // Check HSYNC
                // ------------------------------------------------

                if ((prev_h >= 11'd736) &&
                    (prev_h <  11'd798)) begin

                    // HSYNC active-low region
                    if (hsync !== 1'b0) begin

                        $display(
                            "FAIL: HSYNC should be LOW at H=%0d",
                            prev_h
                        );

                        errors = errors + 1;

                    end

                end
                else begin

                    // HSYNC inactive
                    if (hsync !== 1'b1) begin

                        $display(
                            "FAIL: HSYNC should be HIGH at H=%0d",
                            prev_h
                        );

                        errors = errors + 1;

                    end

                end


                // ------------------------------------------------
                // Check VSYNC
                // ------------------------------------------------

                if ((prev_v >= 10'd489) &&
                    (prev_v <  10'd495)) begin

                    // VSYNC active-low region
                    if (vsync !== 1'b0) begin

                        $display(
                            "FAIL: VSYNC should be LOW at V=%0d",
                            prev_v
                        );

                        errors = errors + 1;

                    end

                end
                else begin

                    // VSYNC inactive
                    if (vsync !== 1'b1) begin

                        $display(
                            "FAIL: VSYNC should be HIGH at V=%0d",
                            prev_v
                        );

                        errors = errors + 1;

                    end

                end

            end


            // ----------------------------------------------------
            // Save current coordinates for next cycle
            // ----------------------------------------------------

            prev_h    = h_count;
            prev_v    = v_count;
            have_prev = 1'b1;

        end

    end

endmodule
