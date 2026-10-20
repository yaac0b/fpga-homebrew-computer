`timescale 1ns/1ps
module video_timing (
    input  wire       clk,
    input  wire       rst,

    output reg [10:0] h_count,
    output reg [9:0]  v_count,

    output wire       hsync,
    output wire       vsync,
    output wire       video_active
);
    localparam [10:0] H_ACTIVE = 11'd720;
    localparam [10:0] H_FRONT  = 11'd16;
    localparam [10:0] H_SYNC   = 11'd62;
    localparam [10:0] H_BACK   = 11'd60;
    localparam [10:0] H_TOTAL  = 11'd858;

    localparam [9:0]  V_ACTIVE = 10'd480;
    localparam [9:0]  V_FRONT  = 10'd9;
    localparam [9:0]  V_SYNC   = 10'd6;
    localparam [9:0]  V_BACK   = 10'd30;
    localparam [9:0]  V_TOTAL  = 10'd525;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            h_count <= 11'd0;
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 11'd1) begin
            h_count <= 11'd0;
            if (v_count == V_TOTAL - 10'd1)
                v_count <= 10'd0;
            else
                v_count <= v_count + 10'd1;
        end else begin
            h_count <= h_count + 11'd1;
        end
    end

    assign video_active =
        (h_count < H_ACTIVE) &&
        (v_count < V_ACTIVE);

    assign hsync =
        (h_count >= H_ACTIVE + H_FRONT) &&
        (h_count <  H_ACTIVE + H_FRONT + H_SYNC);

    assign vsync =
        (v_count >= V_ACTIVE + V_FRONT) &&
        (v_count <  V_ACTIVE + V_FRONT + V_SYNC);
endmodule
