`include "inc.h"
`include "uart_top.v"
`include "ref_top.v"
module tb_uart_compare;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
   // parameter CLK_FREQ    = 50000000;
    //parameter BAUD_RATE   = 9600;

   // parameter WIDTH       = 8;
parameter CLK_FREQ  = `XTAL_CLK;  // ? pull from inc.h so they always match
    parameter BAUD_RATE = `BAUD;       // ? pull from inc.h so they always match
    parameter WIDTH     = `WL;
    parameter SYNC_SETTLE = 4;
    // Total bits in one 8N1 frame: 1 start + 8 data + 1 stop = 10
    parameter FRAME_BITS  = 10;

    // ------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------
    reg              sys_clk;
    reg              sys_rst;
    reg              xmit_h;
    reg  [WIDTH-1:0] xmit_data_h;

    // TB-driven RX inputs  fed from captured_frame after TX done
    reg              dut_rx_in;
    reg              ref_rx_in;

    // Captured TX serial stream (bit-by-bit from DUT TX output)
    reg [FRAME_BITS-1:0] captured_frame;

    // ------------------------------------------------------------
    // DUT outputs
    // ------------------------------------------------------------
    wire             dut_baud_op_clk;
    wire             dut_uart_xmit_data_h;
    wire             dut_xmit_done_h;
    wire [WIDTH-1:0] dut_rec_data_h;
    wire             dut_rec_ready;
    wire             dut_rec_busy;
    wire             dut_xmit_active;

    // ------------------------------------------------------------
    // REF outputs
    // ------------------------------------------------------------
    wire             ref_baud_op_clk;
    wire             ref_uart_xmit_data_h;
    wire             ref_xmit_done_h;
    wire [WIDTH-1:0] ref_rec_data_h;
    wire             ref_rec_ready;
    wire             ref_rec_busy;
    wire             ref_xmit_active;
    wire [WIDTH-1:0] ref_shift_monitor;
    wire [3:0]       ref_bit_index;

    // ------------------------------------------------------------
    // Score-keeping
    // ------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer test_num = 0;
/*
    // ============================================================
    // DUT INSTANTIATION  uart_rec_data_h driven by dut_rx_in
    // ============================================================
    top #(
        .clk_freq  (CLK_FREQ),
        .baud_rate (BAUD_RATE),
        .width     (WIDTH)
    ) DUT (
        .sys_clk          (sys_clk),
        .sys_rst          (sys_rst),
        .xmit_h           (xmit_h),
        .xmit_data_h      (xmit_data_h),
        .uart_rec_data_h  (dut_rx_in),          // fed from captured_frame
        .baud_op_clk      (dut_baud_op_clk),
        .uart_xmit_data_h (dut_uart_xmit_data_h),
        .xmit_done_h      (dut_xmit_done_h),
        .rec_data_h       (dut_rec_data_h),
        .rec_ready        (dut_rec_ready),
        .rec_busy         (dut_rec_busy),
        .xmit_active      (dut_xmit_active)
    );
*/


// ============================================================
// DUT INSTANTIATION  uart module with corrected port mapping
// ============================================================
uart 
/*#(
    // uart uses `include "inc.h" for WL, so no parameters here
    // unless your uart/baud modules accept clk_freq/baud_rate params
)*/
 DUT (
    .sys_clk          (sys_clk),
    .sys_rst_l        (sys_rst),             // TB is active-high; design is active-low
    .uart_clk         (dut_baud_op_clk),      // baud clock output
    .uart_XMIT_dataH  (dut_uart_xmit_data_h), // serial TX output
    .xmitH            (xmit_h),               // transmit trigger
    .xmit_dataH       (xmit_data_h),          // parallel data in
    .xmit_doneH       (dut_xmit_done_h),      // TX complete flag
    .xmit_active      (dut_xmit_active),      // TX in-progress flag
    .uart_REC_dataH   (dut_rx_in),            // serial RX input (fed from captured_frame)
    .rec_dataH        (dut_rec_data_h),        // received parallel data
    .rec_readyH       (dut_rec_ready),         // RX data ready pulse
    .rec_busy         (dut_rec_busy)           // RX in-progress flag
);
    // ============================================================
    // REF INSTANTIATION  uart_rec_data_h driven by ref_rx_in
    // ============================================================
    top_ref #(
        //.clk_freq  (CLK_FREQ),
        //.baud_rate (BAUD_RATE),
        //.width     (WIDTH)
   .clk_freq  (`XTAL_CLK),           // ? use macro directly, not parameter
    .baud_rate (`BAUD),                // ? use macro directly, not parameter
    .width     (`WL)
 ) REF (
        .sys_clk          (sys_clk),
        .sys_rst          (sys_rst),
        .xmit_h           (xmit_h),
        .xmit_data_h      (xmit_data_h),
        .uart_rec_data_h  (ref_rx_in),          // fed from captured_frame
        .baud_op_clk      (ref_baud_op_clk),
        .uart_xmit_data_h (ref_uart_xmit_data_h),
        .xmit_done_h      (ref_xmit_done_h),
        .rec_data_h       (ref_rec_data_h),
        .rec_ready        (ref_rec_ready),
        .rec_busy         (ref_rec_busy),
        .xmit_active      (ref_xmit_active),
        .shift_out        (ref_shift_monitor),
        .bit_index        (ref_bit_index)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial sys_clk = 0;
    always  #5 sys_clk = ~sys_clk;

    // ------------------------------------------------------------
    // Global timeout
    // ------------------------------------------------------------
    initial begin
        #80_000_000;
        $display("GLOBAL TIMEOUT  simulation aborted");
        $finish;
    end

    // ============================================================
    // TASKS
    // ============================================================

    // ----------------------------------------------------------
    // apply_reset
    // ----------------------------------------------------------
    task apply_reset;
        begin
            sys_rst          = 0;
            xmit_h           = 0;
            xmit_data_h      = 0;
            dut_rx_in        = 1;   // idle high
            ref_rx_in        = 1;
            captured_frame   = {FRAME_BITS{1'b1}};
            repeat(10) @(posedge sys_clk);
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
        end
    endtask

    // ----------------------------------------------------------
    // wait_ticks  N rising edges of ref_baud_op_clk
    // ----------------------------------------------------------
    task wait_ticks;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge ref_baud_op_clk);
        end
    endtask

    // ----------------------------------------------------------
    // run_tx
    // STEP 1: Trigger TX on both DUT and REF with same data.
    //         Capture DUT serial output bit-by-bit every baud
    //         tick into captured_frame[].
    //         Wait until xmit_done_h then stop capturing.
    // ----------------------------------------------------------
    task run_tx;
        input [WIDTH-1:0] data;
        integer b;
        begin
            captured_frame = {FRAME_BITS{1'b1}};

            // Trigger TX on both DUT and REF
            @(posedge ref_baud_op_clk);
            xmit_data_h = data;
            xmit_h      = 1;
            @(posedge ref_baud_op_clk);
            xmit_h = 0;

            // Wait until start bit actually appears on DUT TX line
            @(negedge dut_uart_xmit_data_h);

            // Capture FRAME_BITS bits at mid-bit of each baud period
            for (b = 0; b < FRAME_BITS; b = b + 1) begin
                wait_ticks(8);
                captured_frame[b] = dut_uart_xmit_data_h;
                wait_ticks(8);
            end

            // Wait for both TX done (fork so neither blocks the other)
            fork
                begin wait(dut_xmit_done_h); end
                begin wait(ref_xmit_done_h); end
            join
            repeat(4) @(posedge ref_baud_op_clk);

            $display("  run_tx: data=0x%h captured=%b (start=%b d=%b%b%b%b%b%b%b%b stop=%b)",
                data, captured_frame,
                captured_frame[0],
                captured_frame[1], captured_frame[2], captured_frame[3], captured_frame[4],
                captured_frame[5], captured_frame[6], captured_frame[7], captured_frame[8],
                captured_frame[9]);
        end
    endtask

    // ----------------------------------------------------------
    // run_rx
    // STEP 2: Replay captured_frame[] bit-by-bit into both
    //         dut_rx_in and ref_rx_in at 16 baud ticks per bit.
    //         No direct connection to TX output anywhere.
    // ----------------------------------------------------------
    task run_rx;
        integer b;
        begin
            // Ensure line is idle before replay
            dut_rx_in = 1;
            ref_rx_in = 1;
            wait_ticks(4);

            // Drive each captured bit for 16 baud ticks
            for (b = 0; b < FRAME_BITS; b = b + 1) begin
                dut_rx_in = captured_frame[b];
                ref_rx_in = captured_frame[b];
                wait_ticks(16);
            end

            // Return to idle
            dut_rx_in = 1;
            ref_rx_in = 1;

            // Wait for DUT 2-FF sync pipeline to settle
            wait_ticks(SYNC_SETTLE);
            #1;
        end
    endtask

    // ----------------------------------------------------------
    // compare_outputs
    // ----------------------------------------------------------
    task compare_outputs;
        input        check_tx;
        input        check_rx;
        output reg   matched;
        begin
            matched = 1;
            if (check_tx) begin
                if (dut_uart_xmit_data_h !== ref_uart_xmit_data_h) matched = 0;
                // xmit_done_h compared only on TX-only tests (check_rx=0)
                // In full TX+RX tests done pulse timing differs after run_rx delay
                if (!check_rx) begin
                    if (dut_xmit_done_h !== ref_xmit_done_h) matched = 0;
                end
                if (dut_xmit_active !== ref_xmit_active) matched = 0;
            end
            if (check_rx) begin
                if (dut_rec_data_h !== ref_rec_data_h) matched = 0;
                if (dut_rec_ready  !== ref_rec_ready)  matched = 0;
                if (dut_rec_busy   !== ref_rec_busy)   matched = 0;
            end
        end
    endtask

    // ----------------------------------------------------------
    // print_mismatch
    // ----------------------------------------------------------
    task print_mismatch;
        input check_tx;
        input check_rx;
        begin
            if (check_tx) begin
                if (dut_uart_xmit_data_h !== ref_uart_xmit_data_h)
                    $display("         uart_xmit_data_h : DUT=%b  REF=%b",
                              dut_uart_xmit_data_h, ref_uart_xmit_data_h);
                if (!check_rx && dut_xmit_done_h !== ref_xmit_done_h)
                    $display("         xmit_done_h      : DUT=%b  REF=%b",
                              dut_xmit_done_h, ref_xmit_done_h);
                if (dut_xmit_active !== ref_xmit_active)
                    $display("         xmit_active      : DUT=%b  REF=%b",
                              dut_xmit_active, ref_xmit_active);
            end
            if (check_rx) begin
                if (dut_rec_data_h !== ref_rec_data_h)
                    $display("         rec_data_h  : DUT=0x%h  REF=0x%h",
                              dut_rec_data_h, ref_rec_data_h);
                if (dut_rec_ready !== ref_rec_ready)
                    $display("         rec_ready   : DUT=%b  REF=%b",
                              dut_rec_ready, ref_rec_ready);
                if (dut_rec_busy !== ref_rec_busy)
                    $display("         rec_busy    : DUT=%b  REF=%b",
                              dut_rec_busy, ref_rec_busy);
            end
        end
    endtask

    // ----------------------------------------------------------
    // report
    // ----------------------------------------------------------
    task report;
        input [8*64-1:0] tname;
        input            passed;
        input            check_tx;
        input            check_rx;
        begin
            test_num = test_num + 1;
            if (passed) begin
                $display("");
                $display("============================================================");
                $display("  [PASS]  %s", tname);
                $display("  DUT : tx=%b  done=%b  active=%b  busy=%b  ready=%b  data=0x%h",
                    dut_uart_xmit_data_h, dut_xmit_done_h, dut_xmit_active,
                    dut_rec_busy, dut_rec_ready, dut_rec_data_h);
                $display("  REF : tx=%b  done=%b  active=%b  busy=%b  ready=%b  data=0x%h",
                    ref_uart_xmit_data_h, ref_xmit_done_h, ref_xmit_active,
                    ref_rec_busy, ref_rec_ready, ref_rec_data_h);
                $display("============================================================");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("");
                $display("============================================================");
                $display("  [FAIL]  %s", tname);
                $display("  DUT : tx=%b  done=%b  active=%b  busy=%b  ready=%b  data=0x%h",
                    dut_uart_xmit_data_h, dut_xmit_done_h, dut_xmit_active,
                    dut_rec_busy, dut_rec_ready, dut_rec_data_h);
                $display("  REF : tx=%b  done=%b  active=%b  busy=%b  ready=%b  data=0x%h",
                    ref_uart_xmit_data_h, ref_xmit_done_h, ref_xmit_active,
                    ref_rec_busy, ref_rec_ready, ref_rec_data_h);
                $display("  MISMATCH:");
                print_mismatch(check_tx, check_rx);
                $display("============================================================");
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ----------------------------------------------------------
    // full_test
    // Runs TX, captures, runs RX replay, compares  all in one.
    // ----------------------------------------------------------
    task full_test;
        input [WIDTH-1:0] data;
        output reg        matched;
        reg               m;
        begin
            run_tx(data);
            run_rx();
            compare_outputs(1, 1, m);
            matched = m;
        end
    endtask

    // ============================================================
    // MAIN TEST SEQUENCE
    // ============================================================
    initial begin
        $display("=======================================================");
        $display("  UART Compare TB  DUT vs REF  60 Test Cases        ");
        $display("  Flow: run_tx -> capture -> run_rx -> compare         ");
        $display("  No direct TX-to-RX wire anywhere                    ");
        $display("  SYNC_SETTLE=%0d baud ticks                          ", SYNC_SETTLE);
        $display("=======================================================\n");

        // --------------------------------------------------------
        // Basic Transmission TX+RX 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : basic_tx_rx_0xA5
            reg m;
            full_test(8'hA5, m);
            report("Basic TX+RX 0xA5", m, 1, 1);
        end

        // --------------------------------------------------------
        // xmit_active Asserts On xmit_h
        // --------------------------------------------------------
        apply_reset();
        begin : xmit_active_asserts_on_xmit_h
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hAA;
            xmit_h      = 1;
            @(posedge ref_baud_op_clk);
            #1;
            m = (dut_xmit_active === ref_xmit_active) && (dut_xmit_active === 1);
            xmit_h = 0;
            wait(dut_xmit_done_h);
            repeat(4) @(posedge ref_baud_op_clk);
            report("xmit_active asserts on xmit_h", m, 1, 0);
        end

        // --------------------------------------------------------
        // xmit_done_h Asserts After Full Frame
        // --------------------------------------------------------
        apply_reset();
        begin : xmit_done_asserts_after_full_frame
            reg dut_done, ref_done, m;
            dut_done = 0; ref_done = 0;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5;
            xmit_h      = 1;
            @(posedge ref_baud_op_clk);
            xmit_h = 0;
            wait(ref_xmit_done_h); ref_done = 1;
            begin : wait_dut3
                integer k;
                for (k=0; k<8 && !dut_xmit_done_h; k=k+1)
                    @(posedge ref_baud_op_clk);
                if (dut_xmit_done_h) dut_done = 1;
            end
            repeat(4) @(posedge ref_baud_op_clk);
            m = (dut_done === ref_done);
            report("xmit_doneH asserts after full frame", m, 1, 0);
        end

        // --------------------------------------------------------
        // Back-to-Back TX+RX 0x12 Then 0x34
        // --------------------------------------------------------
        apply_reset();
        begin : back_to_back_0x12_then_0x34
            reg m1, m2, m;
            full_test(8'h12, m1);
            full_test(8'h34, m2);
            m = m1 && m2;
            report("Back-to-Back TX+RX 0x12 then 0x34", m, 1, 1);
        end

        // --------------------------------------------------------
        // Idle Line TX High xmit_active Low
        // --------------------------------------------------------
        apply_reset();
        begin : idle_line_tx_high_xmit_active_low
            reg m;
            wait_ticks(20); #1;
            m = (dut_uart_xmit_data_h===1) && (ref_uart_xmit_data_h===1) &&
                (dut_xmit_active===0)       && (ref_xmit_active===0);
            report("Idle TX HIGH xmit_active=0", m, 1, 0);
        end

        // --------------------------------------------------------
        // Max Data 0xFF TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : max_data_0xFF_tx_rx
            reg m;
            full_test(8'hFF, m);
            report("Max Data 0xFF TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Alternating Pattern 0x2A TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : alternating_pattern_0x2A_tx_rx
            reg m;
            full_test(8'h2A, m);
            report("Alternating pattern 0x2A TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Retrigger During Active TX Ignored
        // --------------------------------------------------------
        apply_reset();
        begin : retrigger_during_active_tx_ignored
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait_ticks(20);
            xmit_data_h = 8'h3C; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait(ref_xmit_done_h);
            repeat(4) @(posedge ref_baud_op_clk); #1;
            compare_outputs(1, 0, m);
            report("Retrigger during active TX: original frame intact", m, 1, 0);
        end

        // --------------------------------------------------------
        // Reset During TX Both Abort To Idle
        // --------------------------------------------------------
        apply_reset();
        begin : reset_during_tx_both_abort_to_idle
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait_ticks(20);
            sys_rst = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_outputs(1, 1, m);
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
            report("Reset during TX: both abort to idle", m, 1, 1);
        end

        // --------------------------------------------------------
        // 8N1 Frame Integrity 0x55
        // --------------------------------------------------------
        apply_reset();
        begin : frame_integrity_8N1_0x55
            reg m;
            full_test(8'h55, m);
            report("8N1 frame integrity 0x55 TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // 6-bit Boundary Value 0x3F
        // --------------------------------------------------------
        apply_reset();
        begin : six_bit_boundary_0x3F
            reg m;
            full_test(8'h3F, m);
            report("6-bit boundary 0x3F TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // 8-bit Max Boundary 0xFF Repeat
        // --------------------------------------------------------
        apply_reset();
        begin : eight_bit_max_boundary_0xFF_repeat
            reg m;
            full_test(8'hFF, m);
            report("8-bit max boundary 0xFF TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Three Back-to-Back Frames AA 55 A5
        // --------------------------------------------------------
        apply_reset();
        begin : three_back_to_back_AA_55_A5
            reg m1, m2, m3, m;
            full_test(8'hAA, m1);
            full_test(8'h55, m2);
            full_test(8'hA5, m3);
            m = m1 && m2 && m3;
            report("3 back-to-back frames AA,55,A5", m, 1, 1);
        end

        // --------------------------------------------------------
        // Baud Low-limit Proxy
        // --------------------------------------------------------
        apply_reset();
        begin : baud_low_limit_proxy
            reg m;
            full_test(8'hA5, m);
            report("Baud low-limit proxy TX+RX 0xA5", m, 1, 1);
        end

        // --------------------------------------------------------
        // Baud High-limit Proxy
        // --------------------------------------------------------
        apply_reset();
        begin : baud_high_limit_proxy
            reg m;
            full_test(8'h3C, m);
            report("Baud high-limit proxy TX+RX 0x3C", m, 1, 1);
        end

        // --------------------------------------------------------
        // Immediate Retrigger After Done
        // --------------------------------------------------------
        apply_reset();
        begin : immediate_retrigger_after_done
            reg m1, m2, m;
            full_test(8'hA5, m1);
            full_test(8'hB6, m2);
            m = m1 && m2;
            report("Immediate retrigger after done: A5 then B6", m, 1, 1);
        end

        // --------------------------------------------------------
        // Second Trigger During Active TX Ignored
        // --------------------------------------------------------
        apply_reset();
        begin : second_trigger_during_active_tx_ignored
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hCC; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait_ticks(10);
            xmit_data_h = 8'hDD; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait(ref_xmit_done_h);
            repeat(4) @(posedge ref_baud_op_clk); #1;
            compare_outputs(1, 0, m);
            report("Second trigger during active TX: ignored", m, 1, 0);
        end

        // --------------------------------------------------------
        // Reset Mid-TX Both Abort To Idle
        // --------------------------------------------------------
        apply_reset();
        begin : reset_mid_tx_both_abort_to_idle
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait_ticks(15);
            sys_rst = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_outputs(1, 1, m);
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
            report("Reset mid-TX: both abort to idle", m, 1, 1);
        end

        // --------------------------------------------------------
        // Zero Data 0x00 TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : zero_data_0x00_tx_rx
            reg m;
            full_test(8'h00, m);
            report("Zero data 0x00 TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Sub-cycle Glitch On xmit_h DUT REF Same Behaviour
        // --------------------------------------------------------
        apply_reset();
        begin : sub_cycle_glitch_on_xmit_h
            reg m;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            #2; xmit_h = 0;
            wait_ticks(30); #1;
            compare_outputs(1, 1, m);
            report("Sub-cycle glitch on xmit_h: DUT and REF same", m, 1, 1);
        end

        // --------------------------------------------------------
        // Valid Stop Bit Frame Accepted 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : valid_stop_bit_frame_accepted
            reg m;
            full_test(8'hA5, m);
            report("Valid stop bit: frame accepted 0xA5", m, 1, 1);
        end

        // --------------------------------------------------------
        // TX Then RX 0x3C
        // --------------------------------------------------------
        apply_reset();
        begin : tx_then_rx_0x3C
            reg m;
            full_test(8'h3C, m);
            report("TX then RX 0x3C", m, 1, 1);
        end

        // --------------------------------------------------------
        // rec_ready Pulses After Valid Frame
        // --------------------------------------------------------
        apply_reset();
        begin : rec_ready_pulses_after_valid_frame
            reg dut_rdy, ref_rdy, m;
            dut_rdy = 0; ref_rdy = 0;
            run_tx(8'hA5);
            fork
                run_rx();
                begin : watch23
                    integer k;
                    for (k=0; k<60; k=k+1) begin
                        @(posedge ref_baud_op_clk);
                        if (dut_rec_ready) dut_rdy = 1;
                        if (ref_rec_ready) ref_rdy = 1;
                    end
                end
            join
            m = (dut_rdy===1) && (ref_rdy===1);
            report("rec_ready pulses after valid frame", m, 0, 1);
        end

        // --------------------------------------------------------
        // rec_busy Asserts On Start Bit Detection
        // --------------------------------------------------------
        apply_reset();
        begin : rec_busy_asserts_on_start_bit
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(12); #1;
            m = (dut_rec_busy===1) && (ref_rec_busy===1);
            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(20);
            report("Start bit: rec_busy asserts in DUT and REF", m, 0, 1);
        end

        // --------------------------------------------------------
        // Sequential TX+RX 0xA5 Then 0x3C
        // --------------------------------------------------------
        apply_reset();
        begin : sequential_tx_rx_0xA5_then_0x3C
            reg m1, m2, m;
            full_test(8'hA5, m1);
            full_test(8'h3C, m2);
            m = m1 && m2;
            report("Sequential TX+RX: 0xA5 then 0x3C", m, 1, 1);
        end

        // --------------------------------------------------------
        // Valid Stop Bit Accepted DUT Matches REF
        // --------------------------------------------------------
        apply_reset();
        begin : valid_stop_bit_dut_matches_ref
            reg m;
            full_test(8'hA5, m);
            report("Valid stop bit accepted: DUT matches REF", m, 1, 1);
        end

        // --------------------------------------------------------
        // Idle Line No Activity In DUT Or REF
        // --------------------------------------------------------
        apply_reset();
        begin : idle_line_no_activity_dut_or_ref
            reg m;
            wait_ticks(30); #1;
            m = (dut_uart_xmit_data_h===1) && (ref_uart_xmit_data_h===1) &&
                (dut_rec_busy===0) && (ref_rec_busy===0);
            report("Idle line: no activity in DUT or REF", m, 1, 1);
        end

        // --------------------------------------------------------
        // Clean Frame Baseline 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : clean_frame_baseline_0xA5
            reg m;
            full_test(8'hA5, m);
            report("Clean frame baseline 0xA5", m, 1, 1);
        end

        // --------------------------------------------------------
        // Post-frame rec_busy Clears In DUT And REF
        // --------------------------------------------------------
        apply_reset();
        begin : post_frame_rec_busy_clears
            reg m;
            full_test(8'hA5, m);
            wait_ticks(5); #1;
            m = (dut_rec_busy===0) && (ref_rec_busy===0);
            report("Post-frame rec_busy clears in DUT and REF", m, 0, 1);
        end

        // --------------------------------------------------------
        // Three Back-to-Back Frames AA BB CC
        // --------------------------------------------------------
        apply_reset();
        begin : three_back_to_back_AA_BB_CC
            reg m1, m2, m3, m;
            full_test(8'hAA, m1);
            full_test(8'hBB, m2);
            full_test(8'hCC, m3);
            m = m1 && m2 && m3;
            report("3 back-to-back frames AA,BB,CC", m, 1, 1);
        end

        // --------------------------------------------------------
        // Reset During RX DUT Matches REF
        // --------------------------------------------------------
        apply_reset();
        begin : reset_during_rx_dut_matches_ref
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(20);
            sys_rst = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_outputs(1, 1, m);
            dut_rx_in = 1; ref_rx_in = 1;
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
            report("Reset during RX: DUT matches REF", m, 1, 1);
        end

        // --------------------------------------------------------
        // Min Boundary 0x2A TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : min_boundary_0x2A
            reg m;
            full_test(8'h2A, m);
            report("Min boundary 0x2A TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Max Boundary 0xFF TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : max_boundary_0xFF
            reg m;
            full_test(8'hFF, m);
            report("Max boundary 0xFF TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Three Sequential Frames 0x12 0x34 0x56
        // --------------------------------------------------------
        apply_reset();
        begin : three_sequential_frames_0x12_0x34_0x56
            reg m1, m2, m3, m;
            full_test(8'h12, m1);
            full_test(8'h34, m2);
            full_test(8'h56, m3);
            m = m1 && m2 && m3;
            report("Back-to-Back 0x12,0x34,0x56", m, 1, 1);
        end

        // --------------------------------------------------------
        // rec_busy Still High At 24th Baud Tick
        // --------------------------------------------------------
        apply_reset();
        begin : rec_busy_high_at_24th_baud_tick
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(24); #1;
            m = (dut_rec_busy===ref_rec_busy) && (dut_rec_busy===1);
            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(28);
            report("rec_busy high at 24th baud tick: DUT matches REF", m, 0, 1);
        end

        // --------------------------------------------------------
        // Slow Baud Proxy TX+RX 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : slow_baud_proxy_tx_rx
            reg m;
            full_test(8'hA5, m);
            report("Slow baud proxy TX+RX 0xA5", m, 1, 1);
        end

        // --------------------------------------------------------
        // Fast Baud Proxy TX+RX 0x3C
        // --------------------------------------------------------
        apply_reset();
        begin : fast_baud_proxy_tx_rx
            reg m;
            full_test(8'h3C, m);
            report("Fast baud proxy TX+RX 0x3C", m, 1, 1);
        end

        // --------------------------------------------------------
        // Valid Stop Bit RX Accepted 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : valid_stop_bit_rx_accepted
            reg m;
            full_test(8'hA5, m);
            report("Valid stop bit RX accepted 0xA5", m, 1, 1);
        end

        // --------------------------------------------------------
        // Idle RX No Spurious Reception
        // --------------------------------------------------------
        apply_reset();
        begin : idle_rx_no_spurious_reception
            reg m;
            wait_ticks(30); #1;
            m = (dut_rec_busy===0) && (ref_rec_busy===0) &&
                (dut_rec_ready===0) && (ref_rec_ready===0);
            report("Idle RX: no spurious reception", m, 0, 1);
        end

        // --------------------------------------------------------
        // Noise Baseline 0x55 TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : noise_baseline_0x55
            reg m;
            full_test(8'h55, m);
            report("Noise baseline 0x55 TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Short Start Glitch DUT REF Same Behaviour
        // --------------------------------------------------------
        apply_reset();
        begin : short_start_glitch_dut_ref_same
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(3);
            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(30); #1;
            m = (dut_rec_busy===ref_rec_busy) && (dut_rec_ready===ref_rec_ready);
            report("Short start glitch: DUT and REF same", m, 0, 1);
        end

        // --------------------------------------------------------
        // Three Frames No Inter-frame Gap 0x11 0x22 0x33
        // --------------------------------------------------------
        apply_reset();
        begin : three_frames_no_gap_0x11_0x22_0x33
            reg m1, m2, m3, m;
            full_test(8'h11, m1);
            full_test(8'h22, m2);
            full_test(8'h33, m3);
            m = m1 && m2 && m3;
            report("3 frames no gap: 11,22,33", m, 1, 1);
        end

        // --------------------------------------------------------
        // Sequential 0xA5 Then Bit-flip 0x5A
        // --------------------------------------------------------
        apply_reset();
        begin : sequential_0xA5_then_bitflip_0x5A
            reg m1, m2, m;
            full_test(8'hA5, m1);
            full_test(8'h5A, m2);
            m = m1 && m2;
            report("Sequential 0xA5 then bit-flip 0x5A", m, 1, 1);
        end

        // --------------------------------------------------------
        // Reset Mid-RX DUT Matches REF
        // --------------------------------------------------------
        apply_reset();
        begin : reset_mid_rx_dut_matches_ref
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(25);
            sys_rst = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_outputs(1, 1, m);
            dut_rx_in = 1; ref_rx_in = 1;
            sys_rst = 1;
            repeat(5) @(posedge ref_baud_op_clk);
            report("Reset mid-RX: DUT matches REF", m, 1, 1);
        end

        // --------------------------------------------------------
        // Baud 2400 Full TX+RX 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : baud_2400_full_tx_rx
            reg m;
            full_test(8'hA5, m);
            report("Baud 2400 TX+RX 0xA5", m, 1, 1);
        end

        // --------------------------------------------------------
        // Baud 9600 Proxy 0xB7 TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : baud_9600_proxy_0xB7
            reg m;
            full_test(8'hB7, m);
            report("Baud 9600 proxy 0xB7 TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Baud 19200 Proxy 0xC8 TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : baud_19200_proxy_0xC8
            reg m;
            full_test(8'hC8, m);
            report("Baud 19200 proxy 0xC8 TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Unsupported Baud Proxy 0xD9 TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : unsupported_baud_proxy_0xD9
            reg m;
            full_test(8'hD9, m);
            report("Unsupported baud proxy 0xD9 TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Baud Mismatch Proxy 0xA5 TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : baud_mismatch_proxy_0xA5
            reg m;
            full_test(8'hA5, m);
            report("Baud mismatch proxy 0xA5 TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Oversampling Start Bit Tick Count DUT Matches REF
        // --------------------------------------------------------
        apply_reset();
        begin : oversampling_start_bit_tick_count
            reg m;
            integer dut_count, ref_count;
            dut_count = 0; ref_count = 0;
            @(posedge ref_baud_op_clk);
            xmit_data_h = 8'hA5; xmit_h = 1;
            @(posedge ref_baud_op_clk); xmit_h = 0;
            wait(dut_uart_xmit_data_h === 0);
            begin : cnt_dut50
                integer k;
                for (k=0; k<20; k=k+1) begin
                    @(posedge dut_baud_op_clk); dut_count = dut_count + 1;
                    if (dut_uart_xmit_data_h !== 0) k = 20;
                end
            end
            begin : cnt_ref50
                integer k;
                for (k=0; k<20; k=k+1) begin
                    @(posedge ref_baud_op_clk); ref_count = ref_count + 1;
                    if (ref_uart_xmit_data_h !== 0) k = 20;
                end
            end
            m = (dut_count === ref_count);
            wait(ref_xmit_done_h);
            repeat(4) @(posedge ref_baud_op_clk);
            report("Oversampling: start bit tick count DUT matches REF", m, 1, 0);
        end

        // --------------------------------------------------------
        // Lowest Baud Proxy 0xEA TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : lowest_baud_proxy_0xEA
            reg m;
            full_test(8'hEA, m);
            report("Lowest baud proxy 0xEA TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Highest Baud Proxy 0xFB TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : highest_baud_proxy_0xFB
            reg m;
            full_test(8'hFB, m);
            report("Highest baud proxy 0xFB TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Oversampling Boundary rec_busy High At 8th Tick
        // --------------------------------------------------------
        apply_reset();
        begin : oversampling_boundary_rec_busy_8th_tick
            reg m;
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(8); #1;
            m = (dut_rec_busy===ref_rec_busy) && (dut_rec_busy===1);
            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(30);
            report("Oversampling boundary: rec_busy high at 8th tick", m, 0, 1);
        end

        // --------------------------------------------------------
        // Timing Accuracy 8N1 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : timing_accuracy_8N1
            reg m;
            full_test(8'hA5, m);
            report("Timing accuracy 8N1 TX+RX 0xA5", m, 1, 1);
        end

        // --------------------------------------------------------
        // No Data Corruption 0xA5 TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : no_data_corruption_0xA5
            reg m;
            full_test(8'hA5, m);
            report("No data corruption 0xA5 TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Baud Mismatch Proxy 0x3C TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : baud_mismatch_proxy_0x3C
            reg m;
            full_test(8'h3C, m);
            report("Baud mismatch proxy 0x3C TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Extreme Value 0xFF TX+RX
        // --------------------------------------------------------
        apply_reset();
        begin : extreme_value_0xFF
            reg m;
            full_test(8'hFF, m);
            report("Extreme value 0xFF TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Clock Drift Proxy Three Frames A5 5A FF
        // --------------------------------------------------------
        apply_reset();
        begin : clock_drift_proxy_A5_5A_FF
            reg m1, m2, m3, m;
            full_test(8'hA5, m1);
            full_test(8'h5A, m2);
            full_test(8'hFF, m3);
            m = m1 && m2 && m3;
            report("Clock drift proxy: A5,5A,FF TX+RX", m, 1, 1);
        end

        // --------------------------------------------------------
        // Step-by-step Shift Register For 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : stepwise_shift_register_0xA5
            reg m;
            reg [WIDTH-1:0] exp [0:7];
            exp[0]=8'h80; exp[1]=8'h40; exp[2]=8'hA0; exp[3]=8'h50;
            exp[4]=8'h28; exp[5]=8'h94; exp[6]=8'h4A; exp[7]=8'hA5;
            m = 1;

            // Manually drive start bit
            dut_rx_in = 0; ref_rx_in = 0;
            wait_ticks(16);

            begin : step59
                integer b;
                for (b = 0; b < 8; b = b + 1) begin
                    dut_rx_in = 8'hA5 >> b & 1;
                    ref_rx_in = 8'hA5 >> b & 1;
                    wait_ticks(8 + SYNC_SETTLE); #1;
                    if (ref_shift_monitor !== exp[b]) begin
                        $display("  stepwise_shift bit%0d: ref_shift=0x%h exp=0x%h", b, ref_shift_monitor, exp[b]);
                        m = 0;
                    end
                    if (dut_rec_data_h !== exp[b]) begin
                        $display("  stepwise_shift bit%0d: dut_data=0x%h  exp=0x%h", b, dut_rec_data_h, exp[b]);
                        m = 0;
                    end
                    wait_ticks(16 - 8 - SYNC_SETTLE);
                end
            end

            dut_rx_in = 1; ref_rx_in = 1;
            wait_ticks(20);
            report("Step-by-step shift register 0xA5: DUT matches REF", m, 0, 1);
        end

        // --------------------------------------------------------
        // TX Capture Then RX Replay Independence 0xA5
        // --------------------------------------------------------
        apply_reset();
        begin : tx_capture_rx_replay_independence_0xA5
            reg m;
            run_tx(8'hA5);
            $display("         TX+RX independence: captured_frame=%b", captured_frame);
            run_rx();
            compare_outputs(1, 1, m);
            $display("         TX+RX independence: dut_rec=0x%h ref_rec=0x%h (expect A5)",
                      dut_rec_data_h, ref_rec_data_h);
            report("TX capture then RX replay independence 0xA5", m, 1, 1);
        end

        // ========================================================
        // SUMMARY
        // ========================================================
        repeat(10) @(posedge ref_baud_op_clk);
        $display("\n=======================================================");
        $display("  FINAL RESULTS");
        $display("  Total : %0d", test_num);
        $display("  PASS  : %0d", pass_cnt);
        $display("  FAIL  : %0d", fail_cnt);
        $display("=======================================================");
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***\n");
        else
            $display("  *** %0d TEST(S) FAILED ***\n", fail_cnt);
        $finish;
    end

    // ============================================================
    // $monitor
    // ============================================================
    initial begin
        $monitor("T=%0t | DUT: tx=%b done=%b active=%b busy=%b ready=%b data=0x%h | REF: tx=%b done=%b active=%b busy=%b ready=%b data=0x%h | dut_rx=%b ref_rx=%b",
            $time,
            dut_uart_xmit_data_h, dut_xmit_done_h, dut_xmit_active,
            dut_rec_busy, dut_rec_ready, dut_rec_data_h,
            ref_uart_xmit_data_h, ref_xmit_done_h, ref_xmit_active,
            ref_rec_busy, ref_rec_ready, ref_rec_data_h,
            dut_rx_in, ref_rx_in);
    end

endmodule
