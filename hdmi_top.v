module hdmi_top (

    input wire clk27,
    input wire rst_n,

    // =========================================================
    // Hack CPU interface
    // =========================================================

    input wire        cpu_clk,
    input wire [15:0] cpu_addr,
    input wire [15:0] cpu_din,
    input wire        cpu_we,

    // =========================================================
    // HDMI
    // =========================================================

    output wire tmds_clk_p,
    output wire tmds_clk_n,

    output wire tmds_d0_p,
    output wire tmds_d0_n,

    output wire tmds_d1_p,
    output wire tmds_d1_n,

    output wire tmds_d2_p,
    output wire tmds_d2_n,

    // =========================================================
    // Tang Nano 20K SDRAM
    // =========================================================

    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,

    inout wire [31:0]  IO_sdram_dq,

    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm
);

    // =========================================================
    // Reset
    // =========================================================

    wire rst;

    assign rst = ~rst_n;


    // =========================================================
    // HDMI PLL
    //
    // 27 MHz input
    //
    // CLKOUT  = 270 MHz
    // CLKOUTD = 27 MHz
    //
    // =========================================================

    wire pixel_clk;
    wire serial_clk;

    Gowin_rPLL u_hdmi_pll (

        .clkout  (serial_clk),
        .clkoutp (),
        .clkoutd (pixel_clk),

        .clkin   (clk27),

        .psda    (4'b0000),
        .dutyda  (4'b0000),
        .fdly     (4'b0000)
    );


    // =========================================================
    // GPU registers
    // =========================================================

    wire [8:0] gpu_x;
    wire [7:0] gpu_y;
    wire [7:0] gpu_color;
    wire       gpu_draw;

    gpu_regs u_gpu_regs (

        .clk       (cpu_clk),
        .rst       (rst),

        .cpu_addr  (cpu_addr),
        .cpu_din   (cpu_din),
        .cpu_we    (cpu_we),

        .gpu_x     (gpu_x),
        .gpu_y     (gpu_y),
        .gpu_color (gpu_color),
        .gpu_draw  (gpu_draw)
    );


    // =========================================================
    // GPU pixel write
    // =========================================================

    wire [16:0] fb_write_addr;
    wire [7:0]  fb_write_data;
    wire        fb_write;

    gpu_pixel u_gpu_pixel (

        .clk       (cpu_clk),
        .rst       (rst),

        .gpu_x     (gpu_x),
        .gpu_y     (gpu_y),
        .gpu_color (gpu_color),
        .gpu_draw  (gpu_draw),

        .fb_addr   (fb_write_addr),
        .fb_data   (fb_write_data),
        .fb_we     (fb_write)
    );


    // =========================================================
    // Video timing
    // =========================================================

    wire hsync;
    wire vsync;
    wire video_active;

    wire [10:0] h_count;
    wire [9:0]  v_count;

    video_timing u_video_timing (

        .clk          (pixel_clk),
        .rst          (rst),

        .hsync        (hsync),
        .vsync        (vsync),
        .video_active (video_active),

        .h_count      (h_count),
        .v_count      (v_count)
    );


    // =========================================================
    // Framebuffer read address
    // =========================================================

    wire [16:0] fb_read_addr;

    wire [7:0] fb_read_data;

    wire fb_video_req;

    /*
     * Request SDRAM when inside the framebuffer.
     */
    assign fb_video_req =
        video_active &&
        (h_count >= 11'd104) &&
        (h_count <  11'd616) &&
        (v_count >= 10'd112) &&
        (v_count <  10'd368);


    // =========================================================
    // Video scanner
    // =========================================================

    wire       video_hsync;
    wire       video_vsync;
    wire       video_active_out;

    wire [7:0] red;
    wire [7:0] green;
    wire [7:0] blue;

    video_scan_color u_video_scan (

        .clk              (pixel_clk),
        .rst              (rst),

        .h_count          (h_count),
        .v_count          (v_count),

        .hsync_in         (hsync),
        .vsync_in         (vsync),

        .video_active_in  (video_active),

        .fb_data          (fb_read_data),

        .fb_addr          (fb_read_addr),

        .hsync_out        (video_hsync),
        .vsync_out        (video_vsync),

        .video_active_out (video_active_out),

        .red              (red),
        .green            (green),
        .blue             (blue)
    );


    // =========================================================
    // SDRAM
    //
    // TEMPORARY clock connection
    //
    // IMPORTANT:
    // This is NOT the final SDRAM clock architecture.
    // We will generate a dedicated ~64.8 MHz SDRAM PLL next.
    // =========================================================

    wire mem_clk;
    wire mem_clk_180;

    Gowin_sdram_pll u_sdram_pll (
        .clkout  (mem_clk),
        .clkoutp (mem_clk_180),
        .clkin   (clk27)
    );


    // =========================================================
    // SDRAM control
    // =========================================================

    wire sdram_gpu_busy;

    wire sdram_video_valid;

    gpu_sdram u_gpu_sdram (

        .mem_clk       (mem_clk),
        .mem_clk_sdram (mem_clk_180),

        .resetn        (rst_n),

        // GPU write
        .gpu_wr        (fb_write),
        .gpu_addr      (fb_write_addr),
        .gpu_data      (fb_write_data),
        .gpu_busy      (sdram_gpu_busy),

        // Video read
        .video_req     (fb_video_req),
        .video_addr    (fb_read_addr),

        .video_valid   (sdram_video_valid),
        .video_data    (fb_read_data),

        // SDRAM pins
        .SDRAM_DQ      (IO_sdram_dq),

        .SDRAM_A       (O_sdram_addr),
        .SDRAM_BA      (O_sdram_ba),

        .SDRAM_nCS     (O_sdram_cs_n),
        .SDRAM_nWE     (O_sdram_wen_n),
        .SDRAM_nRAS    (O_sdram_ras_n),
        .SDRAM_nCAS    (O_sdram_cas_n),

        .SDRAM_CLK     (O_sdram_clk),
        .SDRAM_CKE     (O_sdram_cke),

        .SDRAM_DQM     (O_sdram_dqm)
    );


    // =========================================================
    // TMDS encoders
    // =========================================================

    wire [9:0] tmds_r;
    wire [9:0] tmds_g;
    wire [9:0] tmds_b;


    tmds_encoder u_tmds_r (

        .clk          (pixel_clk),
        .rst          (rst),

        .data_in      (red),

        .c0           (1'b0),
        .c1           (1'b0),

        .de           (video_active_out),

        .data_out     (tmds_r)
    );


    tmds_encoder u_tmds_g (

        .clk          (pixel_clk),
        .rst          (rst),

        .data_in      (green),

        .c0           (1'b0),
        .c1           (1'b0),

        .de           (video_active_out),

        .data_out     (tmds_g)
    );


    tmds_encoder u_tmds_b (

        .clk          (pixel_clk),
        .rst          (rst),

        .data_in      (blue),

        .c0           (video_hsync),
        .c1           (video_vsync),

        .de           (video_active_out),

        .data_out     (tmds_b)
    );


    // =========================================================
    // TMDS serializers
    // =========================================================

    wire serial_r;
    wire serial_g;
    wire serial_b;

    tmds_serializer u_serializer (

        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),

        .rst        (rst),

        .tmds_r     (tmds_r),
        .tmds_g     (tmds_g),
        .tmds_b     (tmds_b),

        .serial_r   (serial_r),
        .serial_g   (serial_g),
        .serial_b   (serial_b)
    );


    // =========================================================
    // HDMI differential outputs
    // =========================================================

    ELVDS_OBUF u_hdmi_r (

        .I  (serial_r),

        .O  (tmds_d2_p),
        .OB (tmds_d2_n)
    );


    ELVDS_OBUF u_hdmi_g (

        .I  (serial_g),

        .O  (tmds_d1_p),
        .OB (tmds_d1_n)
    );


    ELVDS_OBUF u_hdmi_b (

        .I  (serial_b),

        .O  (tmds_d0_p),
        .OB (tmds_d0_n)
    );


    ELVDS_OBUF u_hdmi_clk (

        .I  (pixel_clk),

        .O  (tmds_clk_p),
        .OB (tmds_clk_n)
    );

endmodule