module framebuffer_bram (
    input  wire        clk,

    // CPU write port
    input  wire        cpu_we,
    input  wire [14:0] cpu_addr,
    input  wire [7:0]  cpu_wdata,

    // Video read port
    input  wire [14:0] video_addr,
    output reg  [7:0]  video_pixel
);

    // 160 x 120 RGB332 = 19,200 bytes
    reg [7:0] mem [0:19199];

    always @(posedge clk) begin
        if (cpu_we)
            mem[cpu_addr] <= cpu_wdata;

        video_pixel <= mem[video_addr];
    end
endmodule
