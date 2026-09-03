`timescale 1ns/1ps

module OSER10 (
    input wire D0,
    input wire D1,
    input wire D2,
    input wire D3,
    input wire D4,
    input wire D5,
    input wire D6,
    input wire D7,
    input wire D8,
    input wire D9,

    input wire PCLK,
    input wire FCLK,
    input wire RESET,

    output reg Q
);

    reg [9:0] shift_reg;

    // Load 10-bit parallel data
    always @(posedge PCLK or posedge RESET) begin
        if (RESET) begin
            shift_reg <= 10'b0;
        end
        else begin
            shift_reg <= {
                D9, D8, D7, D6, D5,
                D4, D3, D2, D1, D0
            };
        end
    end

    // Serialize
    always @(posedge FCLK or posedge RESET) begin
        if (RESET) begin
            Q <= 1'b0;
        end
        else begin
            Q <= shift_reg[0];
            shift_reg <= {1'b0, shift_reg[9:1]};
        end
    end

endmodule
