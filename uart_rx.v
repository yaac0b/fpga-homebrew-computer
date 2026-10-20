`timescale 1ns/1ps

module uart_rx (
    input wire clk,
    input wire rx,

    output reg [7:0] data,
    output reg       data_valid
);

    localparam integer CLK_FREQ      = 27_000_000;
    localparam integer BAUD_RATE     = 115_200;
    localparam integer CLKS_PER_BIT  = 234;

    localparam [1:0]
        IDLE  = 2'd0,
        START = 2'd1,
        DATA  = 2'd2,
        STOP  = 2'd3;

    reg [1:0] rx_sync;

    reg [1:0] state = IDLE;

    reg [15:0] clock_count = 16'd0;

    reg [2:0] bit_count = 3'd0;

    reg [7:0] rx_data = 8'd0;

    // ------------------------------------------------------------
    // INPUT SYNCHRONIZER
    // ------------------------------------------------------------

    always @(posedge clk) begin
        rx_sync[0] <= rx;
        rx_sync[1] <= rx_sync[0];
    end

    // ------------------------------------------------------------
    // UART STATE MACHINE
    // ------------------------------------------------------------

    always @(posedge clk) begin

        data_valid <= 1'b0;

        case (state)

            IDLE: begin

                if (rx_sync[1] == 1'b0) begin

                    state <= START;

                    clock_count <= CLKS_PER_BIT / 2;

                end

            end

            START: begin

                if (clock_count == 16'd0) begin

                    if (rx_sync[1] == 1'b0) begin

                        state <= DATA;

                        clock_count <= CLKS_PER_BIT - 1;

                        bit_count <= 3'd0;

                    end
                    else begin

                        state <= IDLE;

                    end

                end
                else begin

                    clock_count <= clock_count - 16'd1;

                end

            end

            DATA: begin

                if (clock_count == 16'd0) begin

                    rx_data[bit_count] <= rx_sync[1];

                    if (bit_count == 3'd7) begin

                        state <= STOP;

                        clock_count <= CLKS_PER_BIT - 1;

                    end
                    else begin

                        bit_count <= bit_count + 3'd1;

                        clock_count <= CLKS_PER_BIT - 1;

                    end

                end
                else begin

                    clock_count <= clock_count - 16'd1;

                end

            end

            STOP: begin

                if (clock_count == 16'd0) begin

                    data <= rx_data;

                    data_valid <= 1'b1;

                    state <= IDLE;

                end
                else begin

                    clock_count <= clock_count - 16'd1;

                end

            end

            default: begin

                state <= IDLE;

            end

        endcase

    end

endmodule