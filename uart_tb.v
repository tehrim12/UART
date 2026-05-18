mescale 1ns / 1ps
module tb_uart;
 
    parameter freq  = 1000000;   // matches always #5 below
    parameter baudr = 115200;
    parameter width = 8;
 
    reg              sys_clk;
    reg              sys_rst;
    reg              xmit_h;
    reg  [width-1:0] xmit_data_h;
 
    wire             uart_clk;
    wire             uart_xmit_data_h;
    wire             xmit_done_h;
    wire [width-1:0] rec_data_h;
    wire             rec_ready;
    wire             rec_busy;
    wire             xmit_active;
 
    uart #(.freq(freq), .baudr(baudr), .width(width)) DUT (
        .sys_clk         (sys_clk),
        .sys_rst         (sys_rst),
        .xmit_h          (xmit_h),
        .xmit_data_h     (xmit_data_h),
        .uart_rec_data_h (uart_xmit_data_h),
        .uart_clk        (uart_clk),
        .uart_xmit_data_h(uart_xmit_data_h),
        .xmit_done_h     (xmit_done_h),
        .rec_data_h      (rec_data_h),
        .rec_ready       (rec_ready),
        .rec_busy        (rec_busy),
        .xmit_active     (xmit_active)
    );
 
    initial sys_clk = 0;
    always  #5 sys_clk = ~sys_clk;
 
    initial begin
        sys_rst     = 0;
        xmit_h      = 0;
        xmit_data_h = 0;
        #100;
        sys_rst = 1;
        #50;
 
        // ---- Transmission 1: 0xA5 ----
        @(posedge uart_clk);
        xmit_data_h = 8'hA5;
        xmit_h      = 1;
        @(posedge uart_clk);
        xmit_h      = 0;
        wait(xmit_done_h);
        @(posedge uart_clk);
        $display("--------------------------------");
        $display("TRANSMITTED DATA = %h", 8'hA5);
        $display("RECEIVED DATA    = %h", rec_data_h);
        $display("--------------------------------");
 
        repeat(20) @(posedge uart_clk);
 
        // ---- Transmission 2: 0x3C ----
        @(posedge uart_clk);
        xmit_data_h = 8'h3C;
        xmit_h      = 1;
        @(posedge uart_clk);
        xmit_h      = 0;
        wait(xmit_done_h);
        @(posedge uart_clk);
        $display("--------------------------------");
        $display("TRANSMITTED DATA = %h", 8'h3C);
        $display("RECEIVED DATA    = %h", rec_data_h);
        $display("--------------------------------");
 
        repeat(20) @(posedge uart_clk);
        $finish;
    end
 
    // Watchdog
    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end
 
    initial begin
        $monitor("TIME=%0t uart_tx=%b busy=%b ready=%b tx_done=%b rec_data=%h",
                  $time, uart_xmit_data_h, rec_busy, rec_ready, xmit_done_h, rec_data_h);
    end
 
endmodule
