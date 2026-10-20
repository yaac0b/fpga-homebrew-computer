// ============================================================
// gpu_top.v
//
// Tang Nano 20K GPU
//
// VIDEO:
//     720 x 480
//
// FRAMEBUFFER:
//     160 x 120
//     RGB332
//     19,200 pixels
//
// SCALE:
//     3x
//
// GPU REGISTER MAP:
//
//     0x6000 = CONTROL
//              bit 0 = GPU enable
//
//     0x6001 = STATUS
//              bit 0 = GPU busy
//
//     0x6002 = COMMAND
//
//     0x6003 = X
//
//     0x6004 = Y
//
//     0x6005 = X2
//
//     0x6006 = Y2
//
//     0x6007 = COLOR
//
//     0x6008 = SIZE
//
//     0x6009 = PARAM0
//
//     0x600A = PARAM1
//
// COMMANDS:
//
//     1 = DRAW_PIXEL
//     2 = CLEAR
//     3 = FILL_RECT
//     4 = DRAW_RECT
//     5 = CHECKERBOARD
//     6 = RAINBOW
//     7 = ANIMATED_RAINBOW
//
// ============================================================

module gpu_top (

    // ========================================================
    // CLOCK
    // ========================================================

    input wire clk27,

    // ========================================================
    // RESET
    //
    // IMPORTANT:
    // Reset is supplied by top.v.
    // ========================================================

    input wire rst,

    // ========================================================
    // CPU -> GPU
    // ========================================================

    input wire        gpu_load,
    input wire [15:0] gpu_address,
    input wire [15:0] gpu_data,

    // ========================================================
    // GPU -> CPU
    // ========================================================

    output reg [15:0] gpu_out,

    // ========================================================
    // GPU STATUS
    // ========================================================

    output wire gpu_busy,

    // ========================================================
    // SDRAM CLOCK
    // ========================================================

    output wire sdram_clk,

    // ========================================================
    // HDMI CLOCK
    // ========================================================

    output wire tmds_clk_p,
    output wire tmds_clk_n,

    // ========================================================
    // HDMI DATA
    // ========================================================

    output wire tmds_d0_p,
    output wire tmds_d0_n,

    output wire tmds_d1_p,
    output wire tmds_d1_n,

    output wire tmds_d2_p,
    output wire tmds_d2_n

);


// ============================================================
// CLOCK GENERATION
// ============================================================
//
// clk27
//   |
//   v
// Gowin PLL
//   |
//   +---- serial_clk = 135 MHz
//   |
//   +---- pll_phase_clk
//
// serial_clk / 5 = pixel_clk = 27 MHz
//
// ============================================================

wire serial_clk;
wire pll_phase_clk;
wire pixel_clk;


// ============================================================
// GOWIN PLL
// ============================================================

Gowin_rPLL u_pll (

    .clkin   (clk27),
    .clkout  (serial_clk),
    .clkoutp (pll_phase_clk)

);


// ============================================================
// PIXEL CLOCK
// ============================================================

CLKDIV #(
    .DIV_MODE("5"),
    .GSREN("false")
) u_pixel_clkdiv (

    .HCLKIN(serial_clk),
    .RESETN(~rst),
    .CALIB(1'b1),
    .CLKOUT(pixel_clk)

);


// ============================================================
// SDRAM CLOCK
// ============================================================

CLKDIV #(
    .DIV_MODE("5"),
    .GSREN("false")
) u_sdram_clkdiv (

    .HCLKIN(pll_phase_clk),
    .RESETN(~rst),
    .CALIB(1'b1),
    .CLKOUT(sdram_clk)

);


// ============================================================
// VIDEO TIMING
// ============================================================
//
// 720 x 480
//
// H:
//     ACTIVE = 720
//     FRONT  = 16
//     SYNC   = 62
//     BACK   = 60
//     TOTAL  = 858
//
// V:
//     ACTIVE = 480
//     FRONT  = 9
//     SYNC   = 6
//     BACK   = 30
//     TOTAL  = 525
//
// ============================================================

localparam [10:0] H_ACTIVE = 11'd720;
localparam [10:0] H_FRONT  = 11'd16;
localparam [10:0] H_SYNC   = 11'd62;
localparam [10:0] H_BACK   = 11'd60;
localparam [10:0] H_TOTAL  = 11'd858;

localparam [9:0] V_ACTIVE = 10'd480;
localparam [9:0] V_FRONT  = 10'd9;
localparam [9:0] V_SYNC   = 10'd6;
localparam [9:0] V_BACK   = 10'd30;
localparam [9:0] V_TOTAL  = 10'd525;


// ============================================================
// VIDEO COUNTERS
// ============================================================

reg [10:0] h_count;
reg [9:0]  v_count;


always @(posedge pixel_clk or posedge rst) begin

    if (rst) begin

        h_count <= 11'd0;
        v_count <= 10'd0;

    end

    else begin

        if (h_count == H_TOTAL - 11'd1) begin

            h_count <= 11'd0;

            if (v_count == V_TOTAL - 10'd1)
                v_count <= 10'd0;

            else
                v_count <= v_count + 10'd1;

        end

        else begin

            h_count <= h_count + 11'd1;

        end

    end

end


// ============================================================
// VIDEO ACTIVE
// ============================================================

wire video_active;

assign video_active =
    (h_count < H_ACTIVE) &&
    (v_count < V_ACTIVE);


// ============================================================
// HSYNC
// ============================================================

wire hsync;

assign hsync =
    (h_count >= H_ACTIVE + H_FRONT) &&
    (h_count <  H_ACTIVE + H_FRONT + H_SYNC);


// ============================================================
// VSYNC
// ============================================================

wire vsync;

assign vsync =
    (v_count >= V_ACTIVE + V_FRONT) &&
    (v_count <  V_ACTIVE + V_FRONT + V_SYNC);


// ============================================================
// GPU REGISTER SELECT
// ============================================================
//
// 6000 ... 600A
//
// ============================================================

wire gpu_reg_select;

assign gpu_reg_select =
    (gpu_address >= 16'h6000) &&
    (gpu_address <= 16'h600A);


// ============================================================
// GPU REGISTERS
// ============================================================

wire        gpu_enable;

wire [7:0]  gpu_command;
wire        gpu_command_valid;

wire [7:0]  gx;
wire [7:0]  gy;

wire [7:0]  gx2;
wire [7:0]  gy2;

wire [7:0]  gpu_color;

wire [15:0] gpu_size;

wire [15:0] gpu_param0;
wire [15:0] gpu_param1;

// Renderer busy is fed back to the register block so commands
// are not lost while the renderer is drawing.
wire renderer_busy;


// ============================================================
// GPU REGISTER MODULE
// ============================================================

gpu_regs u_gpu_regs (

    .clk(clk27),
    .rst(rst),

    .cpu_we(
        gpu_load &&
        gpu_reg_select
    ),

    .cpu_addr(gpu_address),
    .cpu_wdata(gpu_data),

    .renderer_busy(renderer_busy),

    .gpu_enable(gpu_enable),

    .command(gpu_command),
    .command_valid(gpu_command_valid),

    .x(gx),
    .y(gy),

    .x2(gx2),
    .y2(gy2),

    .color(gpu_color),

    .size(gpu_size),

    .param0(gpu_param0),
    .param1(gpu_param1)

);


// ============================================================
// GPU RENDERER
// ============================================================

wire        renderer_we;
wire [14:0] renderer_addr;
wire [7:0]  renderer_data;


// ============================================================
// GPU RENDERER INSTANCE
// ============================================================

gpu_renderer u_gpu_renderer (

    .clk(clk27),
    .rst(rst),

    .gpu_enable(gpu_enable),

    .command(gpu_command),
    .command_valid(gpu_command_valid),

    .draw_x(gx),
    .draw_y(gy),

    .draw_x2(gx2),
    .draw_y2(gy2),

    .draw_color(gpu_color),

    .draw_size(gpu_size),

    .param0(gpu_param0),
    .param1(gpu_param1),

    .fb_we(renderer_we),
    .fb_addr(renderer_addr),
    .fb_wdata(renderer_data),

    .busy(renderer_busy)

);


// ============================================================
// GPU BUSY
// ============================================================

assign gpu_busy = renderer_busy;


// ============================================================
// FRAMEBUFFER DISPLAY AREA
// ============================================================
//
// Framebuffer:
//     160 x 120
//
// Scale:
//     3x
//
// Display:
//     480 x 360
//
// Centered:
//     720 x 480
//
// Position:
//     X = 120
//     Y = 60
//
// ============================================================

wire framebuffer_display;

assign framebuffer_display =

    video_active &&

    (h_count >= 11'd120) &&
    (h_count <  11'd600) &&

    (v_count >= 10'd60) &&
    (v_count <  10'd420);


// ============================================================
// DISPLAY RELATIVE COORDINATES
// ============================================================

wire [10:0] relative_x;
wire [9:0]  relative_y;

assign relative_x =
    h_count - 11'd120;

assign relative_y =
    v_count - 10'd60;


// ============================================================
// FRAMEBUFFER COORDINATES
// ============================================================
//
// 3 HDMI pixels = 1 framebuffer pixel.
//
// 480 / 3 = 160
// 360 / 3 = 120
//
// ============================================================

wire [10:0] fb_x_wide;
wire [9:0]  fb_y_wide;

assign fb_x_wide =
    relative_x / 11'd3;

assign fb_y_wide =
    relative_y / 10'd3;


// ============================================================
// FINAL FRAMEBUFFER X/Y
// ============================================================

wire [7:0] fb_x;
wire [6:0] fb_y;

assign fb_x =
    fb_x_wide[7:0];

assign fb_y =
    fb_y_wide[6:0];


// ============================================================
// FRAMEBUFFER ADDRESS
// ============================================================
//
// address = Y * 160 + X
//
// Maximum:
//     119 * 160 + 159
//     = 19199
//
// 15 bits are sufficient.
//
// IMPORTANT:
// video_addr is declared explicitly BEFORE it is used.
//
// ============================================================

wire [15:0] video_addr_wide;
wire [14:0] video_addr;


// ============================================================
// ADDRESS CALCULATION
// ============================================================

assign video_addr_wide =

    (16'd160 * {9'd0, fb_y}) +

    {8'd0, fb_x};


// ============================================================
// 16-bit -> 15-bit
// ============================================================

assign video_addr =
    video_addr_wide[14:0];


// ============================================================
// FRAMEBUFFER PIXEL
// ============================================================

wire [7:0] fb_pixel;


// ============================================================
// FRAMEBUFFER BRAM
// ============================================================
//
// This assumes framebuffer_bram has:
//
//     clk_w
//     clk_r
//     cpu_we
//     cpu_addr
//     cpu_wdata
//     video_addr
//     video_pixel
//
// ============================================================

framebuffer_bram u_fb (

    .clk_w(clk27),

    .clk_r(pixel_clk),

    .cpu_we(renderer_we),

    .cpu_addr(renderer_addr),

    .cpu_wdata(renderer_data),

    .video_addr(video_addr),

    .video_pixel(fb_pixel)

);


// ============================================================
// GPU CPU READBACK
// ============================================================
//
// 6000 = CONTROL
// 6001 = STATUS
// 6002 = COMMAND
// 6003 = X
// 6004 = Y
// 6005 = X2
// 6006 = Y2
// 6007 = COLOR
// 6008 = SIZE
// 6009 = PARAM0
// 600A = PARAM1
//
// ============================================================

always @(*) begin

    gpu_out = 16'h0000;

    case (gpu_address)


        // ----------------------------------------------------
        // CONTROL
        // ----------------------------------------------------

        16'h6000: begin

            gpu_out = {
                15'h0000,
                gpu_enable
            };

        end


        // ----------------------------------------------------
        // STATUS
        // ----------------------------------------------------

        16'h6001: begin

            gpu_out = {
                15'h0000,
                renderer_busy
            };

        end


        // ----------------------------------------------------
        // COMMAND
        // ----------------------------------------------------

        16'h6002: begin

            gpu_out = {
                8'h00,
                gpu_command
            };

        end


        // ----------------------------------------------------
        // X
        // ----------------------------------------------------

        16'h6003: begin

            gpu_out = {
                8'h00,
                gx
            };

        end


        // ----------------------------------------------------
        // Y
        // ----------------------------------------------------

        16'h6004: begin

            gpu_out = {
                8'h00,
                gy
            };

        end


        // ----------------------------------------------------
        // X2
        // ----------------------------------------------------

        16'h6005: begin

            gpu_out = {
                8'h00,
                gx2
            };

        end


        // ----------------------------------------------------
        // Y2
        // ----------------------------------------------------

        16'h6006: begin

            gpu_out = {
                8'h00,
                gy2
            };

        end


        // ----------------------------------------------------
        // COLOR
        // ----------------------------------------------------

        16'h6007: begin

            gpu_out = {
                8'h00,
                gpu_color
            };

        end


        // ----------------------------------------------------
        // SIZE
        // ----------------------------------------------------

        16'h6008: begin

            gpu_out = gpu_size;

        end


        // ----------------------------------------------------
        // PARAM0
        // ----------------------------------------------------

        16'h6009: begin

            gpu_out = gpu_param0;

        end


        // ----------------------------------------------------
        // PARAM1
        // ----------------------------------------------------

        16'h600A: begin

            gpu_out = gpu_param1;

        end


        // ----------------------------------------------------
        // DEFAULT
        // ----------------------------------------------------

        default: begin

            gpu_out = 16'h0000;

        end

    endcase

end


// ============================================================
// RGB332 -> RGB888
// ============================================================

reg [7:0] red;
reg [7:0] green;
reg [7:0] blue;


always @(*) begin

    red   = 8'h00;
    green = 8'h00;
    blue  = 8'h00;


    if (framebuffer_display) begin


        // ----------------------------------------------------
        // RED
        // ----------------------------------------------------
        //
        // RGB332:
        // R = bits 7:5
        //
        // ----------------------------------------------------

        red = {

            fb_pixel[7:5],
            fb_pixel[7:5],
            fb_pixel[7:6]

        };


        // ----------------------------------------------------
        // GREEN
        // ----------------------------------------------------
        //
        // G = bits 4:2
        //
        // ----------------------------------------------------

        green = {

            fb_pixel[4:2],
            fb_pixel[4:2],
            fb_pixel[4:3]

        };


        // ----------------------------------------------------
        // BLUE
        // ----------------------------------------------------
        //
        // B = bits 1:0
        //
        // ----------------------------------------------------

        blue = {

            fb_pixel[1:0],
            fb_pixel[1:0],
            fb_pixel[1:0],
            fb_pixel[1:0]

        };

    end

end


// ============================================================
// TMDS ENCODERS
// ============================================================

wire [9:0] tmds_r;
wire [9:0] tmds_g;
wire [9:0] tmds_b;


// ============================================================
// RED TMDS
// ============================================================

tmds_encoder enc_r (

    .clk(pixel_clk),
    .rst(rst),

    .data_in(red),

    .c0(1'b0),
    .c1(1'b0),

    .de(video_active),

    .data_out(tmds_r)

);


// ============================================================
// GREEN TMDS
// ============================================================

tmds_encoder enc_g (

    .clk(pixel_clk),
    .rst(rst),

    .data_in(green),

    .c0(1'b0),
    .c1(1'b0),

    .de(video_active),

    .data_out(tmds_g)

);


// ============================================================
// BLUE TMDS
// ============================================================
//
// Blue carries HSYNC/VSYNC during blanking.
//
// ============================================================

tmds_encoder enc_b (

    .clk(pixel_clk),
    .rst(rst),

    .data_in(blue),

    .c0(hsync),
    .c1(vsync),

    .de(video_active),

    .data_out(tmds_b)

);


// ============================================================
// TMDS SERIALIZER
// ============================================================

wire serial_r;
wire serial_g;
wire serial_b;


tmds_serializer serializer (

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


// ============================================================
// HDMI OUTPUT
// ============================================================
//
// D0 = BLUE
// D1 = GREEN
// D2 = RED
//
// ============================================================

TLVDS_OBUF tmds_d0_buf (

    .I(serial_b),

    .O(tmds_d0_p),
    .OB(tmds_d0_n)

);


TLVDS_OBUF tmds_d1_buf (

    .I(serial_g),

    .O(tmds_d1_p),
    .OB(tmds_d1_n)

);


TLVDS_OBUF tmds_d2_buf (

    .I(serial_r),

    .O(tmds_d2_p),
    .OB(tmds_d2_n)

);


// ============================================================
// HDMI PIXEL CLOCK OUTPUT
// ============================================================

TLVDS_OBUF tmds_clk_buf (

    .I(pixel_clk),

    .O(tmds_clk_p),
    .OB(tmds_clk_n)

);


// ============================================================
// END GPU TOP
// ============================================================

endmodule