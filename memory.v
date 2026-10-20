
`timescale 1ns/1ps

module memory (
    input wire clk,
    input wire reset,
    input wire load,

    input wire [15:0] in,
    input wire [14:0] address,
    input wire [15:0] key_code,
    input wire [15:0] instruction,
    input wire cpu_ack,
    input wire gpu_busy,

    output wire [15:0] out,
    output wire ready,
    output wire sdram_timeout,

    // GPU interface
    output wire        gpu_load,
    output wire [15:0] gpu_address,
    output wire [15:0] gpu_data,
    input  wire [15:0] gpu_out,

    // ADS1115 memory-mapped interface
    output wire [1:0]  adc_channel_wdata,
    output wire        adc_channel_wr,
    output wire        adc_control_wr,
    input  wire        adc_busy,
    input  wire        adc_data_valid,
    input  wire [15:0] adc_data,

    // External 16-bit LED output register
    output reg [15:0] ext_led_reg,

    // SDRAM physical interface
    output wire O_sdram_clk,
    output wire O_sdram_cke,
    output wire O_sdram_cs_n,
    output wire O_sdram_cas_n,
    output wire O_sdram_ras_n,
    output wire O_sdram_wen_n,

    inout wire [31:0] IO_sdram_dq,

    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm,

    input wire clk_sdram
);

    // ============================================================
    // ADDRESS DECODING
    // ============================================================

    wire ram_select =
        (address <= 15'h3FFF);

    wire gpu_select =
        (address >= 15'h6000) &&
        (address <= 15'h600A);

    wire keyboard_select =
        (address == 15'h7FFF);

    // ADS1115 and external LED registers
    wire adc_channel_select =
        (address == 15'h6010);

    wire adc_control_select =
        (address == 15'h6011);

    wire adc_data_select =
        (address == 15'h6012);

    wire ext_led_select =
        (address == 15'h6014);

    // ADC channel register and LED output register
    reg [1:0] adc_channel_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            adc_channel_reg <= 2'b00;
            ext_led_reg <= 16'h0000;
        end else begin
            if (load && ready && adc_channel_select)
                adc_channel_reg <= in[1:0];

            if (load && ready && ext_led_select)
                ext_led_reg <= in;
        end
    end

    assign adc_channel_wdata = adc_channel_reg;

    assign adc_channel_wr =
        load && ready && adc_channel_select;

    assign adc_control_wr =
        load && ready && adc_control_select && in[0];

    // ============================================================
    // CPU SDRAM ACCESS DETECTION
    // ============================================================

    wire cpu_ram_read =
        instruction[15] &&
        instruction[12] &&
        ram_select;

    wire cpu_ram_write =
        load && ram_select;

    // ============================================================
    // FSM STATES
    // ============================================================

    reg [3:0] state;

    localparam IDLE            = 4'd0;
    localparam READ_LOW_ACK    = 4'd1;
    localparam READ_LOW_WAIT   = 4'd2;
    localparam READ_HIGH_CMD   = 4'd3;
    localparam READ_HIGH_ACK   = 4'd4;
    localparam READ_HIGH_WAIT  = 4'd5;
    localparam WRITE_LOW_ACK   = 4'd6;
    localparam WRITE_LOW_WAIT  = 4'd7;
    localparam WRITE_HIGH_ACK  = 4'd8;
    localparam WRITE_HIGH_WAIT = 4'd9;
    localparam REFRESH_ACK     = 4'd10;
    localparam REFRESH_WAIT    = 4'd11;

    // ============================================================
    // TRANSACTION REGISTERS
    // ============================================================

    reg [22:0] pending_addr;
    reg [15:0] pending_write_data;

    reg [7:0] read_low;
    reg [15:0] read_word;
    reg read_valid;

    // ============================================================
    // SDRAM CONTROLLER SIGNALS
    // ============================================================

    reg sdram_rd;
    reg sdram_wr;
    reg sdram_refresh;

    reg [22:0] sdram_addr;
    reg [7:0] sdram_din;

    wire [7:0] sdram_dout;
    wire sdram_data_ready;
    wire sdram_busy;

    // ============================================================
    // REFRESH TIMER
    // ============================================================

    reg [8:0] refresh_count;

    wire refresh_due =
        (refresh_count >= 9'd404);

    // ============================================================
    // WATCHDOG
    // ============================================================

    reg [9:0] watchdog;
    reg timeout_flag;

    assign sdram_timeout = timeout_flag;

    // ============================================================
    // MAIN MEMORY FSM
    // ============================================================

    always @(posedge clk) begin

        // One-clock SDRAM command pulses
        sdram_rd      <= 1'b0;
        sdram_wr      <= 1'b0;
        sdram_refresh <= 1'b0;

        if (reset) begin
            state <= IDLE;

            pending_addr <= 23'd0;
            pending_write_data <= 16'd0;

            read_low <= 8'd0;
            read_word <= 16'd0;
            read_valid <= 1'b0;

            sdram_addr <= 23'd0;
            sdram_din <= 8'd0;

            refresh_count <= 9'd0;
            watchdog <= 10'd0;
            timeout_flag <= 1'b0;
        end else begin

            // Refresh timer
            if (refresh_count != 9'd511)
                refresh_count <= refresh_count + 9'd1;

            // Watchdog
            if (state == IDLE)
                watchdog <= 10'd0;
            else
                watchdog <= watchdog + 10'd1;

            case (state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------
                IDLE: begin
                    if (refresh_due && !sdram_busy) begin
                        sdram_refresh <= 1'b1;
                        refresh_count <= 9'd0;
                        state <= REFRESH_ACK;
                    end else if (cpu_ram_write && !sdram_busy) begin
                        pending_addr <= {address, 1'b0};
                        pending_write_data <= in;

                        sdram_addr <= {address, 1'b0};
                        sdram_din <= in[7:0];
                        sdram_wr <= 1'b1;

                        state <= WRITE_LOW_ACK;
                    end else if (
                        cpu_ram_read &&
                        !read_valid &&
                        !sdram_busy
                    ) begin
                        pending_addr <= {address, 1'b0};

                        sdram_addr <= {address, 1'b0};
                        sdram_rd <= 1'b1;

                        state <= READ_LOW_ACK;
                    end
                end

                // ------------------------------------------------
                // READ LOW BYTE
                // ------------------------------------------------
                READ_LOW_ACK: begin
                    if (sdram_busy)
                        state <= READ_LOW_WAIT;
                end

                READ_LOW_WAIT: begin
                    if (sdram_data_ready) begin
                        read_low <= sdram_dout;
                        state <= READ_HIGH_CMD;
                    end
                end

                // ------------------------------------------------
                // READ HIGH BYTE
                // ------------------------------------------------
                READ_HIGH_CMD: begin
                    if (!sdram_busy) begin
                        sdram_addr <= pending_addr + 23'd1;
                        sdram_rd <= 1'b1;
                        state <= READ_HIGH_ACK;
                    end
                end

                READ_HIGH_ACK: begin
                    if (sdram_busy)
                        state <= READ_HIGH_WAIT;
                end

                READ_HIGH_WAIT: begin
                    if (sdram_data_ready) begin
                        read_word <= {sdram_dout, read_low};
                        read_valid <= 1'b1;
                        state <= IDLE;
                    end
                end

                // ------------------------------------------------
                // WRITE LOW BYTE
                // ------------------------------------------------
                WRITE_LOW_ACK: begin
                    if (sdram_busy)
                        state <= WRITE_LOW_WAIT;
                end

                WRITE_LOW_WAIT: begin
                    if (!sdram_busy) begin
                        sdram_addr <= pending_addr + 23'd1;
                        sdram_din <= pending_write_data[15:8];
                        sdram_wr <= 1'b1;
                        state <= WRITE_HIGH_ACK;
                    end
                end

                // ------------------------------------------------
                // WRITE HIGH BYTE
                // ------------------------------------------------
                WRITE_HIGH_ACK: begin
                    if (sdram_busy)
                        state <= WRITE_HIGH_WAIT;
                end

                WRITE_HIGH_WAIT: begin
                    if (!sdram_busy)
                        state <= IDLE;
                end

                // ------------------------------------------------
                // SDRAM REFRESH
                // ------------------------------------------------
                REFRESH_ACK: begin
                    if (sdram_busy)
                        state <= REFRESH_WAIT;
                end

                REFRESH_WAIT: begin
                    if (!sdram_busy)
                        state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase

            // Watchdog timeout
            if ((state != IDLE) && (watchdog == 10'd1023)) begin
                state <= IDLE;
                timeout_flag <= 1'b1;
            end

            // CPU consumes completed SDRAM read
            if (cpu_ack)
                read_valid <= 1'b0;

        end
    end

    // ============================================================
    // SDRAM CONTROLLER
    // ============================================================

    sdram #(
        .FREQ(27_000_000)
    ) u_sdram (
        .SDRAM_DQ(IO_sdram_dq),
        .SDRAM_A(O_sdram_addr),
        .SDRAM_BA(O_sdram_ba),
        .SDRAM_nCS(O_sdram_cs_n),
        .SDRAM_nWE(O_sdram_wen_n),
        .SDRAM_nRAS(O_sdram_ras_n),
        .SDRAM_nCAS(O_sdram_cas_n),
        .SDRAM_CLK(O_sdram_clk),
        .SDRAM_CKE(O_sdram_cke),
        .SDRAM_DQM(O_sdram_dqm),

        .clk(clk),
        .resetn(~reset),

        .rd(sdram_rd),
        .wr(sdram_wr),
        .refresh(sdram_refresh),

        .addr(sdram_addr),
        .din(sdram_din),

        .dout(sdram_dout),
        .dout32(),

        .data_ready(sdram_data_ready),
        .busy(sdram_busy)
    );

    // ============================================================
    // CPU READY
    // ============================================================

    assign ready =
        !reset &&
        !sdram_busy &&
        (state == IDLE) &&
        !refresh_due &&
        !gpu_busy &&
        (!cpu_ram_read || read_valid);

    // ============================================================
    // GPU BUS
    // ============================================================

    assign gpu_load =
        load &&
        gpu_select &&
        ready;

    assign gpu_address = {1'b0, address};
    assign gpu_data = in;

    // ============================================================
    // CPU READ DATA MULTIPLEXER
    // ============================================================

    assign out =
        ram_select         ? read_word :
        gpu_select         ? gpu_out :
        adc_channel_select ? {14'b0, adc_channel_reg} :
        adc_control_select ? {14'b0, adc_data_valid, adc_busy} :
        adc_data_select    ? adc_data :
        ext_led_select     ? ext_led_reg :
        keyboard_select    ? key_code :
        16'h0000;

endmodule
