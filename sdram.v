`timescale 1ns/1ps

// ============================================================
// Tang Nano 20K SDRAM Controller
//
// GW2AR-18C embedded SDRAM
//   64 Mbit, 32-bit data bus
//   4 banks x 2048 rows x 256 columns x 32 bits
//
// Byte-based user interface, 23-bit byte address:
//
//   [22:12] = ROW  (11 bits, 2048 rows)
//   [11:10] = BANK (2 bits,  4 banks)
//   [9:2]   = COL  (8 bits,  256 columns)
//   [1:0]   = BYTE lane within the 32-bit word
//
// ------------------------------------------------------------
// CHANGE FROM PREVIOUS VERSION
// ------------------------------------------------------------
//
// SDRAM_CLK used to be driven from a CLKDIV output that was
// divided down from the video PLL. That clock had NO defined
// phase relationship to "clk", which is the clock that actually
// launches every command, address and data bit in this module:
//
//   - rPLL was configured with PSDA_SEL = "0000", i.e. the
//     "phase shifted" CLKOUTP was shifted by zero degrees.
//   - Two independent CLKDIV /5 blocks each start on an
//     arbitrary one of five possible phases of the 135 MHz
//     clock, and CALIB was tied to a constant instead of being
//     pulsed, so nothing aligned them.
//   - Result: the SDRAM sampled its inputs at a phase that was
//     effectively random per power-up, in 7.4 ns steps across a
//     37 ns period. Setup or hold could be violated on any
//     given boot, and no static timing analysis covered it
//     (hence Gowin TA1132 "determined to be a clock but was
//     not created" and PR1014 "generic routing resource will
//     be used to clock signal").
//
// SDRAM_CLK is now produced by an ODDR fed from "clk" with
// D0=0, D1=1. The output is low for the first half of each clk
// period and high for the second half, so SDRAM_CLK rises on
// the FALLING edge of clk: a fixed 180 degree shift.
//
// At 27 MHz that gives roughly 18.5 ns of setup and 18.5 ns of
// hold at the SDRAM, launched and captured from the same clock
// tree, with no extra PLL or CLKDIV resources used.
// ============================================================

module sdram
#(
    parameter         FREQ       = 27_000_000,
    parameter         DATA_WIDTH = 32,
    parameter         ROW_WIDTH  = 11,
    parameter         COL_WIDTH  = 8,
    parameter         BANK_WIDTH = 2,

    parameter [3:0]   CAS   = 4'd2,
    parameter [3:0]   T_WR  = 4'd2,
    parameter [3:0]   T_MRD = 4'd2,
    parameter [3:0]   T_RP  = 4'd1,
    parameter [3:0]   T_RCD = 4'd1,
    parameter [3:0]   T_RC  = 4'd4
)
(
    // ========================================================
    // SDRAM SIDE
    // ========================================================

    inout  [DATA_WIDTH-1:0]     SDRAM_DQ,

    output reg [ROW_WIDTH-1:0]  SDRAM_A,
    output reg [BANK_WIDTH-1:0] SDRAM_BA,

    output                      SDRAM_nCS,
    output reg                  SDRAM_nWE,
    output reg                  SDRAM_nRAS,
    output reg                  SDRAM_nCAS,

    output                      SDRAM_CLK,
    output                      SDRAM_CKE,

    output reg [3:0]            SDRAM_DQM,

    // ========================================================
    // USER SIDE
    // ========================================================

    input                       clk,
    input                       resetn,

    input                       rd,
    input                       wr,
    input                       refresh,

    input  [22:0]               addr,
    input  [7:0]                din,

    output [7:0]                dout,
    output [DATA_WIDTH-1:0]     dout32,

    output reg                  data_ready,
    output reg                  busy
);

    // ========================================================
    // SDRAM CLOCK OUTPUT
    //
    // 180 degree shifted copy of clk, launched from an IOB
    // DDR register so the phase is fixed and analysable.
    // ========================================================

    ODDR u_sdram_clk_oddr (
        .Q0  (SDRAM_CLK),
        .Q1  (),
        .D0  (1'b0),
        .D1  (1'b1),
        .TX  (1'b0),
        .CLK (clk)
    );

    defparam u_sdram_clk_oddr.TXCLK_POL = 1'b0;


    // ========================================================
    // SDRAM DQ
    // ========================================================

    reg dq_oen;
    reg [DATA_WIDTH-1:0] dq_out;

    assign SDRAM_DQ =
        dq_oen
        ? 32'bz
        : dq_out;

    wire [DATA_WIDTH-1:0] dq_in = SDRAM_DQ;


    // ========================================================
    // FIXED SDRAM CONTROL
    // ========================================================

    assign SDRAM_CKE = resetn;
    assign SDRAM_nCS = 1'b0;


    // ========================================================
    // BYTE LANE SELECT / READ DATA
    // ========================================================

    reg [1:0] off;
    reg [7:0] dout_buf;

    wire [7:0] next_dout =
        (off == 2'd0) ? dq_in[7:0]   :
        (off == 2'd1) ? dq_in[15:8]  :
        (off == 2'd2) ? dq_in[23:16] :
                        dq_in[31:24];

    assign dout =
        data_ready
        ? next_dout
        : dout_buf;

    assign dout32 = dq_in;


    // ========================================================
    // STATE MACHINE
    // ========================================================

    reg [2:0] state;

    localparam INIT    = 3'd0;
    localparam CONFIG  = 3'd1;
    localparam IDLE    = 3'd2;
    localparam READ    = 3'd3;
    localparam WRITE   = 3'd4;
    localparam REFRESH = 3'd5;


    // ========================================================
    // SDRAM COMMANDS  {RAS, CAS, WE}
    // ========================================================

    localparam CMD_SetModeReg   = 3'b000;
    localparam CMD_AutoRefresh  = 3'b001;
    localparam CMD_PreCharge    = 3'b010;
    localparam CMD_BankActivate = 3'b011;
    localparam CMD_Write        = 3'b100;
    localparam CMD_Read         = 3'b101;
    localparam CMD_NOP          = 3'b111;


    // ========================================================
    // MODE REGISTER
    //
    // A[2:0] burst length   = 000 -> 1
    // A[3]   burst type     = 0   -> sequential
    // A[6:4] CAS latency    = 010 -> 2
    // A[8:7] operating mode = 00  -> standard
    // A[9]   write burst    = 0   -> burst (length 1 here)
    // ========================================================

    localparam [2:0] BURST_LEN  = 3'b000;
    localparam       BURST_MODE = 1'b0;

    localparam [10:0] MODE_REG =
        {
            4'b0000,
            CAS[2:0],
            BURST_MODE,
            BURST_LEN
        };


    // ========================================================
    // INTERNAL REGISTERS
    // ========================================================

    reg        cfg_now;
    reg [3:0]  cycle;
    reg [7:0]  din_buf;
    reg [22:0] addr_buf;


    // ========================================================
    // SDRAM STATE MACHINE
    // ========================================================

    always @(posedge clk) begin

        cycle <=
            (cycle == 4'd15)
            ? 4'd15
            : cycle + 4'd1;

        // Default command = NOP
        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;


        casex ({state, cycle})

            // =================================================
            // POWER-UP WAIT
            // =================================================

            {INIT, 4'bxxxx}: begin

                if (cfg_now) begin

                    state <= CONFIG;
                    cycle <= 4'd0;

                end

            end


            // =================================================
            // PRECHARGE ALL
            // =================================================

            {CONFIG, 4'd0}: begin

                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}
                    <= CMD_PreCharge;

                SDRAM_A[10] <= 1'b1;

            end


            // =================================================
            // AUTO REFRESH 1
            // =================================================

            {CONFIG, T_RP}: begin

                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}
                    <= CMD_AutoRefresh;

            end


            // =================================================
            // AUTO REFRESH 2
            // =================================================

            {CONFIG, T_RP + T_RC}: begin

                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}
                    <= CMD_AutoRefresh;

            end


            // =================================================
            // LOAD MODE REGISTER
            // =================================================

            {CONFIG, T_RP + T_RC + T_RC}: begin

                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}
                    <= CMD_SetModeReg;

                SDRAM_BA    <= 2'b00;
                SDRAM_A[10:0] <= MODE_REG;

            end


            // =================================================
            // INITIALISATION COMPLETE
            // =================================================

            {CONFIG, T_RP + T_RC + T_RC + T_MRD}: begin

                state <= IDLE;
                busy  <= 1'b0;

            end


            // =================================================
            // IDLE
            // =================================================

            {IDLE, 4'bxxxx}: begin

                if (rd | wr) begin

                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}
                        <= CMD_BankActivate;

                    SDRAM_BA <= addr[11:10];
                    SDRAM_A  <= addr[22:12];

                    state <= rd ? READ : WRITE;

                    addr_buf <= addr;

                    if (wr)
                        din_buf <= din;

                    cycle <= 4'd1;
                    busy  <= 1'b1;

                end

                else if (refresh) begin

                    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}
                        <= CMD_AutoRefresh;

                    state <= REFRESH;

                    cycle <= 4'd1;
                    busy  <= 1'b1;

                end

            end


            // =================================================
            // READ COMMAND (after tRCD)
            // =================================================

            {READ, T_RCD}: begin

                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}
                    <= CMD_Read;

                // A10 = 1 -> auto precharge
                SDRAM_A[10] <= 1'b1;

                // Column address in A[7:0], A[9:8] = 0
                SDRAM_A[9:0] <=
                    {
                        2'b00,
                        addr_buf[COL_WIDTH-1+2:2]
                    };

                SDRAM_DQM <= 4'b0000;

                off <= addr_buf[1:0];

            end


            // =================================================
            // READ DATA VALID
            // =================================================

            {READ, T_RCD + CAS}: begin

                data_ready <= 1'b1;

            end


            // =================================================
            // READ COMPLETE
            // =================================================

            {READ, T_RCD + CAS + 4'd1}: begin

                data_ready <= 1'b0;
                dout_buf   <= next_dout;

                busy  <= 1'b0;
                state <= IDLE;

            end


            // =================================================
            // WRITE COMMAND (after tRCD)
            // =================================================

            {WRITE, T_RCD}: begin

                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}
                    <= CMD_Write;

                // A10 = 1 -> auto precharge
                SDRAM_A[10] <= 1'b1;

                SDRAM_A[9:0] <=
                    {
                        2'b00,
                        addr_buf[COL_WIDTH-1+2:2]
                    };

                // DQM low enables the selected byte lane.
                SDRAM_DQM <=
                    (addr_buf[1:0] == 2'd0) ? 4'b1110 :
                    (addr_buf[1:0] == 2'd1) ? 4'b1101 :
                    (addr_buf[1:0] == 2'd2) ? 4'b1011 :
                                              4'b0111;

                off <= addr_buf[1:0];

                // Byte replicated across all four lanes; DQM
                // selects which one is actually written.
                dq_out <= {din_buf, din_buf, din_buf, din_buf};

                dq_oen <= 1'b0;

            end


            // =================================================
            // RELEASE DQ
            // =================================================

            {WRITE, T_RCD + 4'd1}: begin

                dq_oen    <= 1'b1;
                SDRAM_DQM <= 4'b1111;

            end


            // =================================================
            // WRITE COMPLETE (tWR + tRP after the command)
            // =================================================

            {WRITE, T_RCD + T_WR + T_RP}: begin

                busy  <= 1'b0;
                state <= IDLE;

            end


            // =================================================
            // REFRESH COMPLETE (tRC)
            // =================================================

            {REFRESH, T_RC}: begin

                state <= IDLE;
                busy  <= 1'b0;

            end

        endcase


        // =====================================================
        // RESET
        // =====================================================

        if (~resetn) begin

            busy <= 1'b1;

            dq_oen <= 1'b1;
            dq_out <= 32'd0;

            SDRAM_DQM <= 4'b1111;

            SDRAM_A  <= 11'd0;
            SDRAM_BA <= 2'b00;

            SDRAM_nRAS <= 1'b1;
            SDRAM_nCAS <= 1'b1;
            SDRAM_nWE  <= 1'b1;

            state <= INIT;

            data_ready <= 1'b0;
            dout_buf   <= 8'd0;
            off        <= 2'd0;

            cycle <= 4'd0;

        end

    end


    // ==========================================================
    // POWER-UP DELAY
    //
    // Approximately 200 us of NOP with CKE high before the
    // initialisation sequence starts.
    // ==========================================================

    reg [14:0] rst_cnt;
    reg        rst_done;
    reg        rst_done_p1;

    localparam [14:0] RST_TARGET = FREQ / 1000 * 200 / 1000;


    always @(posedge clk) begin

        rst_done_p1 <= rst_done;

        cfg_now <= rst_done & ~rst_done_p1;


        if (rst_cnt != RST_TARGET) begin

            rst_cnt  <= rst_cnt + 15'd1;
            rst_done <= 1'b0;

        end
        else begin

            rst_done <= 1'b1;

        end


        if (~resetn) begin

            rst_cnt     <= 15'd0;
            rst_done    <= 1'b0;
            rst_done_p1 <= 1'b0;
            cfg_now     <= 1'b0;

        end

    end

endmodule