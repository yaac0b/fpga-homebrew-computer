module video_scan_color (
    input  wire        clk,
    input  wire        rst,

    input  wire [10:0] h_count,
    input  wire [9:0]  v_count,

    input  wire        hsync_in,
    input  wire        vsync_in,
    input  wire        video_active_in,

    input  wire [7:0]  fb_data,

    output reg  [16:0] fb_addr,

    output reg         hsync_out,
    output reg         vsync_out,
    output reg         video_active_out,

    output reg [7:0]   red,
    output reg [7:0]   green,
    output reg [7:0]   blue
);

    // Position of 512 x 256 image inside 720 x 480
    //
    // X = 104 ... 615
    // Y = 112 ... 367

    wire inside_x;
    wire inside_y;
    wire inside_screen;

    assign inside_x =
        (h_count >= 11'd104) &&
        (h_count <  11'd616);

    assign inside_y =
        (v_count >= 10'd112) &&
        (v_count <  10'd368);

    assign inside_screen = inside_x && inside_y;

    wire [10:0] pixel_x_calc;
    wire [9:0]  pixel_y_calc;

    wire [8:0] pixel_x;
    wire [7:0] pixel_y;

    assign pixel_x_calc = h_count - 11'd104;
    assign pixel_y_calc = v_count - 10'd112;

    assign pixel_x = pixel_x_calc[8:0];
    assign pixel_y = pixel_y_calc[7:0];
    wire [16:0] calculated_addr;

    assign calculated_addr =
        {pixel_y, 9'b0} +
        {8'b0, pixel_x};

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            fb_addr          <= 17'd0;

            hsync_out        <= 1'b1;
            vsync_out        <= 1'b1;
            video_active_out <= 1'b0;

            red              <= 8'h00;
            green            <= 8'h00;
            blue             <= 8'h00;

        end
        else begin

            hsync_out <= hsync_in;
            vsync_out <= vsync_in;

            if (inside_screen)
                fb_addr <= calculated_addr;
            else
                fb_addr <= 17'd0;

            if (video_active_in && inside_screen) begin

                video_active_out <= 1'b1;

                // RGB332
                //
                // R = bits 7:5
                // G = bits 4:2
                // B = bits 1:0

                red <= {
                    fb_data[7:5],
                    fb_data[7:5],
                    2'b00
                };

                green <= {
                    fb_data[4:2],
                    fb_data[4:2],
                    2'b00
                };

                blue <= {
                    fb_data[1:0],
                    fb_data[1:0],
                    fb_data[1:0],
                    fb_data[1:0]
                };

            end
            else begin

                video_active_out <= 1'b0;

                red   <= 8'h00;
                green <= 8'h00;
                blue  <= 8'h00;

            end

        end

    end

endmodule