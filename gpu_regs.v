module gpu_regs (
    input  wire        clk,
    input  wire        rst,
    input  wire        cpu_we,
    input  wire [11:0] cpu_addr,
    input  wire [31:0] cpu_wdata,

    output reg  [7:0]  color,
    output reg  [7:0]  x,
    output reg  [7:0]  y,
    output reg         gpu_enable,
    output reg         draw_pixel,
    output reg         clear_screen
);

    // Register map:
    // 0x000 CONTROL     bit0 = GPU enable
    // 0x004 X           low 8 bits
    // 0x008 Y           low 8 bits
    // 0x00C COLOR       RGB332 in low 8 bits
    // 0x010 COMMAND     1 = draw pixel, 2 = clear framebuffer

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            color        <= 8'h00;
            x            <= 8'd0;
            y            <= 8'd0;
            gpu_enable   <= 1'b0;
            draw_pixel   <= 1'b0;
            clear_screen <= 1'b0;
        end else begin
            draw_pixel   <= 1'b0;
            clear_screen <= 1'b0;

            if (cpu_we) begin
                case (cpu_addr)
                    12'h000: gpu_enable <= cpu_wdata[0];
                    12'h004: x <= cpu_wdata[7:0];
                    12'h008: y <= cpu_wdata[7:0];
                    12'h00C: color <= cpu_wdata[7:0];
                    12'h010: begin
                        if (cpu_wdata[1:0] == 2'd1)
                            draw_pixel <= 1'b1;
                        else if (cpu_wdata[1:0] == 2'd2)
                            clear_screen <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
