// ============================================================================
// ads1115_i2c_master.v
//
// I2C master controller for the ADS1115 16-bit ADC, exposing a simple
// CPU-facing register interface so a memory-mapped read/write from your
// custom CPU can trigger a full conversion cycle without the CPU knowing
// anything about I2C.
//
// CPU-visible registers (wire these into your existing address decoder):
//   CHANNEL_SELECT (write) : bits [1:0] select AIN0-AIN3
//   CONTROL        (write) : write 1 to bit 0 to start a conversion
//   CONTROL        (read)  : bit 0 = busy, bit 1 = data_valid
//   DATA           (read)  : 16-bit conversion result (signed)
//
// Physical pins:
//   scl, sda  -> open-drain, both need external ~4.7k pull-ups to 3.3V
//
// Assumes ADDR pin on the ADS1115 is tied to GND (I2C address 0x48).
//
// Target clock: adjust CLK_FREQ_HZ to match your system clock.
// Produces a nominal 100kHz I2C clock (standard mode).
//
// NOTE: this is a teaching-oriented implementation. It does not implement
// clock stretching or bus-arbitration/multi-master support, and has no
// timeout/error recovery if a device fails to ACK. Recommended next step:
// build a self-checking testbench that forces NACK conditions and verifies
// the FSM returns to IDLE safely, and add a watchdog timeout state before
// using this on real hardware you can't easily power-cycle.
// ============================================================================

module ads1115_i2c_master #(
    parameter CLK_FREQ_HZ   = 27_000_000,  // Tang Nano 20K default system clock
    parameter I2C_FREQ_HZ   = 100_000,     // standard-mode I2C
    parameter ADS1115_ADDR  = 7'b1001000   // 0x48, ADDR pin tied to GND
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- CPU-facing memory-mapped interface ----
    input  wire [1:0]  channel_sel_wdata, // value CPU writes to CHANNEL_SELECT
    input  wire        channel_sel_wr,    // pulse: CPU writes CHANNEL_SELECT
    input  wire        control_wr,        // pulse: CPU writes CONTROL (start=1)
    output wire        busy,              // CONTROL read bit 0
    output wire        data_valid,        // CONTROL read bit 1
    output wire [15:0] data,              // DATA register read value

    // ---- Physical I2C bus (open-drain) ----
    inout  wire        scl,
    inout  wire        sda
);

    // ------------------------------------------------------------------
    // I2C bit-clock generator
    // Each I2C bit period is divided into 4 phases:
    //   0: SCL low,  SDA may change   (setup)
    //   1: SCL rises                  (propagation)
    //   2: SCL high, SDA sampled/held (hold)
    //   3: SCL falls                  (release)
    // ------------------------------------------------------------------
    localparam integer QUARTER_PERIOD = CLK_FREQ_HZ / (I2C_FREQ_HZ * 4);

    reg [31:0] clk_div_cnt;
    reg [1:0]  phase;       // 0..3
    reg        tick;        // pulses once per phase

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div_cnt <= 0;
            phase       <= 0;
            tick        <= 0;
        end else if (clk_div_cnt == QUARTER_PERIOD - 1) begin
            clk_div_cnt <= 0;
            phase       <= phase + 1'b1;
            tick        <= 1'b1;
        end else begin
            clk_div_cnt <= clk_div_cnt + 1'b1;
            tick        <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Open-drain bus drivers
    // Drive low actively; release (Z) to let external pull-up take it high.
    // ------------------------------------------------------------------
    reg scl_drive_low;
    reg sda_drive_low;

    assign scl = scl_drive_low ? 1'b0 : 1'bz;
    assign sda = sda_drive_low ? 1'b0 : 1'bz;

    wire sda_in = sda; // read current bus level for ACK/data sampling

    // ------------------------------------------------------------------
    // Register interface: capture CPU writes
    // ------------------------------------------------------------------
    reg [1:0] channel_reg;
    reg       start_req;      // level set on CONTROL write, cleared when FSM starts
    reg       busy_r;
    reg       data_valid_r;
    reg [15:0] data_r;

    assign busy       = busy_r;
    assign data_valid = data_valid_r;
    assign data        = data_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_reg <= 2'b00;
            start_req   <= 1'b0;
        end else begin
            if (channel_sel_wr)
                channel_reg <= channel_sel_wdata;

            if (control_wr)
                start_req <= 1'b1;
            else if (busy_r)
                start_req <= 1'b0; // consumed once FSM picks it up
        end
    end

    // ------------------------------------------------------------------
    // Main FSM
    // Two back-to-back I2C transactions per conversion:
    //   (A) write Config register: select channel, set gain, start conv
    //   (B) point to Conversion register, repeated-start, read 2 bytes
    // ------------------------------------------------------------------
    localparam
        S_IDLE          = 0,
        S_START1        = 1,
        S_ADDR_W1       = 2,
        S_ACK1          = 3,
        S_REGPTR_CFG    = 4,
        S_ACK2          = 5,
        S_CFG_HI        = 6,
        S_ACK3          = 7,
        S_CFG_LO        = 8,
        S_ACK4          = 9,
        S_STOP1         = 10,
        S_WAIT_CONV     = 11, // fixed delay for conversion time
        S_START2        = 12,
        S_ADDR_W2       = 13,
        S_ACK5          = 14,
        S_REGPTR_CONV   = 15,
        S_ACK6          = 16,
        S_RSTART        = 17,
        S_ADDR_R        = 18,
        S_ACK7          = 19,
        S_READ_HI       = 20,
        S_MACK          = 21, // master ACK after high byte
        S_READ_LO       = 22,
        S_MNACK         = 23, // master NACK after low byte
        S_STOP2         = 24,
        S_DONE          = 25;

    reg [4:0]  state;
    reg [3:0]  bit_cnt;
    reg [7:0]  shift_out;
    reg [7:0]  shift_in;
    reg        rw_bit; // 0 = write, 1 = read

    // Conversion wait. The ADS1115 converts in 1/DR seconds: at the 128 SPS
    // configured below that is 7.8125 ms, and the datasheet allows the data
    // rate to be 10% slow (=> 8.6 ms worst case). 10 ms leaves margin.
    // If you change the data-rate bits in build_config, change this too
    // (860 SPS needs ~1.3 ms, 8 SPS needs ~140 ms).
    localparam integer CONV_WAIT_MS     = 10;
    localparam integer CONV_WAIT_CYCLES = (CLK_FREQ_HZ / 1000) * CONV_WAIT_MS;
    reg [31:0] conv_wait_cnt;

    // Config register value: single-shot, FSR=+-4.096V (PGA=001), start
    // single conversion, channel from channel_reg (single-ended AINx vs GND),
    // 128SPS, disable comparator. See ADS1115 datasheet Table 8 for full
    // bit meanings -- adjust MUX bits if you want a different PGA/rate.
    function [15:0] build_config;
        input [1:0] ch;
        reg [2:0] mux;
        begin
            case (ch)
                2'b00: mux = 3'b100; // AIN0 vs GND
                2'b01: mux = 3'b101; // AIN1 vs GND
                2'b10: mux = 3'b110; // AIN2 vs GND
                2'b11: mux = 3'b111; // AIN3 vs GND
            endcase
            // [15]OS [14:12]MUX [11:9]PGA [8]MODE [7:5]DR [4]COMP_MODE
            // [3]COMP_POL [2]COMP_LAT [1:0]COMP_QUE
            build_config = {1'b1, mux, 3'b001, 1'b1, 3'b100, 1'b0, 1'b0, 1'b0, 2'b11};
        end
    endfunction

    reg [15:0] cfg_word;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
            busy_r        <= 1'b0;
            data_valid_r  <= 1'b0;
            data_r        <= 16'h0000;
            bit_cnt       <= 4'd0;
            conv_wait_cnt <= 32'd0;
        end else begin
            case (state)

            // ---------------- IDLE ----------------
            S_IDLE: begin
                scl_drive_low <= 1'b0;
                sda_drive_low <= 1'b0;
                if (start_req) begin
                    busy_r       <= 1'b1;
                    data_valid_r <= 1'b0;
                    cfg_word     <= build_config(channel_reg);
                    state        <= S_START1;
                end
            end

            // ---------------- (A) WRITE CONFIG ----------------
            // SCL is held released (high) in this state until the START has
            // been generated, so SDA falls while SCL is genuinely high.
            S_START1: if (tick) begin
                case (phase)
                    2'd2: sda_drive_low <= 1'b1;       // SDA falls while SCL high = START
                    2'd3: begin                        // SCL falls this same tick (see SCL block)
                        shift_out <= {ADS1115_ADDR, 1'b0}; // address + write bit
                        bit_cnt   <= 4'd7;
                        state     <= S_ADDR_W1;
                    end
                    default: ;
                endcase
            end

            S_ADDR_W1: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= ~shift_out[7]; // MSB first
                    2'd3: begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        if (bit_cnt == 0) state <= S_ACK1;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_ACK1: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0; // release SDA, let slave ACK
                    2'd2: ; // sample point (sda_in low = ACK) -- proceed regardless for brevity
                    2'd3: begin
                        shift_out <= 8'h01; // point to Config register
                        bit_cnt   <= 4'd7;
                        state     <= S_REGPTR_CFG;
                    end
                endcase
            end

            S_REGPTR_CFG: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= ~shift_out[7];
                    2'd3: begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        if (bit_cnt == 0) state <= S_ACK2;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_ACK2: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0;
                    2'd3: begin
                        shift_out <= cfg_word[15:8];
                        bit_cnt   <= 4'd7;
                        state     <= S_CFG_HI;
                    end
                endcase
            end

            S_CFG_HI: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= ~shift_out[7];
                    2'd3: begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        if (bit_cnt == 0) state <= S_ACK3;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_ACK3: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0;
                    2'd3: begin
                        shift_out <= cfg_word[7:0];
                        bit_cnt   <= 4'd7;
                        state     <= S_CFG_LO;
                    end
                endcase
            end

            S_CFG_LO: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= ~shift_out[7];
                    2'd3: begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        if (bit_cnt == 0) state <= S_ACK4;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_ACK4: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0;
                    2'd3: begin
                        state <= S_STOP1;
                    end
                endcase
            end

            S_STOP1: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b1; // SDA low
                    2'd2: sda_drive_low <= 1'b0; // SDA rises while SCL high = STOP
                    2'd3: begin
                        conv_wait_cnt <= 32'd0;
                        state         <= S_WAIT_CONV;
                    end
                endcase
            end

            // ---------------- wait for conversion to finish ----------------
            S_WAIT_CONV: begin
                if (conv_wait_cnt == CONV_WAIT_CYCLES - 1)
                    state <= S_START2;
                else
                    conv_wait_cnt <= conv_wait_cnt + 1'b1;
            end

            // ---------------- (B) READ CONVERSION ----------------
            S_START2: if (tick) begin
                case (phase)
                    2'd2: sda_drive_low <= 1'b1;       // START (SCL held high)
                    2'd3: begin
                        shift_out <= {ADS1115_ADDR, 1'b0};
                        bit_cnt   <= 4'd7;
                        state     <= S_ADDR_W2;
                    end
                    default: ;
                endcase
            end

            S_ADDR_W2: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= ~shift_out[7];
                    2'd3: begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        if (bit_cnt == 0) state <= S_ACK5;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_ACK5: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0;
                    2'd3: begin
                        shift_out <= 8'h00; // point to Conversion register
                        bit_cnt   <= 4'd7;
                        state     <= S_REGPTR_CONV;
                    end
                endcase
            end

            S_REGPTR_CONV: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= ~shift_out[7];
                    2'd3: begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        if (bit_cnt == 0) state <= S_ACK6;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_ACK6: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0;
                    2'd3: state <= S_RSTART;
                endcase
            end

            S_RSTART: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0; // ensure released
                    2'd2: sda_drive_low <= 1'b1; // SDA falls while SCL high = repeated START
                    2'd3: begin
                        shift_out <= {ADS1115_ADDR, 1'b1}; // address + READ bit
                        bit_cnt   <= 4'd7;
                        state     <= S_ADDR_R;
                    end
                endcase
            end

            S_ADDR_R: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= ~shift_out[7];
                    2'd3: begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        if (bit_cnt == 0) state <= S_ACK7;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_ACK7: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0; // release for slave ACK
                    2'd3: begin
                        bit_cnt <= 4'd7;
                        state   <= S_READ_HI;
                    end
                endcase
            end

            S_READ_HI: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0; // master releases SDA while reading
                    2'd2: shift_in <= {shift_in[6:0], sda_in}; // sample on SCL high
                    2'd3: begin
                        if (bit_cnt == 0) state <= S_MACK;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_MACK: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b1; // master drives ACK (more bytes wanted)
                    2'd3: begin
                        data_r[15:8] <= shift_in;
                        bit_cnt      <= 4'd7;
                        state        <= S_READ_LO;
                    end
                endcase
            end

            S_READ_LO: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0;
                    2'd2: shift_in <= {shift_in[6:0], sda_in};
                    2'd3: begin
                        if (bit_cnt == 0) state <= S_MNACK;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                endcase
            end

            S_MNACK: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b0; // master does NOT pull low = NACK ("no more")
                    2'd3: begin
                        data_r[7:0] <= shift_in;
                        state       <= S_STOP2;
                    end
                endcase
            end

            S_STOP2: if (tick) begin
                case (phase)
                    2'd0: sda_drive_low <= 1'b1;
                    2'd2: sda_drive_low <= 1'b0; // SDA rises while SCL high = STOP
                    2'd3: state <= S_DONE;
                endcase
            end

            S_DONE: begin
                busy_r       <= 1'b0;
                data_valid_r <= 1'b1;
                state        <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase

            // ---- SCL generation ----
            // 50% duty cycle: SCL falls at phase 3, stays low through phase 0,
            // rises at phase 1, stays high through phase 2.
            //   - SDA is changed at phase 0 (SCL already low for a quarter
            //     period), so data never changes at the same instant as SCL.
            //   - SDA is sampled at phase 2 (middle of SCL high).
            // SCL is held released (high) while the bus is idle: IDLE, DONE,
            // the conversion wait, and the START states up to the moment the
            // START condition has been generated.
            if (state == S_IDLE || state == S_DONE || state == S_WAIT_CONV) begin
                scl_drive_low <= 1'b0;
            end else if (state == S_START1 || state == S_START2) begin
                // First pull SCL low only after SDA has already fallen
                // (sda_drive_low == 1), on the same tick the FSM moves on.
                if (tick && phase == 2'd3 && sda_drive_low)
                    scl_drive_low <= 1'b1;
            end else if (tick) begin
                case (phase)
                    // Don't pull SCL low after the STOP's SDA rise: the bus
                    // should simply stay idle-high.
                    2'd3: if (state != S_STOP1 && state != S_STOP2)
                              scl_drive_low <= 1'b1;
                    2'd1: scl_drive_low <= 1'b0;
                    default: ; // hold
                endcase
            end
        end
    end

endmodule
