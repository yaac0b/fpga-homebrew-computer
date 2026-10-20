// ============================================================
// gpu_renderer.v
//
// Tang Nano 20K GPU Renderer
//
// Framebuffer:
//     160 x 120
//     RGB332
//     19,200 pixels
//
// Address:
//     0 ... 19199
//     15 bits
//
// Commands:
//     1 = DRAW_PIXEL
//     2 = CLEAR
//     3 = FILL_RECT
//
// ============================================================

module gpu_renderer (

    input  wire        clk,
    input  wire        rst,

    // --------------------------------------------------------
    // GPU CONTROL
    // --------------------------------------------------------

    input  wire        gpu_enable,

    // --------------------------------------------------------
    // COMMAND INTERFACE
    // --------------------------------------------------------

    input  wire [7:0]  command,
    input  wire        command_valid,

    // --------------------------------------------------------
    // DRAW COORDINATES
    // --------------------------------------------------------

    input  wire [7:0]  draw_x,
    input  wire [7:0]  draw_y,

    input  wire [7:0]  draw_x2,
    input  wire [7:0]  draw_y2,

    // --------------------------------------------------------
    // DRAW COLOR
    // --------------------------------------------------------

    input  wire [7:0]  draw_color,

    // --------------------------------------------------------
    // SIZE
    // --------------------------------------------------------

    input  wire [15:0] draw_size,

    // --------------------------------------------------------
    // PARAMETERS
    // --------------------------------------------------------

    input  wire [15:0] param0,
    input  wire [15:0] param1,

    // --------------------------------------------------------
    // FRAMEBUFFER WRITE INTERFACE
    // --------------------------------------------------------

    output reg         fb_we,
    output reg  [14:0] fb_addr,
    output reg  [7:0]  fb_wdata,

    // --------------------------------------------------------
    // BUSY
    // --------------------------------------------------------

    output reg         busy

);


    // ========================================================
    // FRAMEBUFFER CONSTANTS
    // ========================================================

    localparam [7:0] FB_WIDTH  = 8'd160;
    localparam [7:0] FB_HEIGHT = 8'd120;

    localparam [14:0] FB_LAST_ADDR = 15'd19199;


    // ========================================================
    // COMMAND CONSTANTS
    // ========================================================

    localparam [7:0] CMD_DRAW_PIXEL = 8'd1;
    localparam [7:0] CMD_CLEAR      = 8'd2;
    localparam [7:0] CMD_FILL_RECT  = 8'd3;


    // ========================================================
    // STATE
    // ========================================================

    localparam [2:0] STATE_IDLE  = 3'd0;
    localparam [2:0] STATE_CLEAR = 3'd1;
    localparam [2:0] STATE_RECT  = 3'd2;

    reg [2:0] state;


    // ========================================================
    // CLEAR ADDRESS
    // ========================================================

    reg [14:0] clear_addr;


    // ========================================================
    // RECTANGLE STATE
    // ========================================================

    // Current drawing position
    reg [7:0] rect_x;
    reg [7:0] rect_y;

    // Ending position
    reg [7:0] rect_x2;
    reg [7:0] rect_y2;

    // Original starting position
    //
    // This is important because rect_x changes while drawing.
    // When a new row starts, we must return to the original X.
    reg [7:0] rect_start_x;
    reg [7:0] rect_start_y;

    // Rectangle color
    reg [7:0] rect_color;


    // ========================================================
    // ADDRESS CALCULATION
    //
    // address = y * 160 + x
    //
    // Maximum:
    //
    // 119 * 160 + 159 = 19199
    //
    // Therefore 15 bits are sufficient.
    // ========================================================

    reg [15:0] calculated_addr;


    // ========================================================
    // MAIN RENDERER
    // ========================================================

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            fb_we       <= 1'b0;
            fb_addr     <= 15'd0;
            fb_wdata    <= 8'h00;

            busy        <= 1'b0;

            state       <= STATE_IDLE;

            clear_addr  <= 15'd0;

            rect_x      <= 8'd0;
            rect_y      <= 8'd0;

            rect_x2     <= 8'd0;
            rect_y2     <= 8'd0;

            rect_start_x <= 8'd0;
            rect_start_y <= 8'd0;

            rect_color  <= 8'h00;

            calculated_addr <= 16'd0;

        end

        else begin

            // ------------------------------------------------
            // Default: no framebuffer write
            // ------------------------------------------------

            fb_we <= 1'b0;


            // =================================================
            // IDLE
            // =================================================

            if (state == STATE_IDLE) begin

                busy <= 1'b0;


                // ------------------------------------------------
                // New command
                // ------------------------------------------------

                if (command_valid && gpu_enable) begin


                    // ============================================
                    // DRAW PIXEL
                    // ============================================

                    if (command == CMD_DRAW_PIXEL) begin

                        // Only draw inside framebuffer

                        if ((draw_x < FB_WIDTH) &&
                            (draw_y < FB_HEIGHT)) begin

                            calculated_addr =
                                (16'd160 * {8'd0, draw_y}) +
                                {8'd0, draw_x};

                            fb_addr  <= calculated_addr[14:0];
                            fb_wdata <= draw_color;
                            fb_we    <= 1'b1;

                        end

                    end


                    // ============================================
                    // CLEAR SCREEN
                    // ============================================

                    else if (command == CMD_CLEAR) begin

                        busy       <= 1'b1;

                        state      <= STATE_CLEAR;

                        clear_addr <= 15'd0;

                        fb_addr    <= 15'd0;
                        fb_wdata   <= 8'h00;
                        fb_we      <= 1'b1;

                    end


                    // ============================================
                    // FILL RECTANGLE
                    // ============================================

                    else if (command == CMD_FILL_RECT) begin

                        // ------------------------------------------------
                        // Clamp starting X
                        // ------------------------------------------------

                        if (draw_x < FB_WIDTH) begin
                            rect_start_x <= draw_x;
                            rect_x       <= draw_x;
                        end
                        else begin
                            rect_start_x <= 8'd159;
                            rect_x       <= 8'd159;
                        end


                        // ------------------------------------------------
                        // Clamp starting Y
                        // ------------------------------------------------

                        if (draw_y < FB_HEIGHT) begin
                            rect_start_y <= draw_y;
                            rect_y       <= draw_y;
                        end
                        else begin
                            rect_start_y <= 8'd119;
                            rect_y       <= 8'd119;
                        end


                        // ------------------------------------------------
                        // Clamp ending X
                        // ------------------------------------------------

                        if (draw_x2 < FB_WIDTH)
                            rect_x2 <= draw_x2;
                        else
                            rect_x2 <= 8'd159;


                        // ------------------------------------------------
                        // Clamp ending Y
                        // ------------------------------------------------

                        if (draw_y2 < FB_HEIGHT)
                            rect_y2 <= draw_y2;
                        else
                            rect_y2 <= 8'd119;


                        // ------------------------------------------------
                        // Save color
                        // ------------------------------------------------

                        rect_color <= draw_color;


                        // ------------------------------------------------
                        // FIRST PIXEL
                        //
                        // IMPORTANT:
                        //
                        // Use the clamped starting coordinates.
                        // ------------------------------------------------

                        if ((draw_x < FB_WIDTH) &&
                            (draw_y < FB_HEIGHT)) begin

                            calculated_addr =
                                (16'd160 * {8'd0, draw_y}) +
                                {8'd0, draw_x};

                            fb_addr  <= calculated_addr[14:0];
                            fb_wdata <= draw_color;
                            fb_we    <= 1'b1;

                            busy  <= 1'b1;
                            state <= STATE_RECT;

                        end

                        else begin

                            // Completely outside framebuffer

                            fb_we <= 1'b0;

                            busy  <= 1'b0;
                            state <= STATE_IDLE;

                        end

                    end

                end

            end


            // =================================================
            // CLEAR FRAMEBUFFER
            // =================================================

            else if (state == STATE_CLEAR) begin

                busy <= 1'b1;


                if (clear_addr == FB_LAST_ADDR) begin

                    // Last pixel has already been written

                    fb_we <= 1'b0;

                    busy  <= 1'b0;

                    state <= STATE_IDLE;

                end

                else begin

                    clear_addr <= clear_addr + 15'd1;

                    fb_addr <= clear_addr + 15'd1;

                    fb_wdata <= 8'h00;

                    fb_we <= 1'b1;

                end

            end


            // =================================================
            // FILL RECTANGLE
            // =================================================

            else if (state == STATE_RECT) begin

                busy <= 1'b1;


                // ------------------------------------------------
                // Continue across X
                // ------------------------------------------------

                if (rect_x < rect_x2) begin

                    rect_x <= rect_x + 8'd1;


                    calculated_addr =
                        (16'd160 * {8'd0, rect_y}) +
                        {8'd0, rect_x + 8'd1};


                    fb_addr  <= calculated_addr[14:0];
                    fb_wdata <= rect_color;
                    fb_we    <= 1'b1;

                end


                // ------------------------------------------------
                // End of current row
                // ------------------------------------------------

                else begin

                    // ------------------------------------------------
                    // More rows remaining
                    // ------------------------------------------------

                    if (rect_y < rect_y2) begin

                        // Move down one row

                        rect_y <= rect_y + 8'd1;

                        // IMPORTANT:
                        //
                        // Restart X at the ORIGINAL X coordinate.
                        //
                        // Previously this was:
                        //
                        //     rect_x <= rect_x;
                        //
                        // which caused the next row to start from
                        // the previous row's ending position.

                        rect_x <= rect_start_x;


                        // First pixel of the new row

                        calculated_addr =
                            (16'd160 * {8'd0, rect_y + 8'd1}) +
                            {8'd0, rect_start_x};


                        fb_addr  <= calculated_addr[14:0];
                        fb_wdata <= rect_color;
                        fb_we    <= 1'b1;

                    end


                    // ------------------------------------------------
                    // Rectangle finished
                    // ------------------------------------------------

                    else begin

                        fb_we <= 1'b0;

                        busy  <= 1'b0;

                        state <= STATE_IDLE;

                    end

                end

            end


            // =================================================
            // SAFETY
            // =================================================

            else begin

                state <= STATE_IDLE;

                busy  <= 1'b0;

                fb_we <= 1'b0;

            end

        end

    end

endmodule