
`timescale 1ns/1ps

module top (
    input wire clk,
    input wire uart_rx,

    // ADS1115 I2C interface
    inout wire ads_scl,
    inout wire ads_sda,

    // External 16-bit LED output
    output wire [15:0] ext_led,

    // SDRAM interface
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    inout wire [31:0]  IO_sdram_dq,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm,

    // HDMI interface
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire tmds_d0_p,
    output wire tmds_d0_n,
    output wire tmds_d1_p,
    output wire tmds_d1_n,
    output wire tmds_d2_p,
    output wire tmds_d2_n,

    // Onboard LEDs
    output wire [5:0] led
);

    // ============================================================
    // CLOCK
    // ============================================================

    wire clk27;
    assign clk27 = clk;

    // ============================================================
    // POWER-UP RESET
    // ============================================================

    reg [23:0] reset_counter = 24'd0;
    reg reset = 1'b1;

    always @(posedge clk27) begin
        if (reset_counter != 24'hFFFFFF) begin
            reset_counter <= reset_counter + 24'd1;
            reset <= 1'b1;
        end else begin
            reset <= 1'b0;
        end
    end

    // ============================================================
    // USB KEYBOARD REMOVED
    // ============================================================

    wire [15:0] key_code = 16'h0000;

    // ============================================================
    // UART RECEIVER
    // ============================================================

    wire [7:0] rx_data;
    wire rx_valid;

    uart_rx u_uart_rx (
        .clk(clk27),
        .rx(uart_rx),
        .data(rx_data),
        .data_valid(rx_valid)
    );

    // ============================================================
    // UART PROGRAM LOADER
    // ============================================================

    wire program_load;
    wire [14:0] program_address;
    wire [15:0] program_data;

    wire uart_cpu_enable;
    wire uart_cpu_reset;

    uart_loader u_uart_loader (
        .clk(clk27),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .program_load(program_load),
        .program_address(program_address),
        .program_data(program_data),
        .cpu_enable(uart_cpu_enable),
        .cpu_reset(uart_cpu_reset)
    );

    // ============================================================
    // CPU CONTROL
    // ============================================================

    wire cpu_enable;
    wire computer_reset;

    assign computer_reset = reset | uart_cpu_reset;
    assign cpu_enable = (~reset) & uart_cpu_enable;

    // ============================================================
    // GPU BUS
    // ============================================================

    wire gpu_load;
    wire [15:0] gpu_address;
    wire [15:0] gpu_data;
    wire [15:0] gpu_out;
    wire gpu_busy;

    // ============================================================
    // DEBUG AND ADC SIGNALS
    // ============================================================

    wire [15:0] debug_a;
    wire [15:0] debug_d;
    wire [15:0] debug_pc;
    wire debug_sdram_timeout;

    wire [1:0] adc_channel_wdata;
    wire adc_channel_wr;
    wire adc_control_wr;

    wire adc_busy;
    wire adc_data_valid;
    wire [15:0] adc_data;

    wire [15:0] ext_led_reg;

    // ============================================================
    // SDRAM CLOCK
    // ============================================================

    wire clk_sdram;
    assign clk_sdram = clk27;

    wire gpu_sdram_clk;

    // ============================================================
    // HACK COMPUTER
    // ============================================================

    computer u_computer (
        .clk(clk27),
        .enable(cpu_enable),
        .reset(computer_reset),

        .key_code(key_code),

        // UART program loading
        .program_load(program_load),
        .program_address(program_address),
        .program_data(program_data),

        // GPU
        .gpu_out(gpu_out),
        .gpu_busy(gpu_busy),
        .gpu_load(gpu_load),
        .gpu_address(gpu_address),
        .gpu_data(gpu_data),

        // ADS1115 and external LEDs
        .adc_channel_wdata(adc_channel_wdata),
        .adc_channel_wr(adc_channel_wr),
        .adc_control_wr(adc_control_wr),
        .adc_busy(adc_busy),
        .adc_data_valid(adc_data_valid),
        .adc_data(adc_data),
        .ext_led_reg(ext_led_reg),

        // Debug
        .debug_a(debug_a),
        .debug_d(debug_d),
        .debug_pc(debug_pc),
        .debug_sdram_timeout(debug_sdram_timeout),

        // SDRAM
        .O_sdram_clk(O_sdram_clk),
        .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n),
        .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq),
        .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm),
        .clk_sdram(clk_sdram)
    );

    // ============================================================
    // GPU AND HDMI
    // ============================================================

    gpu_top u_gpu (
        .clk27(clk27),
        .rst(reset),

        .gpu_load(gpu_load),
        .gpu_address(gpu_address),
        .gpu_data(gpu_data),

        .gpu_out(gpu_out),
        .gpu_busy(gpu_busy),
        .sdram_clk(gpu_sdram_clk),

        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_d0_p(tmds_d0_p),
        .tmds_d0_n(tmds_d0_n),
        .tmds_d1_p(tmds_d1_p),
        .tmds_d1_n(tmds_d1_n),
        .tmds_d2_p(tmds_d2_p),
        .tmds_d2_n(tmds_d2_n)
    );

    // ============================================================
    // ADS1115 ADC INTERFACE
    // ============================================================

    ads1115_i2c_master #(
        .CLK_FREQ_HZ(27_000_000),
        .I2C_FREQ_HZ(100_000),
        .ADS1115_ADDR(7'b1001000)
    ) u_ads1115_i2c_master (
        .clk(clk27),
        .rst_n(~reset),

        .channel_sel_wdata(adc_channel_wdata),
        .channel_sel_wr(adc_channel_wr),
        .control_wr(adc_control_wr),

        .busy(adc_busy),
        .data_valid(adc_data_valid),
        .data(adc_data),

        .scl(ads_scl),
        .sda(ads_sda)
    );

    // ============================================================
    // EXTERNAL LED OUTPUT
    // ============================================================

    assign ext_led = ext_led_reg;

    // ============================================================
    // ONBOARD DEBUG LEDS
    // ============================================================

    assign led[0] = debug_pc[0];
    assign led[1] = debug_pc[1];
    assign led[2] = debug_pc[2];
    assign led[3] = debug_a[0];
    assign led[4] = debug_d[0];
    assign led[5] = 1'b0;

endmodule
