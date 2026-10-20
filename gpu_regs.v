`timescale 1ns/1ps

// ============================================================
// gpu_regs.v
//
// GPU register interface with one pending-command slot.
// Commands written while the renderer is busy are held until
// the renderer becomes idle.
//
// Register map:
//   6000 CONTROL  bit 0 = GPU enable
//   6001 STATUS   read-only in gpu_top
//   6002 COMMAND
//   6003 X
//   6004 Y
//   6005 X2
//   6006 Y2
//   6007 COLOR
//   6008 SIZE
//   6009 PARAM0
//   600A PARAM1
// ============================================================

module gpu_regs (
    input  wire        clk,
    input  wire        rst,

    input  wire        cpu_we,
    input  wire [15:0] cpu_addr,
    input  wire [15:0] cpu_wdata,

    input  wire        renderer_busy,

    output reg         gpu_enable,

    output reg  [7:0]  command,
    output reg         command_valid,

    output reg  [7:0]  x,
    output reg  [7:0]  y,
    output reg  [7:0]  x2,
    output reg  [7:0]  y2,

    output reg  [7:0]  color,
    output reg  [15:0] size,
    output reg  [15:0] param0,
    output reg  [15:0] param1
);

    // One pending command. The parameters are captured at the
    // moment the COMMAND register is written.
    reg        pending;
    reg [7:0]  pending_command;
    reg [7:0]  pending_x;
    reg [7:0]  pending_y;
    reg [7:0]  pending_x2;
    reg [7:0]  pending_y2;
    reg [7:0]  pending_color;
    reg [15:0] pending_size;
    reg [15:0] pending_param0;
    reg [15:0] pending_param1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gpu_enable    <= 1'b0;

            command       <= 8'd0;
            command_valid <= 1'b0;

            x             <= 8'd0;
            y             <= 8'd0;
            x2            <= 8'd0;
            y2            <= 8'd0;
            color         <= 8'd0;
            size          <= 16'd0;
            param0        <= 16'd0;
            param1        <= 16'd0;

            pending       <= 1'b0;
            pending_command <= 8'd0;
            pending_x     <= 8'd0;
            pending_y     <= 8'd0;
            pending_x2    <= 8'd0;
            pending_y2    <= 8'd0;
            pending_color <= 8'd0;
            pending_size  <= 16'd0;
            pending_param0 <= 16'd0;
            pending_param1 <= 16'd0;
        end
        else begin
            // command_valid is a one-clock pulse.
            command_valid <= 1'b0;

            // --------------------------------------------------
            // CPU register writes
            // --------------------------------------------------
            if (cpu_we) begin
                case (cpu_addr)
                    16'h6000: begin
                        gpu_enable <= cpu_wdata[0];
                        if (!cpu_wdata[0])
                            pending <= 1'b0;
                    end

                    16'h6002: begin
                        // Renderer is idle and no command is waiting:
                        // issue immediately.
                        if (gpu_enable && !renderer_busy && !pending) begin
                            command       <= cpu_wdata[7:0];
                            command_valid <= 1'b1;
                        end
                        // Renderer is busy: capture this command.
                        else if (gpu_enable && renderer_busy && !pending) begin
                            pending         <= 1'b1;
                            pending_command <= cpu_wdata[7:0];

                            pending_x       <= x;
                            pending_y       <= y;
                            pending_x2      <= x2;
                            pending_y2      <= y2;
                            pending_color   <= color;
                            pending_size    <= size;
                            pending_param0  <= param0;
                            pending_param1  <= param1;
                        end
                    end

                    16'h6003: x      <= cpu_wdata[7:0];
                    16'h6004: y      <= cpu_wdata[7:0];
                    16'h6005: x2     <= cpu_wdata[7:0];
                    16'h6006: y2     <= cpu_wdata[7:0];
                    16'h6007: color  <= cpu_wdata[7:0];
                    16'h6008: size   <= cpu_wdata;
                    16'h6009: param0 <= cpu_wdata;
                    16'h600A: param1 <= cpu_wdata;
                    default: ;
                endcase
            end

            // --------------------------------------------------
            // Release pending command when renderer becomes idle.
            // --------------------------------------------------
            if (pending && !renderer_busy && gpu_enable) begin
                command       <= pending_command;
                x             <= pending_x;
                y             <= pending_y;
                x2            <= pending_x2;
                y2            <= pending_y2;
                color         <= pending_color;
                size          <= pending_size;
                param0        <= pending_param0;
                param1        <= pending_param1;

                command_valid <= 1'b1;
                pending       <= 1'b0;
            end
        end
    end

endmodule
