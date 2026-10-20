`timescale 1ns/1ps

module alu (
    input  wire [15:0] x,
    input  wire [15:0] y,

    input  wire zx,
    input  wire nx,
    input  wire zy,
    input  wire ny,
    input  wire f,
    input  wire no,

    output wire [15:0] out,
    output wire zr,
    output wire ng
);

    wire [15:0] x1;
    assign x1 = zx ? 16'b0 : x;

    wire [15:0] x2;
    assign x2 = nx ? ~x1 : x1;

    wire [15:0] y1;
    assign y1 = zy ? 16'b0 : y;

    wire [15:0] y2;
    assign y2 = ny ? ~y1 : y1;

    wire [15:0] result;
    assign result = f ? (x2 + y2) : (x2 & y2);
    
    assign out = no ? ~result : result;
    
    assign ng = out[15]; 
    assign zr = (out == 16'h0000);

endmodule