`timescale 1ns/1ps

module computer (
    input wire clk,
    input wire enable,
    input wire reset,

    input wire [15:0] key_code,

    // Program loader
    input wire program_load,
    input wire [14:0] program_address,
    input wire [15:0] program_data,

    // GPU
    input wire [15:0] gpu_out,

    // ADS1115 and external LED memory-mapped I/O
    output wire [1:0] adc_channel_wdata,
    output wire adc_channel_wr,
    output wire adc_control_wr,
    input wire adc_busy,
    input wire adc_data_valid,
    input wire [15:0] adc_data,
    output wire [15:0] ext_led_reg,
    input wire gpu_busy,

    output wire gpu_load,
    output wire [15:0] gpu_address,
    output wire [15:0] gpu_data,

    // Debug
    output wire [15:0] debug_a,
    output wire [15:0] debug_d,
    output wire [15:0] debug_pc,
    output wire        debug_sdram_timeout,

    // SDRAM
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

    // Unused. Retained for port compatibility with top.v.
    input wire clk_sdram
);

    // =========================================================
    // CPU SIGNALS
    // =========================================================

    wire [14:0] pc;
    wire [15:0] instruction;

    wire [15:0] outM;
    wire        writeM;
    wire [14:0] addressM;
    wire [15:0] inM;

    wire memory_ready;

    // High for exactly the clock on which the CPU retires an
    // instruction. The memory controller needs this to know
    // when a completed SDRAM read has actually been consumed.
    wire cpu_step = enable && memory_ready;


    // =========================================================
    // PROGRAM RAM
    // =========================================================

 
    (* keep = "true" *)
    (* keep_hierarchy = "yes" *)
    program_ram u_program (
        .clk(clk),

        .address(pc),

        .out(instruction),

        .load(program_load),

        .load_address(program_address),

        .load_data(program_data)
    );

    // =========================================================
    // MEMORY
    // =========================================================

    memory u_memory (
        .clk(clk),
        .reset(reset),

        .load(writeM),
        .in(outM),
        .address(addressM),

        .key_code(key_code),
        .instruction(instruction),

        .cpu_ack(cpu_step),
        
        .out(inM),
        .ready(memory_ready),

        .sdram_timeout(debug_sdram_timeout),

        // GPU
        .gpu_load(gpu_load),
        .gpu_address(gpu_address),
        .gpu_data(gpu_data),
        .gpu_busy(gpu_busy),
        .gpu_out(gpu_out),

        .adc_channel_wdata(adc_channel_wdata),
        .adc_channel_wr(adc_channel_wr),
        .adc_control_wr(adc_control_wr),
        .adc_busy(adc_busy),
        .adc_data_valid(adc_data_valid),
        .adc_data(adc_data),
        .ext_led_reg(ext_led_reg),

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


    // =========================================================
    // CPU
    // =========================================================

    cpu u_cpu (
        .clk(clk),

        // CPU advances only when:
        // 1. global enable is active
        // 2. memory system is ready
        .enable(cpu_step),

        .reset(reset),

        .instruction(instruction),

        .inM(inM),

        .outM(outM),
        .writeM(writeM),
        .addressM(addressM),

        .pc(pc),

        .debug_a(debug_a),
        .debug_d(debug_d),
        .debug_pc(debug_pc)
    );

endmodule