`timescale 1ns/1ps
// 160x120 RGB332 framebuffer = 19,200 bytes.
// Implemented with 10 Gowin SDP BSRAM blocks (2048x8 each).
//
// Port A (CLKA = clk_w): renderer writes, CPU clock domain.
// Port B (CLKB = clk_r): HDMI scanout reads, pixel clock domain.
//
// ------------------------------------------------------------
// CHANGE: the two ports now take SEPARATE clocks.
//
// Previously both CLKA and CLKB were tied to pixel_clk, which
// forced gpu_regs and gpu_renderer to live in the pixel_clk
// domain too. That meant gpu_load - a one-clock pulse generated
// in the CPU's clk domain - had to be captured by an unrelated
// 27 MHz clock whose phase came from an uncalibrated CLKDIV.
// It happened to work, but nothing guaranteed it.
//
// An SDP block is a true dual-port RAM with independent port
// clocks, so the write side can simply move to clk. Reading a
// location while it is being written returns either the old or
// the new byte, which for a framebuffer is harmless: worst case
// one pixel shows its previous value for one frame.
// ------------------------------------------------------------
module framebuffer_bram (
    input  wire        clk_w,
    input  wire        clk_r,
    input  wire        cpu_we,
    input  wire [14:0] cpu_addr,
    input  wire [7:0]  cpu_wdata,
    input  wire [14:0] video_addr,
    output wire [7:0]  video_pixel
);
    wire [31:0] q0,q1,q2,q3,q4,q5,q6,q7,q8,q9;
    wire [3:0] wb = cpu_addr[14:11];
    wire [3:0] rb = video_addr[14:11];
    wire [13:0] wa = {cpu_addr[10:0],3'b000};
    wire [13:0] ra = {video_addr[10:0],3'b000};
    wire [31:0] din = {24'h000000,cpu_wdata};

    SDP fb0(.DO(q0),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd0),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb1(.DO(q1),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd1),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb2(.DO(q2),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd2),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb3(.DO(q3),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd3),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb4(.DO(q4),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd4),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb5(.DO(q5),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd5),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb6(.DO(q6),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd6),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb7(.DO(q7),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd7),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb8(.DO(q8),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd8),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));
    SDP fb9(.DO(q9),.CLKA(clk_w),.CEA(1'b1),.RESETA(1'b0),.WREA(cpu_we && wb==4'd9),.CLKB(clk_r),.CEB(1'b1),.RESETB(1'b0),.WREB(1'b0),.OCE(1'b1),.BLKSEL(3'b000),.ADA(wa),.DI(din),.ADB(ra));

    defparam fb0.BIT_WIDTH_0=8; defparam fb0.BIT_WIDTH_1=8; defparam fb0.READ_MODE=1'b0; defparam fb0.RESET_MODE="SYNC";
    defparam fb1.BIT_WIDTH_0=8; defparam fb1.BIT_WIDTH_1=8; defparam fb1.READ_MODE=1'b0; defparam fb1.RESET_MODE="SYNC";
    defparam fb2.BIT_WIDTH_0=8; defparam fb2.BIT_WIDTH_1=8; defparam fb2.READ_MODE=1'b0; defparam fb2.RESET_MODE="SYNC";
    defparam fb3.BIT_WIDTH_0=8; defparam fb3.BIT_WIDTH_1=8; defparam fb3.READ_MODE=1'b0; defparam fb3.RESET_MODE="SYNC";
    defparam fb4.BIT_WIDTH_0=8; defparam fb4.BIT_WIDTH_1=8; defparam fb4.READ_MODE=1'b0; defparam fb4.RESET_MODE="SYNC";
    defparam fb5.BIT_WIDTH_0=8; defparam fb5.BIT_WIDTH_1=8; defparam fb5.READ_MODE=1'b0; defparam fb5.RESET_MODE="SYNC";
    defparam fb6.BIT_WIDTH_0=8; defparam fb6.BIT_WIDTH_1=8; defparam fb6.READ_MODE=1'b0; defparam fb6.RESET_MODE="SYNC";
    defparam fb7.BIT_WIDTH_0=8; defparam fb7.BIT_WIDTH_1=8; defparam fb7.READ_MODE=1'b0; defparam fb7.RESET_MODE="SYNC";
    defparam fb8.BIT_WIDTH_0=8; defparam fb8.BIT_WIDTH_1=8; defparam fb8.READ_MODE=1'b0; defparam fb8.RESET_MODE="SYNC";
    defparam fb9.BIT_WIDTH_0=8; defparam fb9.BIT_WIDTH_1=8; defparam fb9.READ_MODE=1'b0; defparam fb9.RESET_MODE="SYNC";

    wire [7:0] selected = rb==4'd0 ? q0[7:0] : rb==4'd1 ? q1[7:0] : rb==4'd2 ? q2[7:0] : rb==4'd3 ? q3[7:0] :
                          rb==4'd4 ? q4[7:0] : rb==4'd5 ? q5[7:0] : rb==4'd6 ? q6[7:0] : rb==4'd7 ? q7[7:0] :
                          rb==4'd8 ? q8[7:0] : q9[7:0];
    assign video_pixel = (video_addr < 15'd19200) ? selected : 8'h00;
endmodule