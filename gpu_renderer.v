module gpu_renderer (
    input  wire        clk,
    input  wire        rst,

    input  wire        gpu_enable,
    input  wire        draw_pixel,
    input  wire        clear_screen,
    input  wire [7:0]  draw_x,
    input  wire [7:0]  draw_y,
    input  wire [7:0]  draw_color,

    output reg         fb_we,
    output reg  [14:0] fb_addr,
    output reg  [7:0]  fb_wdata,
    output reg         busy
);

    // 160 x 120 framebuffer
    reg [14:0] clear_addr;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fb_we     <= 1'b0;
            fb_addr   <= 15'd0;
            fb_wdata  <= 8'h00;
            clear_addr<= 15'd0;
            busy      <= 1'b0;
        end else begin
            fb_we <= 1'b0;

            if (clear_screen && gpu_enable) begin
                busy      <= 1'b1;
                clear_addr<= 15'd0;
                fb_addr   <= 15'd0;
                fb_wdata  <= 8'h00;
                fb_we     <= 1'b1;
            end else if (busy) begin
                if (clear_addr == 15'd19199) begin
                    busy <= 1'b0;
                end else begin
                    clear_addr <= clear_addr + 15'd1;
                    fb_addr    <= clear_addr + 15'd1;
                    fb_wdata   <= 8'h00;
                    fb_we      <= 1'b1;
                end
            end else if (draw_pixel && gpu_enable &&
                         (draw_x < 8'd160) &&
                         (draw_y < 8'd120)) begin
                // address = y*160+x
                fb_addr  <= ({7'd0, draw_y} * 15'd160) + {7'd0, draw_x};
                fb_wdata <= draw_color;
                fb_we    <= 1'b1;
            end
        end
    end
endmodule
