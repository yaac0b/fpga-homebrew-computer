module tmds_encoder (
    input  wire       clk,
    input  wire       rst,

    input  wire [7:0] data_in,
    input  wire       c0,
    input  wire       c1,
    input  wire       de,

    output reg [9:0]  data_out
);

    // TMDS running disparity.
    // 6 bits gives safe signed headroom for intermediate values.
    reg signed [5:0] balance_acc;

    reg [8:0] q_m;

    reg [4:0] ones;
    reg [4:0] zeros;

    // Signed temporary disparity of q_m[7:0].
    reg signed [5:0] q_balance;

    integer i;

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            data_out    <= 10'b0;
            balance_acc <= 6'sd0;

        end
        else begin

            // --------------------------------------------------------
            // BLANKING / CONTROL PERIOD
            // --------------------------------------------------------
            if (!de) begin

                case ({c1, c0})

                    // CTL0
                    2'b00:
                        data_out <= 10'b1101010100;

                    // CTL1
                    2'b01:
                        data_out <= 10'b0010101011;

                    // CTL2
                    2'b10:
                        data_out <= 10'b0101010100;

                    // CTL3
                    2'b11:
                        data_out <= 10'b1010101011;

                endcase

                // Running disparity is reset during control period.
                balance_acc <= 6'sd0;

            end

            // --------------------------------------------------------
            // ACTIVE VIDEO
            // --------------------------------------------------------
            else begin

                // ----------------------------------------------------
                // Count ones in input byte
                // ----------------------------------------------------
                ones = 5'd0;

                for (i = 0; i < 8; i = i + 1) begin
                    if (data_in[i])
                        ones = ones + 5'd1;
                end

                // ----------------------------------------------------
                // TMDS transition minimization
                //
                // q_m[8] = 0 -> XNOR
                // q_m[8] = 1 -> XOR
                // ----------------------------------------------------
                if ((ones > 5'd4) ||
                    ((ones == 5'd4) && !data_in[0])) begin

                    // XNOR
                    q_m[0] = data_in[0];

                    q_m[1] = q_m[0] ^~ data_in[1];
                    q_m[2] = q_m[1] ^~ data_in[2];
                    q_m[3] = q_m[2] ^~ data_in[3];
                    q_m[4] = q_m[3] ^~ data_in[4];
                    q_m[5] = q_m[4] ^~ data_in[5];
                    q_m[6] = q_m[5] ^~ data_in[6];
                    q_m[7] = q_m[6] ^~ data_in[7];

                    q_m[8] = 1'b0;

                end
                else begin

                    // XOR
                    q_m[0] = data_in[0];

                    q_m[1] = q_m[0] ^ data_in[1];
                    q_m[2] = q_m[1] ^ data_in[2];
                    q_m[3] = q_m[2] ^ data_in[3];
                    q_m[4] = q_m[3] ^ data_in[4];
                    q_m[5] = q_m[4] ^ data_in[5];
                    q_m[6] = q_m[5] ^ data_in[6];
                    q_m[7] = q_m[7-1] ^ data_in[7];

                    q_m[8] = 1'b1;

                end

                // ----------------------------------------------------
                // Count ones and zeros in q_m
                // ----------------------------------------------------
                ones  = 5'd0;
                zeros = 5'd0;

                for (i = 0; i < 8; i = i + 1) begin

                    if (q_m[i])
                        ones = ones + 5'd1;
                    else
                        zeros = zeros + 5'd1;

                end

                // Signed disparity of q_m.
                //
                // Range:
                //   -8 ... +8
                //
                q_balance =
                    $signed({1'b0, ones}) -
                    $signed({1'b0, zeros});

                // ----------------------------------------------------
                // TMDS OUTPUT ENCODING
                // ----------------------------------------------------

                // Case 1:
                // Running disparity is zero, OR q_m has equal
                // numbers of ones and zeros.
                //
                if ((balance_acc == 6'sd0) ||
                    (ones == zeros)) begin

                    data_out[9] = ~q_m[8];
                    data_out[8] = q_m[8];

                    if (q_m[8])
                        data_out[7:0] = q_m[7:0];
                    else
                        data_out[7:0] = ~q_m[7:0];

                    if (q_m[8])
                        balance_acc <= balance_acc + q_balance;
                    else
                        balance_acc <= balance_acc - q_balance;

                end

                // Case 2:
                // Running disparity and q_m disparity have the
                // same sign.
                //
                // Invert the lower 8 bits.
                //
                else if (
                    ((balance_acc > 6'sd0) && (ones > zeros)) ||
                    ((balance_acc < 6'sd0) && (zeros > ones))
                ) begin

                    data_out[9]   = 1'b1;
                    data_out[8]   = q_m[8];
                    data_out[7:0] = ~q_m[7:0];

                    // Correct TMDS disparity update.
                    //
                    // Inversion contributes -q_balance,
                    // plus the q_m[8] correction of +2.
                    if (q_m[8])
                        balance_acc <=
                            balance_acc - q_balance + 6'sd2;
                    else
                        balance_acc <=
                            balance_acc - q_balance;

                end

                // Case 3:
                // Running disparity and q_m disparity have
                // opposite signs.
                //
                // Do not invert the lower 8 bits.
                //
                else begin

                    data_out[9]   = 1'b0;
                    data_out[8]   = q_m[8];
                    data_out[7:0] = q_m[7:0];

                    // Correct TMDS disparity update.
                    if (q_m[8])
                        balance_acc <=
                            balance_acc + q_balance - 6'sd2;
                    else
                        balance_acc <=
                            balance_acc + q_balance;

                end

            end

        end

    end

endmodule