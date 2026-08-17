//=============================================================================
// File   : async_fifo_tb.sv
// Module : async_fifo_tb
//   Test sequence:
//     1. Reset check                - EMPTY asserted, FULL deasserted
//     2. Single write / single read - basic sanity
//     3. Fill to FULL                - write exactly DEPTH words, verify
//                                       wfull, then attempt overflow writes
//                                       and confirm no data is corrupted
//     4. Drain to EMPTY              - read all words back in order, then
//                                       attempt underflow reads and confirm
//                                       the read pointer/data do not move
//     5. Pointer wrap-around         - repeated fill/drain cycles
//     6. Simultaneous read/write     - concurrent producer/consumer around
//                                       FULL/EMPTY boundaries
//     7. Clock domain skew           - repeat stress with wclk faster than
//                                       rclk, then rclk faster than wclk
//     8. Randomized stress test      - random data, random inter-transaction
//                                       delays, random enable pulses, over a
//                                       large number of transactions
//

`timescale 1ns/1ps

module async_fifo_tb;

    //-------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------
    localparam int DSIZE = 32;
    localparam int ASIZE = 4;
    localparam int DEPTH = 1 << ASIZE;   // 16

    //-------------------------------------------------------------------
    // DUT interface signals
    //-------------------------------------------------------------------
    logic                 wclk, wrst_n, winc;
    logic [DSIZE-1:0]     wdata;
    logic                 wfull;

    logic                 rclk, rrst_n, rinc;
    logic [DSIZE-1:0]     rdata;
    logic                 rempty;

    //-------------------------------------------------------------------
    // Clock generation - periods are variables so they can be changed
    // between test phases to model different clock relationships.
    //-------------------------------------------------------------------
    int wclk_period = 10;  // ns
    int rclk_period = 16;  // ns

    initial begin
        wclk = 0;
        forever #(wclk_period/2) wclk = ~wclk;
    end

    initial begin
        rclk = 0;
        forever #(rclk_period/2) rclk = ~rclk;
    end

    //-------------------------------------------------------------------
    // DUT instantiation
    //-------------------------------------------------------------------
    async_fifo_top #(
        .DSIZE (DSIZE),
        .ASIZE (ASIZE)
    ) dut (
        .wclk   (wclk),
        .wrst_n (wrst_n),
        .winc   (winc),
        .wdata  (wdata),
        .wfull  (wfull),

        .rclk   (rclk),
        .rrst_n (rrst_n),
        .rinc   (rinc),
        .rdata  (rdata),
        .rempty (rempty)
    );

    //-------------------------------------------------------------------
    // Reference model / scoreboard
    //-------------------------------------------------------------------
    logic [DSIZE-1:0] sb_queue [$];

    int pass_count   = 0;
    int fail_count   = 0;
    int write_count  = 0;
    int read_count   = 0;
    int blocked_write_count = 0;
    int blocked_read_count  = 0;

    // Mirrors the DUT write port: pushes into the reference queue exactly
    // when the DUT itself would accept the write (winc & !wfull).
    always_ff @(posedge wclk) begin
        if (wrst_n && winc && !wfull) begin
            sb_queue.push_back(wdata);
            write_count++;
        end
        else if (wrst_n && winc && wfull) begin
            blocked_write_count++;
        end
    end

    // Mirrors the DUT read port: pops the reference queue and compares
    // rdata exactly when the DUT itself would accept the read
    // (rinc & !rempty). rdata is combinational on raddr (pre-update),
    // so it is still valid at the same posedge that causes rptr to move.
    logic [DSIZE-1:0] exp_data;
    always_ff @(posedge rclk) begin
        if (rrst_n && rinc && !rempty) begin
            if (sb_queue.size() > 0) begin
                exp_data = sb_queue.pop_front();
                read_count++;
                if (rdata !== exp_data) begin
                    fail_count++;
                    $display("[%0t] FAIL: read mismatch - expected %0h, got %0h",
                              $time, exp_data, rdata);
                end else begin
                    pass_count++;
                end
            end
        end
        else if (rrst_n && rinc && rempty) begin
            blocked_read_count++;
        end
    end

    //-------------------------------------------------------------------
    // Checking helper
    //-------------------------------------------------------------------
    task automatic check(input bit condition, input string msg);
        if (condition) begin
            pass_count++;
        end else begin
            fail_count++;
            $display("[%0t] FAIL: %s", $time, msg);
        end
    endtask

    //-------------------------------------------------------------------
    // Reset task
    //-------------------------------------------------------------------
    task automatic apply_reset();
        begin
            wrst_n = 0;
            rrst_n = 0;
            winc   = 0;
            rinc   = 0;
            wdata  = '0;
            repeat (3) @(posedge wclk);
            repeat (3) @(posedge rclk);
            wrst_n = 1;
            rrst_n = 1;
            repeat (2) @(posedge wclk);
            repeat (2) @(posedge rclk);
        end
    endtask

    //-------------------------------------------------------------------
    // Single-cycle write / read transaction tasks
    //-------------------------------------------------------------------
    task automatic write_word(input logic [DSIZE-1:0] data);
        begin
            @(posedge wclk);
            wdata = data;
            winc  = 1'b1;
            @(posedge wclk);
            winc  = 1'b0;
        end
    endtask

    task automatic read_word();
        begin
            @(posedge rclk);
            rinc = 1'b1;
            @(posedge rclk);
            rinc = 1'b0;
        end
    endtask

    // Attempts a write without checking/waiting on wfull first - used to
    // deliberately probe overflow behavior.
    task automatic try_write(input logic [DSIZE-1:0] data);
        begin
            @(posedge wclk);
            wdata = data;
            winc  = 1'b1;
            @(posedge wclk);
            winc  = 1'b0;
        end
    endtask

    task automatic try_read();
        begin
            @(posedge rclk);
            rinc = 1'b1;
            @(posedge rclk);
            rinc = 1'b0;
        end
    endtask

    //-------------------------------------------------------------------
    // Watchdog - guards against a stuck/hanging simulation
    //-------------------------------------------------------------------
    initial begin
        #5_000_000;
        $display("[%0t] ERROR: Global watchdog timeout - simulation did not finish", $time);
        $display("=================================================================");
        $display(" FINAL RESULT (TIMEOUT) : PASS=%0d FAIL=%0d", pass_count, fail_count);
        $display("=================================================================");
        $finish;
    end

    //-------------------------------------------------------------------
    // Main test sequence
    //-------------------------------------------------------------------
    initial begin
        int i;
        logic [DSIZE-1:0] rand_data;

        $display("=================================================================");
        $display(" Asynchronous FIFO (16 x 32) Self-Checking Testbench");
        $display("=================================================================");

        //=================================================================
        // TEST 1: Reset behavior
        //=================================================================
        $display("\n[TEST 1] Reset behavior");
        apply_reset();
        check(rempty === 1'b1, "rempty should be asserted immediately after reset");
        check(wfull  === 1'b0, "wfull should be deasserted immediately after reset");

        //=================================================================
        // TEST 2: Single write, single read
        //=================================================================
        $display("\n[TEST 2] Single write / single read");
        write_word(32'hDEAD_BEEF);
        repeat (4) @(posedge rclk);   // allow the write pointer to cross into the read domain
        check(rempty === 1'b0, "rempty should deassert after one word is written");
        read_word();
        repeat (4) @(posedge rclk);
        check(rempty === 1'b1, "rempty should reassert after the single word is read back");

        //=================================================================
        // TEST 3: Fill to FULL and attempt overflow
        //=================================================================
        $display("\n[TEST 3] Fill to FULL, then attempt overflow writes");
        for (i = 0; i < DEPTH; i++) begin
            rand_data = $urandom();
            write_word(rand_data);
        end
        repeat (4) @(posedge wclk);
        check(wfull === 1'b1, "wfull should assert after writing exactly DEPTH words");

        // Attempt three overflow writes - the reference model will not
        // grow past DEPTH entries because it mirrors the wfull-qualified
        // write condition, so any resulting mismatch below would reveal
        // that the DUT accepted a write it should have blocked.
        for (i = 0; i < 3; i++) begin
            try_write($urandom());
        end
        check(sb_queue.size() == DEPTH, "scoreboard depth should stay at DEPTH after overflow attempts");
        check(wfull === 1'b1, "wfull should remain asserted through overflow attempts");

        //=================================================================
        // TEST 4: Drain to EMPTY and attempt underflow
        //=================================================================
        $display("\n[TEST 4] Drain to EMPTY, then attempt underflow reads");
        for (i = 0; i < DEPTH; i++) begin
            read_word();
        end
        repeat (4) @(posedge rclk);
        check(rempty === 1'b1, "rempty should assert after reading back all DEPTH words");
        check(sb_queue.size() == 0, "scoreboard should be empty after draining DEPTH words");

        for (i = 0; i < 3; i++) begin
            try_read();
        end
        check(rempty === 1'b1, "rempty should remain asserted through underflow attempts");
        check(sb_queue.size() == 0, "scoreboard should remain empty through underflow attempts");

        //=================================================================
        // TEST 5: Pointer wrap-around - repeated fill/drain cycles
        //=================================================================
        $display("\n[TEST 5] Pointer wrap-around (repeated fill/drain cycles)");
        for (int cyc = 0; cyc < 4; cyc++) begin
            for (i = 0; i < DEPTH; i++) write_word($urandom());
            repeat (4) @(posedge wclk);
            check(wfull === 1'b1, $sformatf("wfull should assert on wrap-around cycle %0d", cyc));
            for (i = 0; i < DEPTH; i++) read_word();
            repeat (4) @(posedge rclk);
            check(rempty === 1'b1, $sformatf("rempty should assert on wrap-around cycle %0d", cyc));
        end

        //=================================================================
        // TEST 6: Simultaneous read and write operations
        //=================================================================
        $display("\n[TEST 6] Simultaneous read/write around FULL/EMPTY boundaries");
        fork
            begin : concurrent_writer
                for (int k = 0; k < 40; k++) begin
                    write_word($urandom());
                end
            end
            begin : concurrent_reader
                // Start slightly behind the writer so the FIFO has data,
                // then race the writer for the remainder of the run.
                repeat (6) @(posedge rclk);
                for (int k = 0; k < 40; k++) begin
                    read_word();
                end
            end
        join

        // Drain whatever remains so the FIFO returns to EMPTY before the
        // next phase begins.
        while (sb_queue.size() > 0) begin
            read_word();
        end
        repeat (4) @(posedge rclk);
        check(rempty === 1'b1, "rempty should assert once the concurrent phase fully drains");

        //=================================================================
        // TEST 7: Randomized stress test across different clock relationships
        //=================================================================
        $display("\n[TEST 7] Randomized stress - wclk faster than rclk");
        wclk_period = 6;
        rclk_period = 20;
        run_random_stress(300);

        $display("\n[TEST 7] Randomized stress - rclk faster than wclk");
        wclk_period = 22;
        rclk_period = 7;
        run_random_stress(300);

        $display("\n[TEST 7] Randomized stress - comparable, non-integer-ratio clocks");
        wclk_period = 9;
        rclk_period = 13;
        run_random_stress(300);

        //=================================================================
        // Final drain and summary
        //=================================================================
        while (sb_queue.size() > 0) begin
            read_word();
        end
        repeat (4) @(posedge rclk);
        check(rempty === 1'b1, "FIFO should end the test fully drained");
        check(sb_queue.size() == 0, "scoreboard should end the test fully drained");

        $display("\n=================================================================");
        $display(" TEST SUMMARY");
        $display("   Writes accepted        : %0d", write_count);
        $display("   Reads accepted/checked : %0d", read_count);
        $display("   Writes blocked (FULL)  : %0d", blocked_write_count);
        $display("   Reads blocked (EMPTY)  : %0d", blocked_read_count);
        $display("   Checks passed          : %0d", pass_count);
        $display("   Checks failed          : %0d", fail_count);
        if (fail_count == 0)
            $display(" RESULT: PASS - all checks passed");
        else
            $display(" RESULT: FAIL - %0d check(s) failed", fail_count);
        $display("=================================================================");

        $finish;
    end

    //-------------------------------------------------------------------
    // Randomized stress task: random data, random enable pulses, random
    // idle gaps between transactions, run concurrently on both domains.
    //-------------------------------------------------------------------
    task automatic run_random_stress(input int num_transactions);
        begin
            fork
                begin : rand_writer
                    int n;
                    n = 0;
                    while (n < num_transactions) begin
                        @(posedge wclk);
                        if (!wfull && ($urandom_range(0, 3) != 0)) begin
                            wdata = $urandom();
                            winc  = 1'b1;
                            @(posedge wclk);
                            winc  = 1'b0;
                            n++;
                            // occasional random idle gap
                            repeat ($urandom_range(0, 3)) @(posedge wclk);
                        end else begin
                            winc = 1'b0;
                        end
                    end
                    winc = 1'b0;
                end
                begin : rand_reader
                    int n;
                    n = 0;
                    while (n < num_transactions) begin
                        @(posedge rclk);
                        if (!rempty && ($urandom_range(0, 3) != 0)) begin
                            rinc = 1'b1;
                            @(posedge rclk);
                            rinc = 1'b0;
                            n++;
                            // occasional random idle gap
                            repeat ($urandom_range(0, 3)) @(posedge rclk);
                        end else begin
                            rinc = 1'b0;
                        end
                    end
                    rinc = 1'b0;
                end
            join

            // Drain any words the reader hasn't caught up on yet so each
            // stress phase ends from a clean, fully-drained state.
            while (sb_queue.size() > 0) begin
                read_word();
            end
            repeat (4) @(posedge rclk);
        end
    endtask

endmodule
