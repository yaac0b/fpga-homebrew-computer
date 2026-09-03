module gpu_regs (
    input  wire        clk,
    input  wire        rst,

    input  wire [15:0] cpu_addr,
    input  wire [15:0] cpu_din,
    input  wire        cpu_we,

    output reg  [8:0]  gpu_x,
    output reg  [7:0]  gpu_y,
    output reg  [7:0]  gpu_color,
    output reg         gpu_draw
);

    localparam ADDR_X     = 16'h6001;
    localparam ADDR_Y     = 16'h6002;
    localparam ADDR_COLOR = 16'h6003;
    localparam ADDR_CMD   = 16'h6004;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gpu_x     <= 9'd0;
            gpu_y     <= 8'd0;
            gpu_color <= 8'd0;
            gpu_draw  <= 1'b0;
        end
        else begin
            gpu_draw <= 1'b0;

            if (cpu_we) begin
                case (cpu_addr)

                    ADDR_X:
                        gpu_x <= cpu_din[8:0];

                    ADDR_Y:
                        gpu_y <= cpu_din[7:0];

                    ADDR_COLOR:
                        gpu_color <= cpu_din[7:0];

                    ADDR_CMD:
                        if (cpu_din[0])
                            gpu_draw <= 1'b1;

                    default:
                        begin
                        end

                endcase
            end
        end
    end

endmodule