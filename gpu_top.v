module gpu_top (
    input  wire        clk27,

    // CPU <-> GPU memory-mapped interface
    input  wire        cpu_we,
    input  wire        cpu_re,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output reg  [31:0] cpu_rdata,

    // HDMI
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire        tmds_d0_p,
    output wire        tmds_d0_n,
    output wire        tmds_d1_p,
    output wire        tmds_d1_n,
    output wire        tmds_d2_p,
    output wire        tmds_d2_n
);

    wire rst = 1'b0;
    wire serial_clk;
    wire pixel_clk;

    Gowin_rPLL u_pll (
        .clkout(serial_clk),
        .clkin(clk27)
    );

    CLKDIV u_clkdiv (
        .HCLKIN(serial_clk),
        .RESETN(1'b1),
        .CALIB(1'b1),
        .CLKOUT(pixel_clk)
    );
    defparam u_clkdiv.DIV_MODE = "5";
    defparam u_clkdiv.GSREN = "false";

    wire hsync, vsync, de;
    wire [10:0] h_count;
    wire [9:0] v_count;

    video_timing u_timing (
        .clk(pixel_clk),
        .rst(rst),
        .hsync(hsync),
        .vsync(vsync),
        .video_active(de),
        .h_count(h_count),
        .v_count(v_count)
    );

    // Address map:
    // 0x8000_0000 - 0x8000_0FFF : GPU registers
    // 0x8000_1000 - 0x8000_5AFF : framebuffer bytes
    wire reg_sel = (cpu_addr >= 32'h8000_0000) &&
                   (cpu_addr <  32'h8000_1000);

    wire fb_sel  = (cpu_addr >= 32'h8000_1000) &&
                   (cpu_addr <  32'h8000_5B00);

    wire [11:0] reg_addr = cpu_addr[11:0];
    wire [14:0] fb_cpu_addr = cpu_addr[14:0] - 15'h1000;

    wire [7:0] color, gx, gy;
    wire gpu_enable, draw_pixel, clear_screen;

    gpu_regs u_regs (
        .clk(pixel_clk),
        .rst(rst),
        .cpu_we(cpu_we && reg_sel),
        .cpu_addr(reg_addr),
        .cpu_wdata(cpu_wdata),
        .color(color),
        .x(gx),
        .y(gy),
        .gpu_enable(gpu_enable),
        .draw_pixel(draw_pixel),
        .clear_screen(clear_screen)
    );

    wire renderer_we;
    wire [14:0] renderer_addr;
    wire [7:0] renderer_data;
    wire renderer_busy;

    gpu_renderer u_renderer (
        .clk(pixel_clk),
        .rst(rst),
        .gpu_enable(gpu_enable),
        .draw_pixel(draw_pixel),
        .clear_screen(clear_screen),
        .draw_x(gx),
        .draw_y(gy),
        .draw_color(color),
        .fb_we(renderer_we),
        .fb_addr(renderer_addr),
        .fb_wdata(renderer_data),
        .busy(renderer_busy)
    );

    // Scale 160x120 framebuffer by 3 -> 480x360, centered in 720x480.
    wire fb_display_area =
        de &&
        (h_count >= 11'd120) && (h_count < 11'd600) &&
        (v_count >= 10'd60)  && (v_count < 10'd420);

    wire [10:0] rel_x = h_count - 11'd120;
    wire [9:0]  rel_y = v_count - 10'd60;

    wire [10:0] fb_x_wide;
    wire [9:0]  fb_y_wide;

    wire [7:0] fb_x;
    wire [6:0] fb_y;

    assign fb_x_wide = rel_x / 11'd3;
    assign fb_y_wide = rel_y / 10'd3;

    assign fb_x = fb_x_wide[7:0];
    assign fb_y = fb_y_wide[6:0];

    wire [14:0] video_addr =
        ({8'd0, fb_y} * 15'd160) + {7'd0, fb_x};

    wire [7:0] fb_pixel;

    framebuffer_bram u_fb (
        .clk(pixel_clk),
        .cpu_we((cpu_we && fb_sel) || renderer_we),
        .cpu_addr(renderer_we ? renderer_addr : fb_cpu_addr),
        .cpu_wdata(renderer_we ? renderer_data : cpu_wdata[7:0]),
        .video_addr(video_addr),
        .video_pixel(fb_pixel)
    );

    // CPU readback
    always @(*) begin
        cpu_rdata = 32'h00000000;

        if (cpu_re && fb_sel)
            cpu_rdata = {24'h0, fb_pixel};
        else if (cpu_re && reg_sel) begin
            case (reg_addr)
                12'h000: cpu_rdata = {31'd0, gpu_enable};
                12'h004: cpu_rdata = {24'd0, gx};
                12'h008: cpu_rdata = {24'd0, gy};
                12'h00C: cpu_rdata = {24'd0, color};
                12'h014: cpu_rdata = {31'd0, renderer_busy};
                default: cpu_rdata = 32'h00000000;
            endcase
        end
    end

    // RGB332 -> RGB888
    reg [7:0] red, green, blue;
    always @(*) begin
        red = 8'h00;
        green = 8'h00;
        blue = 8'h00;

        if (fb_display_area) begin
            red = {fb_pixel[7:5], fb_pixel[7:5], fb_pixel[7:6]};
            green = {fb_pixel[4:2], fb_pixel[4:2], fb_pixel[4:3]};
            blue = {fb_pixel[1:0], fb_pixel[1:0], fb_pixel[1:0], fb_pixel[1:0]};
        end
    end

    wire [9:0] tmds_r, tmds_g, tmds_b;

    tmds_encoder u_r (
        .clk(pixel_clk), .rst(rst), .data_in(red),
        .c0(1'b0), .c1(1'b0), .de(de), .data_out(tmds_r)
    );

    tmds_encoder u_g (
        .clk(pixel_clk), .rst(rst), .data_in(green),
        .c0(1'b0), .c1(1'b0), .de(de), .data_out(tmds_g)
    );

    tmds_encoder u_b (
        .clk(pixel_clk), .rst(rst), .data_in(blue),
        .c0(hsync), .c1(vsync), .de(de), .data_out(tmds_b)
    );

    wire serial_r, serial_g, serial_b;

    tmds_serializer u_ser (
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

    ELVDS_OBUF u_r_out (.I(serial_r), .O(tmds_d2_p), .OB(tmds_d2_n));
    ELVDS_OBUF u_g_out (.I(serial_g), .O(tmds_d1_p), .OB(tmds_d1_n));
    ELVDS_OBUF u_b_out (.I(serial_b), .O(tmds_d0_p), .OB(tmds_d0_n));
    ELVDS_OBUF u_clk_out (.I(pixel_clk), .O(tmds_clk_p), .OB(tmds_clk_n));

endmodule
