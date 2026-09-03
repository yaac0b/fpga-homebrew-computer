module gpu_sdram (
    input wire        mem_clk,
    input wire        mem_clk_sdram,
    input wire        resetn,

    // GPU write interface
    input wire        gpu_wr,
    input wire [16:0] gpu_addr,
    input wire [7:0]  gpu_data,
    output reg        gpu_busy,

    // Video read interface
    input wire        video_req,
    input wire [16:0] video_addr,
    output reg        video_valid,
    output reg [7:0]  video_data,

    // SDRAM
    inout wire [31:0] SDRAM_DQ,

    output wire [10:0] SDRAM_A,
    output wire [1:0]  SDRAM_BA,

    output wire SDRAM_nCS,
    output wire SDRAM_nWE,
    output wire SDRAM_nRAS,
    output wire SDRAM_nCAS,

    output wire SDRAM_CLK,
    output wire SDRAM_CKE,

    output wire [3:0] SDRAM_DQM
);

    reg        sdram_rd;
    reg        sdram_wr;
    reg        sdram_refresh;

    reg [22:0] sdram_addr;
    reg [7:0]  sdram_din;

    wire [7:0]  sdram_dout;
    wire [31:0] sdram_dout32;

    wire sdram_data_ready;
    wire sdram_busy;

    /*
     * Refresh counter.
     *
     * At approximately 64.8 MHz,
     * 970 cycles is about 15 us.
     */
    reg [9:0] refresh_counter;

    wire refresh_request =
        (refresh_counter >= 10'd970);

    localparam ST_IDLE  = 3'd0;
    localparam ST_WRITE = 3'd1;
    localparam ST_READ  = 3'd2;
    localparam ST_REFRESH = 3'd3;

    reg [2:0] state;

    /*
     * Actual SDRAM controller
     */
    sdram #(
        .FREQ(64_800_000),
        .DATA_WIDTH(32),
        .ROW_WIDTH(11),
        .COL_WIDTH(8),
        .BANK_WIDTH(2),
        .CAS(4'd2),
        .T_WR(4'd2),
        .T_MRD(4'd2),
        .T_RP(4'd1),
        .T_RCD(4'd1),
        .T_RC(4'd4)
    ) u_sdram (

        .SDRAM_DQ   (SDRAM_DQ),
        .SDRAM_A    (SDRAM_A),
        .SDRAM_BA   (SDRAM_BA),

        .SDRAM_nCS  (SDRAM_nCS),
        .SDRAM_nWE  (SDRAM_nWE),
        .SDRAM_nRAS (SDRAM_nRAS),
        .SDRAM_nCAS (SDRAM_nCAS),

        .SDRAM_CLK  (SDRAM_CLK),
        .SDRAM_CKE  (SDRAM_CKE),
        .SDRAM_DQM  (SDRAM_DQM),

        .clk        (mem_clk),
        .clk_sdram  (mem_clk_sdram),
        .resetn     (resetn),

        .rd         (sdram_rd),
        .wr         (sdram_wr),
        .refresh    (sdram_refresh),

        .addr       (sdram_addr),
        .din        (sdram_din),

        .dout       (sdram_dout),
        .dout32     (sdram_dout32),

        .data_ready (sdram_data_ready),
        .busy       (sdram_busy)
    );

    always @(posedge mem_clk or negedge resetn) begin

        if (!resetn) begin

            state <= ST_IDLE;

            refresh_counter <= 10'd0;

            sdram_rd      <= 1'b0;
            sdram_wr      <= 1'b0;
            sdram_refresh <= 1'b0;

            sdram_addr <= 23'd0;
            sdram_din  <= 8'd0;

            gpu_busy   <= 1'b0;

            video_valid <= 1'b0;
            video_data  <= 8'h00;

        end
        else begin

            // Default pulse signals
            sdram_rd      <= 1'b0;
            sdram_wr      <= 1'b0;
            sdram_refresh <= 1'b0;

            gpu_busy    <= 1'b0;
            video_valid <= 1'b0;

            // Refresh counter
            if (refresh_counter >= 10'd971)
                refresh_counter <= 10'd0;
            else
                refresh_counter <= refresh_counter + 1'b1;

            case (state)

                ST_IDLE: begin

                    /*
                     * Refresh has priority.
                     */
                    if (refresh_request && !sdram_busy) begin

                        sdram_refresh <= 1'b1;

                        state <= ST_REFRESH;

                    end

                    /*
                     * GPU writes one byte.
                     */
                    else if (gpu_wr && !sdram_busy) begin

                        sdram_addr <= {
                            6'b000000,
                            gpu_addr
                        };

                        sdram_din <= gpu_data;

                        sdram_wr <= 1'b1;

                        gpu_busy <= 1'b1;

                        state <= ST_WRITE;

                    end

                    /*
                     * Video reads one byte.
                     */
                    else if (video_req && !sdram_busy) begin

                        sdram_addr <= {
                            6'b000000,
                            video_addr
                        };

                        sdram_rd <= 1'b1;

                        state <= ST_READ;

                    end

                end


                ST_WRITE: begin

                    gpu_busy <= 1'b1;

                    if (!sdram_busy)
                        state <= ST_IDLE;

                end


                ST_READ: begin

                    if (sdram_data_ready) begin

                        video_data <= sdram_dout;

                        video_valid <= 1'b1;

                        state <= ST_IDLE;

                    end

                end


                ST_REFRESH: begin

                    if (!sdram_busy)
                        state <= ST_IDLE;

                end


                default: begin
                    state <= ST_IDLE;
                end

            endcase

        end

    end

endmodule