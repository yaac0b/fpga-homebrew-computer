`timescale 1ns/1ps
module cpu (
    input  wire        clk,
    input  wire        enable,
    input  wire        reset,
    input  wire [15:0] instruction,
    input  wire [15:0] inM,
    output wire [15:0] outM,
    output wire        writeM,
    output wire [14:0] addressM,
    output wire [14:0] pc,
    output wire [15:0] debug_a,
    output wire [15:0] debug_d,
    output wire [15:0] debug_pc
);
    reg [15:0] A, D;
    reg [14:0] PC;

    wire is_c_instruction = instruction[15];
    wire [15:0] alu_x = D;
    wire [15:0] alu_y = instruction[12] ? inM : A;

    wire [15:0] alu_out;
    wire alu_zr, alu_ng;

    alu cpu_alu (
        .x(alu_x), .y(alu_y),
        .zx(instruction[11]), .nx(instruction[10]),
        .zy(instruction[9]),  .ny(instruction[8]),
        .f(instruction[7]),   .no(instruction[6]),
        .out(alu_out), .zr(alu_zr), .ng(alu_ng)
    );

    wire [2:0] jump = instruction[2:0];

    wire jump_condition =
        (jump == 3'b001 && !alu_ng && !alu_zr) ||
        (jump == 3'b010 &&  alu_zr) ||
        (jump == 3'b011 && !alu_ng) ||
        (jump == 3'b100 &&  alu_ng) ||
        (jump == 3'b101 && !alu_zr) ||
        (jump == 3'b110 && (alu_ng || alu_zr)) ||
        (jump == 3'b111);

    always @(posedge clk) begin
        if (reset) begin
            A  <= 16'h0000;
            D  <= 16'h0000;
            PC <= 15'h0000;
        end else if (enable) begin
            if (!is_c_instruction) begin
                A <= {1'b0, instruction[14:0]};
            end else begin
                if (instruction[5]) A <= alu_out;
                if (instruction[4]) D <= alu_out;
            end

            if (is_c_instruction && jump_condition)
                PC <= A[14:0];
            else
                PC <= PC + 15'd1;
        end
    end

    assign outM     = alu_out;
    assign writeM   = is_c_instruction && instruction[3] && enable && !reset;
    assign addressM = A[14:0];
    assign pc       = PC;

    assign debug_a  = A;
    assign debug_d  = D;
    assign debug_pc = {1'b0, PC};
endmodule
