`timescale 1ns/1ps

// ================================================================
// UART PROGRAM LOADER
//
// PC -> UART -> FPGA
//
// Protocol:
//
//   'L' = 8'h4C
//   16-bit word count, little endian
//   program words, little endian
//
// Example:
//
//   4C
//   04 00
//   C8 EF
//   02 00
//   10 EC
//   02 60
//
// The loader writes the program directly into program RAM.
//
// After the LAST word:
//   1. CPU is stopped
//   2. CPU reset is pulsed
//   3. CPU is released
//   4. CPU starts executing the uploaded program
//
// 'R' = manual reset + run
// 'S' = stop CPU
//
// program.hex is NOT required.
// ================================================================

module uart_loader (
    input wire        clk,
    input wire [7:0]  rx_data,
    input wire        rx_valid,

    output reg        program_load,
    output reg [14:0] program_address,
    output reg [15:0] program_data,

    output reg        cpu_enable,
    output reg        cpu_reset
);

    // ============================================================
    // STATES
    // ============================================================

    localparam [3:0]
        CMD          = 4'd0,
        LEN_LO       = 4'd1,
        LEN_HI       = 4'd2,
        DATA_LO      = 4'd3,
        DATA_HI      = 4'd4,
        START_RESET  = 4'd5,
        START_RUN    = 4'd6;

    // ============================================================
    // COMMANDS
    // ============================================================

    localparam [7:0]
        CMD_LOAD = 8'h4C,     // 'L'
        CMD_RUN  = 8'h52,     // 'R'
        CMD_STOP = 8'h53;     // 'S'

    // ============================================================
    // REGISTERS
    // ============================================================

    reg [3:0] state;

    reg [15:0] word_count;

    reg [14:0] write_addr;

    reg [7:0] lo_byte;

    // ============================================================
    // INITIAL STATE
    // ============================================================

    initial begin
        state           = CMD;

        word_count      = 16'd0;
        write_addr      = 15'd0;
        lo_byte         = 8'd0;

        program_load    = 1'b0;
        program_address = 15'd0;
        program_data    = 16'd0;

        cpu_enable      = 1'b0;
        cpu_reset       = 1'b0;
    end

    // ============================================================
    // MAIN UART LOADER
    // ============================================================

    always @(posedge clk) begin

        // --------------------------------------------------------
        // These are one-cycle pulses.
        // --------------------------------------------------------

        program_load <= 1'b0;
        cpu_reset    <= 1'b0;

        // --------------------------------------------------------
        // AUTOMATIC START SEQUENCE
        // --------------------------------------------------------

        if (state == START_RESET) begin

            // Keep CPU stopped while reset is active.
            cpu_enable <= 1'b0;

            // One clock reset pulse.
            cpu_reset <= 1'b1;

            // Next clock: release reset and run.
            state <= START_RUN;

        end
        else if (state == START_RUN) begin

            // Reset is automatically cleared because
            // cpu_reset is assigned 0 at the beginning
            // of every clock cycle.

            cpu_enable <= 1'b1;

            state <= CMD;
        end

        // --------------------------------------------------------
        // UART RECEIVE STATE MACHINE
        // --------------------------------------------------------

        else if (rx_valid) begin

            case (state)

                // =================================================
                // WAIT FOR COMMAND
                // =================================================

                CMD: begin

                    // ------------------------------------------------
                    // LOAD PROGRAM
                    // ------------------------------------------------

                    if (rx_data == CMD_LOAD) begin

                        // Stop CPU before replacing its program.
                        cpu_enable <= 1'b0;

                        // Start writing from address 0.
                        write_addr <= 15'd0;

                        // Receive word count next.
                        state <= LEN_LO;
                    end

                    // ------------------------------------------------
                    // MANUAL RUN
                    // ------------------------------------------------

                    else if (rx_data == CMD_RUN) begin

                        // CPU stopped during reset.
                        cpu_enable <= 1'b0;

                        state <= START_RESET;
                    end

                    // ------------------------------------------------
                    // MANUAL STOP
                    // ------------------------------------------------

                    else if (rx_data == CMD_STOP) begin

                        cpu_enable <= 1'b0;
                    end

                end

                // =================================================
                // WORD COUNT LOW BYTE
                // =================================================

                LEN_LO: begin

                    word_count[7:0] <= rx_data;

                    state <= LEN_HI;
                end

                // =================================================
                // WORD COUNT HIGH BYTE
                // =================================================

                LEN_HI: begin

                    word_count[15:8] <= rx_data;

                    if ({rx_data, word_count[7:0]} == 16'd0) begin

                        // Empty program.
                        state <= CMD;

                    end
                    else begin

                        state <= DATA_LO;

                    end
                end

                // =================================================
                // PROGRAM WORD LOW BYTE
                // =================================================

                DATA_LO: begin

                    lo_byte <= rx_data;

                    state <= DATA_HI;
                end

                // =================================================
                // PROGRAM WORD HIGH BYTE
                // =================================================

                DATA_HI: begin

                    // ------------------------------------------------
                    // Build 16-bit Hack instruction.
                    // UART sends LOW byte first.
                    // ------------------------------------------------

                    program_data <= {rx_data, lo_byte};

                    program_address <= write_addr;

                    // Tell program RAM to write this word.
                    program_load <= 1'b1;

                    // Next address.
                    write_addr <= write_addr + 15'd1;

                    // One less word remaining.
                    word_count <= word_count - 16'd1;

                    // ------------------------------------------------
                    // LAST WORD
                    // ------------------------------------------------

                    if (word_count == 16'd1) begin

                        // The last RAM write happens on this clock.
                        //
                        // After this clock, move to the reset
                        // sequence. The CPU will therefore start
                        // only after the complete program is in RAM.

                        state <= START_RESET;

                    end
                    else begin

                        state <= DATA_LO;

                    end

                end

                default: begin

                    state <= CMD;

                end

            endcase

        end

    end

endmodule