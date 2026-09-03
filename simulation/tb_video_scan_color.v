`timescale 1ns/1ps

module tb_video_scan_color;

    reg clk;
    reg rst;

    reg [10:0] h_count;
    reg [9:0] v_count;

    reg hsync_in;
    reg vsync_in;
    reg video_active_in;

    reg [7:0] fb_data;

    wire [16:0] fb_addr;
    wire hsync_out;
    wire vsync_out;
    wire video_active_out;

    wire [7:0] red;
    wire [7:0] green;
    wire [7:0] blue;

    integer errors;


    // DUT
    video_scan_color dut (
        .clk(clk),
        .rst(rst),
        .h_count(h_count),
        .v_count(v_count),
        .hsync_in(hsync_in),
        .vsync_in(vsync_in),
        .video_active_in(video_active_in),
        .fb_data(fb_data),
        .fb_addr(fb_addr),
        .hsync_out(hsync_out),
        .vsync_out(vsync_out),
        .video_active_out(video_active_out),
        .red(red),
        .green(green),
        .blue(blue)
    );


    // 27 MHz clock
    initial begin
        clk = 0;
        forever #18.518 clk = ~clk;
    end


    // Waveform
    initial begin
        $dumpfile("video_scan_color.vcd");
        $dumpvars(0, tb_video_scan_color);
    end


    // Tests
    initial begin

        errors = 0;

        h_count = 0;
        v_count = 0;
        hsync_in = 1;
        vsync_in = 1;
        video_active_in = 0;
        fb_data = 0;

        // Reset
        rst = 1;
        #100;
        rst = 0;


        // ========================================================
        // TEST 1: Top-left pixel
        // H=104, V=112
        // Address = 0
        // ========================================================

        h_count = 104;
        v_count = 112;
        video_active_in = 1;
        fb_data = 8'b11100000;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd0) begin
            $display("FAIL 1: fb_addr = %0d, expected 0", fb_addr);
            errors = errors + 1;
        end

        if (video_active_out !== 1) begin
            $display("FAIL 1: video_active_out");
            errors = errors + 1;
        end

        if (red !== 8'hFC) begin
            $display("FAIL 1: red = %h, expected FC", red);
            errors = errors + 1;
        end

        if (green !== 8'h00) begin
            $display("FAIL 1: green = %h, expected 00", green);
            errors = errors + 1;
        end

        if (blue !== 8'h00) begin
            $display("FAIL 1: blue = %h, expected 00", blue);
            errors = errors + 1;
        end


        // ========================================================
        // TEST 2: Next pixel
        // H=105, V=112
        // Address = 1
        // ========================================================

        h_count = 105;
        v_count = 112;
        fb_data = 8'b00011100;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd1) begin
            $display("FAIL 2: fb_addr = %0d, expected 1", fb_addr);
            errors = errors + 1;
        end

        if (red !== 8'h00) begin
            $display("FAIL 2: red = %h", red);
            errors = errors + 1;
        end

        if (green !== 8'hFC) begin
            $display("FAIL 2: green = %h, expected FC", green);
            errors = errors + 1;
        end

        if (blue !== 8'h00) begin
            $display("FAIL 2: blue = %h", blue);
            errors = errors + 1;
        end


        // ========================================================
        // TEST 3: Second row
        // H=104, V=113
        // Address = 512
        // ========================================================

        h_count = 104;
        v_count = 113;
        fb_data = 8'b00000011;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd512) begin
            $display("FAIL 3: fb_addr = %0d, expected 512", fb_addr);
            errors = errors + 1;
        end

        if (blue !== 8'hFF) begin
            $display("FAIL 3: blue = %h, expected FF", blue);
            errors = errors + 1;
        end


        // ========================================================
        // TEST 4: Bottom-right pixel
        // H=615, V=367
        // Address = 131071
        // ========================================================

        h_count = 615;
        v_count = 367;
        fb_data = 8'b11111111;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd131071) begin
            $display(
                "FAIL 4: fb_addr = %0d, expected 131071",
                fb_addr
            );
            errors = errors + 1;
        end

        if (red !== 8'hFC) begin
            $display("FAIL 4: red = %h, expected FC", red);
            errors = errors + 1;
        end

        if (green !== 8'hFC) begin
            $display("FAIL 4: green = %h, expected FC", green);
            errors = errors + 1;
        end

        if (blue !== 8'hFF) begin
            $display("FAIL 4: blue = %h, expected FF", blue);
            errors = errors + 1;
        end


        // ========================================================
        // TEST 5: Outside right edge
        // H=616, V=112
        // ========================================================

        h_count = 616;
        v_count = 112;
        fb_data = 8'hFF;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd0) begin
            $display("FAIL 5: fb_addr = %0d, expected 0", fb_addr);
            errors = errors + 1;
        end

        if (video_active_out !== 0) begin
            $display("FAIL 5: video_active_out should be 0");
            errors = errors + 1;
        end

        if (red !== 0 || green !== 0 || blue !== 0) begin
            $display("FAIL 5: RGB should be black");
            errors = errors + 1;
        end


        // ========================================================
        // TEST 6: Outside left edge
        // H=103, V=112
        // ========================================================

        h_count = 103;
        v_count = 112;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd0) begin
            $display("FAIL 6: fb_addr = %0d, expected 0", fb_addr);
            errors = errors + 1;
        end

        if (video_active_out !== 0) begin
            $display("FAIL 6: video_active_out should be 0");
            errors = errors + 1;
        end


        // ========================================================
        // TEST 7: Above image
        // H=104, V=111
        // ========================================================

        h_count = 104;
        v_count = 111;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd0) begin
            $display("FAIL 7: fb_addr = %0d, expected 0", fb_addr);
            errors = errors + 1;
        end

        if (video_active_out !== 0) begin
            $display("FAIL 7: video_active_out should be 0");
            errors = errors + 1;
        end


        // ========================================================
        // TEST 8: Below image
        // H=104, V=368
        // ========================================================

        h_count = 104;
        v_count = 368;

        @(posedge clk);
        #1;

        if (fb_addr !== 17'd0) begin
            $display("FAIL 8: fb_addr = %0d, expected 0", fb_addr);
            errors = errors + 1;
        end

        if (video_active_out !== 0) begin
            $display("FAIL 8: video_active_out should be 0");
            errors = errors + 1;
        end


        // ========================================================
        // TEST 9: HSYNC forwarding
        // ========================================================

        hsync_in = 0;
        vsync_in = 1;

        @(posedge clk);
        #1;

        if (hsync_out !== 0) begin
            $display("FAIL 9: hsync_out should be 0");
            errors = errors + 1;
        end


        // ========================================================
        // TEST 10: VSYNC forwarding
        // ========================================================

        hsync_in = 1;
        vsync_in = 0;

        @(posedge clk);
        #1;

        if (vsync_out !== 0) begin
            $display("FAIL 10: vsync_out should be 0");
            errors = errors + 1;
        end


        // ========================================================
        // TEST 11: video_active_in disabled
        // ========================================================

        h_count = 300;
        v_count = 250;
        fb_data = 8'hFF;
        video_active_in = 0;

        @(posedge clk);
        #1;

        if (video_active_out !== 0) begin
            $display("FAIL 11: video_active_out should be 0");
            errors = errors + 1;
        end

        if (red !== 0 || green !== 0 || blue !== 0) begin
            $display("FAIL 11: RGB should be black");
            errors = errors + 1;
        end


        // ========================================================
        // FINAL RESULT
        // ========================================================

        $display("");
        $display("========================================");
        $display("   VIDEO SCAN COLOR VERIFICATION");
        $display("========================================");

        if (errors == 0) begin
            $display("RESULT: PASS");
            $display("All video scan/color checks passed.");
        end
        else begin
            $display("RESULT: FAIL");
            $display("Total errors: %0d", errors);
        end

        $display("========================================");

        $finish;

    end

endmodule
