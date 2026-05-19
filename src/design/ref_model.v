
module ref_model #(parameter width = 8)(
    input                  baud_op_clk,
    input                  sys_rst,
    input                  xmit_h,
    input      [width-1:0] xmit_data_h,
    output reg [width-1:0] ref_rec_data_h,
    output reg             ref_rec_ready,
    output reg             ref_rec_busy,
    output reg             ref_xmit_done_h
);

    // ----------------------------------------------------------------
    // Internal: model the full UART frame timing
    // TX side: idle → start(16) → data(16×8) → stop(16) → idle
    // RX side: samples at mid-bit (count==7 of each 16-tick bit)
    // ----------------------------------------------------------------

    localparam idle  = 2'd0,
               start = 2'd1,
               data  = 2'd2,
               stop  = 2'd3;

    // TX state
    reg [1:0]             tx_ct, tx_nt;
    reg [3:0]             tx_count;
    reg [$clog2(width):0] tx_index;
    reg [width-1:0]       tx_latched;
    reg                   tx_line;     // models uart_xmit_data_h

    // RX state (mirrors uart_rx, sampling tx_line at mid-bit)
    reg [1:0]             rx_ct, rx_nt;
    reg [3:0]             rx_count;
    reg [$clog2(width):0] rx_index;
    reg [width-1:0]       rx_shift;

    // ----------------------------------------------------------------
    // TX FSM — sequential
    // ----------------------------------------------------------------
    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin
            tx_ct      <= idle;
            tx_count   <= 0;
            tx_index   <= 0;
            tx_latched <= 0;
            tx_line    <= 1;
            ref_xmit_done_h <= 0;
        end
        else begin
            tx_ct <= tx_nt;

            if (xmit_h && tx_ct == idle)
                tx_latched <= xmit_data_h;

            if (tx_ct == idle)         tx_count <= 0;
            else if (tx_nt != tx_ct)   tx_count <= 0;
            else                       tx_count <= tx_count + 1;

            if (tx_ct == idle)         tx_index <= 0;
            else if (tx_ct == data && tx_count == 15 && tx_nt == data)
                                       tx_index <= tx_index + 1;

            if (tx_ct == stop && tx_nt == idle)
                ref_xmit_done_h <= 1;
            else if (tx_ct == idle && xmit_h)
                ref_xmit_done_h <= 0;
        end
    end

    // TX FSM — combinational + tx_line drive
    always @(*) begin
        tx_nt   = tx_ct;
        tx_line = 1;
        case (tx_ct)
            idle:  begin tx_line = 1; tx_nt = xmit_h ? start : idle; end
            start: begin tx_line = 0; tx_nt = (tx_count == 15) ? data : start; end
            data:  begin
                tx_line = tx_latched[tx_index];
                if (tx_count == 15)
                    tx_nt = (tx_index == width-1) ? stop : data;
                else
                    tx_nt = data;
            end
            stop:  begin tx_line = 1; tx_nt = (tx_count == 15) ? idle : stop; end
            default: begin tx_line = 1; tx_nt = idle; end
        endcase
    end

    // ----------------------------------------------------------------
    // RX FSM — sequential (loopback: receives tx_line)
    // ----------------------------------------------------------------
    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin
            rx_ct          <= idle;
            rx_count       <= 0;
            rx_index       <= 0;
            rx_shift       <= 0;
            ref_rec_data_h <= 0;
            ref_rec_ready  <= 1;
            ref_rec_busy   <= 0;
        end
        else begin
            rx_ct <= rx_nt;

            if (rx_ct != rx_nt) rx_count <= 0;
            else                rx_count <= rx_count + 1;

            // Sample at mid-bit
            if (rx_ct == data && rx_count == 7)
                rx_shift <= {tx_line, rx_shift[width-1:1]};

            if (rx_ct == idle)
                rx_index <= 0;
            else if (rx_ct == data && rx_count == 15)
                rx_index <= rx_index + 1;

            // Latch to output at end of stop
            if (rx_ct == stop && rx_nt == idle)
                ref_rec_data_h <= rx_shift;

            // Invalidate on bad stop bit
            if (rx_ct == stop && rx_count == 7 && tx_line != 1'b1)
                ref_rec_data_h <= 0;

            ref_rec_ready <= (rx_nt == idle);
            ref_rec_busy  <= (rx_nt != idle);
        end
    end

    // RX FSM — combinational
    always @(*) begin
        rx_nt = rx_ct;
        case (rx_ct)
            idle:  rx_nt = (tx_line == 1'b0) ? start : idle;
            start: begin
                if (rx_count == 12)
                    rx_nt = (tx_line == 1'b0) ? data : idle;
                else
                    rx_nt = start;
            end
            data: begin
                if (rx_count == 15)
                    rx_nt = (rx_index == width-1) ? stop : data;
                else
                    rx_nt = data;
            end
            stop:  rx_nt = (rx_count == 15) ? idle : stop;
            default: rx_nt = idle;
        endcase
    end

endmodule

