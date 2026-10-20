`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module program_ram (
    input wire        clk,
    input wire [14:0] address,
    output wire [15:0] out,

    // Runtime program loading from UART
    input wire        load,
    input wire [14:0] load_address,
    input wire [15:0] load_data
);

    // ============================================================
    // 32K x 16-bit Hack program memory
    //
    // The program is loaded from the PC through UART.
    // program.hex is NOT required.
    // ============================================================

    (* keep = "true" *)
    (* ram_style = "block" *)
    reg [15:0] memory [0:32767];

    // ============================================================
    // RUNTIME PROGRAM WRITE
    // ============================================================

    always @(posedge clk) begin
        if (load) begin
            memory[load_address] <= load_data;
        end
    end

    // ============================================================
    // ASYNCHRONOUS PROGRAM READ
    //
    // Required by the current Hack CPU architecture.
    // ============================================================

    (* keep = "true" *)
    wire [15:0] instruction_word;

    assign instruction_word = memory[address];

    assign out = instruction_word;

endmodule