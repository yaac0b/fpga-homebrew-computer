module tmds_encoder (
    input wire       clk,
    input wire       rst,
    input wire [7:0] data_in,
    input wire       c0,
    input wire       c1,
    input wire       de,
    output reg [9:0] data_out
);
    reg signed [5:0] disparity;
    reg [8:0] q_m;
    reg [4:0] ones_d;
    reg [4:0] ones_q;
    reg [4:0] zeros_q;
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 10'b0;
            disparity <= 6'sd0;
        end else begin
            if (!de) begin
                case ({c1,c0})
                    2'b00: data_out <= 10'b1101010100;
                    2'b01: data_out <= 10'b0010101011;
                    2'b10: data_out <= 10'b0101010100;
                    2'b11: data_out <= 10'b1010101011;
                endcase
                disparity <= 6'sd0;
            end else begin
                ones_d = 5'd0;
                for (i=0;i<8;i=i+1)
                    ones_d = ones_d + data_in[i];

                q_m[0] = data_in[0];

                if ((ones_d > 5'd4) ||
                    ((ones_d == 5'd4) && (data_in[0] == 1'b0))) begin
                    q_m[1] = q_m[0] ^ ~data_in[1];
                    q_m[2] = q_m[1] ^ ~data_in[2];
                    q_m[3] = q_m[2] ^ ~data_in[3];
                    q_m[4] = q_m[3] ^ ~data_in[4];
                    q_m[5] = q_m[4] ^ ~data_in[5];
                    q_m[6] = q_m[5] ^ ~data_in[6];
                    q_m[7] = q_m[6] ^ ~data_in[7];
                    q_m[8] = 1'b0;
                end else begin
                    q_m[1] = q_m[0] ^ data_in[1];
                    q_m[2] = q_m[1] ^ data_in[2];
                    q_m[3] = q_m[2] ^ data_in[3];
                    q_m[4] = q_m[3] ^ data_in[4];
                    q_m[5] = q_m[4] ^ data_in[5];
                    q_m[6] = q_m[5] ^ data_in[6];
                    q_m[7] = q_m[6] ^ data_in[7];
                    q_m[8] = 1'b1;
                end

                ones_q = 5'd0;
                zeros_q = 5'd0;
                for (i=0;i<8;i=i+1) begin
                    if (q_m[i]) ones_q = ones_q + 5'd1;
                    else zeros_q = zeros_q + 5'd1;
                end

                if ((disparity == 0) || (ones_q == zeros_q)) begin
                    data_out[9] = ~q_m[8];
                    data_out[8] = q_m[8];
                    if (q_m[8]) data_out[7:0] = q_m[7:0];
                    else        data_out[7:0] = ~q_m[7:0];

                    if (q_m[8])
                        disparity <= disparity + $signed({1'b0,ones_q}) - $signed({1'b0,zeros_q});
                    else
                        disparity <= disparity + $signed({1'b0,zeros_q}) - $signed({1'b0,ones_q});
                end else if (((disparity > 0) && (ones_q > zeros_q)) ||
                             ((disparity < 0) && (zeros_q > ones_q))) begin
                    data_out[9] = 1'b1;
                    data_out[8] = q_m[8];
                    data_out[7:0] = ~q_m[7:0];
                    disparity <= disparity + $signed({1'b0,zeros_q}) - $signed({1'b0,ones_q});
                end else begin
                    data_out[9] = 1'b0;
                    data_out[8] = q_m[8];
                    data_out[7:0] = q_m[7:0];
                    disparity <= disparity + $signed({1'b0,ones_q}) - $signed({1'b0,zeros_q});
                end
            end
        end
    end
endmodule
