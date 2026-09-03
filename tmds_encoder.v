module tmds_encoder (
    input  wire       clk,
    input  wire       rst,

    input  wire [7:0] data_in,
    input  wire       c0,
    input  wire       c1,
    input  wire       de,

    output reg [9:0]  data_out
);

    reg signed [4:0] balance_acc;

    reg [8:0] q_m;

    reg [4:0] ones;
    reg [4:0] zeros;

    integer i;

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            data_out    <= 10'b0;
            balance_acc <= 5'sd0;

        end
        else begin

            if (!de) begin

                case ({c1,c0})

                    2'b00:
                        data_out <= 10'b1101010100;

                    2'b01:
                        data_out <= 10'b0010101011;

                    2'b10:
                        data_out <= 10'b0101010100;

                    2'b11:
                        data_out <= 10'b1010101011;

                endcase

                balance_acc <= 5'sd0;

            end
            else begin

                // Count ones in input
                ones = 5'd0;

                for (i = 0; i < 8; i = i + 1)
                    ones = ones + data_in[i];

                // Generate q_m
                if ((ones > 5'd4) ||
                    ((ones == 5'd4) && !data_in[0])) begin

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

                    q_m[0] = data_in[0];
                    q_m[1] = q_m[0] ^ data_in[1];
                    q_m[2] = q_m[1] ^ data_in[2];
                    q_m[3] = q_m[2] ^ data_in[3];
                    q_m[4] = q_m[3] ^ data_in[4];
                    q_m[5] = q_m[4] ^ data_in[5];
                    q_m[6] = q_m[5] ^ data_in[6];
                    q_m[7] = q_m[6] ^ data_in[7];

                    q_m[8] = 1'b1;

                end

                // Count q_m ones / zeros
                ones  = 5'd0;
                zeros = 5'd0;

                for (i = 0; i < 8; i = i + 1) begin

                    if (q_m[i])
                        ones = ones + 1'b1;
                    else
                        zeros = zeros + 1'b1;

                end

                if ((balance_acc == 0) ||
                    (ones == zeros)) begin

                    data_out[9] = ~q_m[8];
                    data_out[8] = q_m[8];

                    if (q_m[8])
                        data_out[7:0] = q_m[7:0];
                    else
                        data_out[7:0] = ~q_m[7:0];

                    if (q_m[8])
                        balance_acc <=
                            balance_acc + (ones - zeros);
                    else
                        balance_acc <=
                            balance_acc + (zeros - ones);

                end
                else if (
                    ((balance_acc > 0) && (ones > zeros)) ||
                    ((balance_acc < 0) && (zeros > ones))
                ) begin

                    data_out[9]   = 1'b1;
                    data_out[8]   = q_m[8];
                    data_out[7:0] = ~q_m[7:0];

                    balance_acc <=
                        balance_acc + (zeros - ones);

                end
                else begin

                    data_out[9]   = 1'b0;
                    data_out[8]   = q_m[8];
                    data_out[7:0] = q_m[7:0];

                    balance_acc <=
                        balance_acc + (ones - zeros);

                end

            end

        end

    end

endmodule