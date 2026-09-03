module video_timing (
    input  wire        clk,
    input  wire        rst,

    output reg         hsync,
    output reg         vsync,
    output reg         video_active,

    output reg [10:0]  h_count,
    output reg [9:0]   v_count
);

    // 720 x 480 timing
    localparam H_ACTIVE = 11'd720;
    localparam H_FRONT  = 11'd16;
    localparam H_SYNC   = 11'd62;
    localparam H_BACK   = 11'd60;
    localparam H_TOTAL  = 11'd858;

    localparam V_ACTIVE = 10'd480;
    localparam V_FRONT  = 10'd9;
    localparam V_SYNC   = 10'd6;
    localparam V_BACK   = 10'd30;
    localparam V_TOTAL  = 10'd525;

    always @(posedge clk or posedge rst) begin

        if (rst) begin
            h_count <= 11'd0;
            v_count <= 10'd0;
        end
        else begin

            if (h_count == H_TOTAL - 1'b1) begin

                h_count <= 11'd0;

                if (v_count == V_TOTAL - 1'b1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 1'b1;

            end
            else begin
                h_count <= h_count + 1'b1;
            end

        end

    end

    always @(posedge clk or posedge rst) begin

        if (rst) begin
            hsync        <= 1'b1;
            vsync        <= 1'b1;
            video_active <= 1'b0;
        end
        else begin

            hsync <= !(
                (h_count >= H_ACTIVE + H_FRONT) &&
                (h_count <  H_ACTIVE + H_FRONT + H_SYNC)
            );

            vsync <= !(
                (v_count >= V_ACTIVE + V_FRONT) &&
                (v_count <  V_ACTIVE + V_FRONT + V_SYNC)
            );

            video_active <=
                (h_count < H_ACTIVE) &&
                (v_count < V_ACTIVE);

        end

    end

endmodule