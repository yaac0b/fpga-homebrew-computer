module gpu_pixel (
    input  wire        clk,
    input  wire        rst,

    input  wire [8:0]  gpu_x,
    input  wire [7:0]  gpu_y,
    input  wire [7:0]  gpu_color,
    input  wire        gpu_draw,

    output reg  [16:0] fb_addr,
    output reg  [7:0]  fb_data,
    output reg         fb_we
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fb_addr <= 17'd0;
            fb_data <= 8'h00;
            fb_we   <= 1'b0;
        end
        else begin

            fb_we <= 1'b0;

            if (gpu_draw) begin

                // y * 512 + x
                fb_addr <= {gpu_y, 9'b0} + {8'b0, gpu_x};

                fb_data <= gpu_color;

                fb_we <= 1'b1;

            end
        end
    end

endmodule