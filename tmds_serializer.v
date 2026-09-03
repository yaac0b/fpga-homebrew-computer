module tmds_serializer (
    input wire       pixel_clk,
    input wire       serial_clk,
    input wire       rst,

    input wire [9:0] tmds_r,
    input wire [9:0] tmds_g,
    input wire [9:0] tmds_b,

    output wire      serial_r,
    output wire      serial_g,
    output wire      serial_b
);

    OSER10 ser_r (
        .Q(serial_r),

        .D0(tmds_r[0]),
        .D1(tmds_r[1]),
        .D2(tmds_r[2]),
        .D3(tmds_r[3]),
        .D4(tmds_r[4]),
        .D5(tmds_r[5]),
        .D6(tmds_r[6]),
        .D7(tmds_r[7]),
        .D8(tmds_r[8]),
        .D9(tmds_r[9]),

        .PCLK(pixel_clk),
        .FCLK(serial_clk),
        .RESET(rst)
    );

    OSER10 ser_g (
        .Q(serial_g),

        .D0(tmds_g[0]),
        .D1(tmds_g[1]),
        .D2(tmds_g[2]),
        .D3(tmds_g[3]),
        .D4(tmds_g[4]),
        .D5(tmds_g[5]),
        .D6(tmds_g[6]),
        .D7(tmds_g[7]),
        .D8(tmds_g[8]),
        .D9(tmds_g[9]),

        .PCLK(pixel_clk),
        .FCLK(serial_clk),
        .RESET(rst)
    );

    OSER10 ser_b (
        .Q(serial_b),

        .D0(tmds_b[0]),
        .D1(tmds_b[1]),
        .D2(tmds_b[2]),
        .D3(tmds_b[3]),
        .D4(tmds_b[4]),
        .D5(tmds_b[5]),
        .D6(tmds_b[6]),
        .D7(tmds_b[7]),
        .D8(tmds_b[8]),
        .D9(tmds_b[9]),

        .PCLK(pixel_clk),
        .FCLK(serial_clk),
        .RESET(rst)
    );

endmodule