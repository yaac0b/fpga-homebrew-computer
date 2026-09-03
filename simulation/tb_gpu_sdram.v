`timescale 1ns/1ps

module tb_gpu_sdram;

    reg mem_clk;
    reg mem_clk_sdram;
    reg resetn;

    reg gpu_wr;
    reg [16:0] gpu_addr;
    reg [7:0] gpu_data;
    wire gpu_busy;

    reg video_req;
    reg [16:0] video_addr;
    wire video_valid;
    wire [7:0] video_data;

    wire [31:0] SDRAM_DQ;
    wire [10:0] SDRAM_A;
    wire [1:0] SDRAM_BA;

    wire SDRAM_nCS;
    wire SDRAM_nWE;
    wire SDRAM_nRAS;
    wire SDRAM_nCAS;

    wire SDRAM_CLK;
    wire SDRAM_CKE;
    wire [3:0] SDRAM_DQM;

    integer errors;

    // DUT
    gpu_sdram dut (
        .mem_clk(mem_clk),
        .mem_clk_sdram(mem_clk_sdram),
        .resetn(resetn),

        .gpu_wr(gpu_wr),
        .gpu_addr(gpu_addr),
        .gpu_data(gpu_data),
        .gpu_busy(gpu_busy),

        .video_req(video_req),
        .video_addr(video_addr),
        .video_valid(video_valid),
        .video_data(video_data),

        .SDRAM_DQ(SDRAM_DQ),
        .SDRAM_A(SDRAM_A),
        .SDRAM_BA(SDRAM_BA),

        .SDRAM_nCS(SDRAM_nCS),
        .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS),

        .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .SDRAM_DQM(SDRAM_DQM)
    );

    // 64.8 MHz memory clock
    initial begin
        mem_clk = 0;
        forever #7.716 mem_clk = ~mem_clk;
    end

    // SDRAM clock
    initial begin
        mem_clk_sdram = 0;
        forever #7.716 mem_clk_sdram = ~mem_clk_sdram;
    end

    // Waveform
    initial begin
        $dumpfile("gpu_sdram.vcd");
        $dumpvars(0, tb_gpu_sdram);
    end

    initial begin

        errors = 0;

        gpu_wr = 0;
        gpu_addr = 17'd0;
        gpu_data = 8'h00;

        video_req = 0;
        video_addr = 17'd0;

        // Reset
        resetn = 0;
        #100;
        resetn = 1;

        // For wrapper testing, pretend SDRAM is immediately available.
        force dut.sdram_busy = 1'b0;


        // =========================================================
        // TEST 1: GPU WRITE
        // =========================================================

        gpu_addr = 17'd1234;
        gpu_data = 8'hA5;
        gpu_wr = 1;

        @(posedge mem_clk);
        #1;

        if (gpu_busy !== 1'b1) begin
            $display("FAIL 1: gpu_busy should be 1");
            errors = errors + 1;
        end

        if (dut.sdram_wr !== 1'b1) begin
            $display("FAIL 1: sdram_wr should be 1");
            errors = errors + 1;
        end

        if (dut.sdram_addr !== 23'd1234) begin
            $display(
                "FAIL 1: sdram_addr = %0d, expected 1234",
                dut.sdram_addr
            );
            errors = errors + 1;
        end

        if (dut.sdram_din !== 8'hA5) begin
            $display(
                "FAIL 1: sdram_din = %h, expected A5",
                dut.sdram_din
            );
            errors = errors + 1;
        end

        gpu_wr = 0;

        @(posedge mem_clk);
        #1;


        // =========================================================
        // TEST 2: SECOND GPU WRITE
        // =========================================================
        gpu_addr = 17'd65535;
        gpu_data = 8'h5A;

        gpu_wr = 1;

        @(posedge mem_clk);

        #1;


        if (gpu_busy !== 1'b1) begin
            $display("FAIL 2: gpu_busy should be 1");
            errors = errors + 1;
        end


        if (dut.sdram_addr !== 23'd65535) begin

            $display(
                "FAIL 2: sdram_addr = %0d, expected 65535",
                dut.sdram_addr

            );
            errors = errors + 1;
        end

        if (dut.sdram_din !== 8'h5A) begin
            $display(

                "FAIL 2: sdram_din = %h, expected 5A",
                dut.sdram_din
            );
            errors = errors + 1;
        end


        gpu_wr = 0;

        @(posedge mem_clk);
        #1;


        // =========================================================
        // TEST 3: VIDEO READ REQUEST
        // =========================================================

        video_addr = 17'd2048;
        video_req = 1;

        @(posedge mem_clk);
        #1;

        if (dut.sdram_rd !== 1'b1) begin
            $display("FAIL 3: sdram_rd should be 1");

            errors = errors + 1;
        end

        if (dut.sdram_addr !== 23'd2048) begin
            $display(
                "FAIL 3: sdram_addr = %0d, expected 2048",
                dut.sdram_addr
            );
            errors = errors + 1;
        end

        video_req = 0;


        // =========================================================
        // TEST 4: VIDEO DATA RETURN
        // =========================================================

        force dut.sdram_data_ready = 1'b1;
        force dut.sdram_dout = 8'h3C;

        @(posedge mem_clk);
        #1;

        if (video_valid !== 1'b1) begin
            $display("FAIL 4: video_valid should be 1");
            errors = errors + 1;
        end

        if (video_data !== 8'h3C) begin
            $display(
                "FAIL 4: video_data = %h, expected 3C",
                video_data
            );
            errors = errors + 1;
        end

        release dut.sdram_data_ready;
        release dut.sdram_dout;

        @(posedge mem_clk);
        #1;

        if (video_valid !== 1'b0) begin
            $display("FAIL 4: video_valid should return to 0");
            errors = errors + 1;
        end


        // =========================================================
        // TEST 5: GPU WRITE DISABLED
        // =========================================================

        gpu_wr = 0;

        @(posedge mem_clk);
        #1;

        if (gpu_busy !== 1'b0) begin
            $display("FAIL 5: gpu_busy should be 0");
            errors = errors + 1;
        end


        // =========================================================
        // TEST 6: VIDEO READ DISABLED
        // =========================================================

        video_req = 0;

        @(posedge mem_clk);
        #1;

        if (video_valid !== 1'b0) begin
            $display("FAIL 6: video_valid should be 0");
            errors = errors + 1;
        end


        // =========================================================
        // FINAL RESULT
        // =========================================================

        $display("");
        $display("========================================");
        $display("       GPU SDRAM VERIFICATION");
        $display("========================================");

        if (errors == 0) begin
            $display("RESULT: PASS");
            $display("All GPU SDRAM wrapper checks passed.");
        end
        else begin
            $display("RESULT: FAIL");
            $display("Total errors: %0d", errors);
        end

        $display("========================================");

        $finish;

    end

endmodule
