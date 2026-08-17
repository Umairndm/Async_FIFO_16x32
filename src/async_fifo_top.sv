//=============================================================================
// File   : async_fifo_top.sv
// Module : async_fifo_top
//
// Description:
//   Top-level 16 x 32-bit asynchronous FIFO. Wraps the dual-port memory,
//   the write- and read-pointer handlers, and the two Gray-code
//   synchronizers that carry pointer information safely across the write
//   and read clock domains. This module follows the architecture in
//   doc/async_fifo_block_diagram.png:
//
//        wdata --------------------------> [ fifo_mem ] --------------> rdata
//                                            ^         ^
//                                       waddr|         |raddr
//                                            |         |
//        winc --> [ wptr_full ] --wptr--> [sync w2r] --> rq2_wptr --> [ rptr_empty ] <-- rinc
//                       ^                                                   |
//                       |<---------- wq2_rptr <-- [sync r2w] <----- rptr ---|
//
// Parameters:
//   DSIZE : data width   (default 32)
//   ASIZE : address width (default 4 -> 16-word depth)
//
// Ports:
//   wclk, wrst_n, winc, wdata : write-domain interface
//   rclk, rrst_n, rinc, rdata : read-domain interface
//   wfull                     : write-domain full flag
//   rempty                    : read-domain empty flag
//=============================================================================

module async_fifo_top #(
    parameter int DSIZE = 32,
    parameter int ASIZE = 4
) (
    // Write domain
    input  logic                wclk,
    input  logic                wrst_n,
    input  logic                winc,
    input  logic [DSIZE-1:0]    wdata,
    output logic                wfull,

    // Read domain
    input  logic                rclk,
    input  logic                rrst_n,
    input  logic                rinc,
    output logic [DSIZE-1:0]    rdata,
    output logic                rempty
);

    // Binary addresses local to each domain
    logic [ASIZE-1:0] waddr, raddr;

    // Gray-coded pointers, native and cross-domain synchronized copies
    logic [ASIZE:0] wptr, rptr;
    logic [ASIZE:0] wq2_rptr;   // read pointer, synchronized into write domain
    logic [ASIZE:0] rq2_wptr;   // write pointer, synchronized into read domain

    //-------------------------------------------------------------------
    // Read pointer (Gray) -> write clock domain
    //-------------------------------------------------------------------
    two_ff_sync #(.WIDTH(ASIZE+1)) sync_r2w (
        .clk   (wclk),
        .rst_n (wrst_n),
        .din   (rptr),
        .dout  (wq2_rptr)
    );

    //-------------------------------------------------------------------
    // Write pointer (Gray) -> read clock domain
    //-------------------------------------------------------------------
    two_ff_sync #(.WIDTH(ASIZE+1)) sync_w2r (
        .clk   (rclk),
        .rst_n (rrst_n),
        .din   (wptr),
        .dout  (rq2_wptr)
    );

    //-------------------------------------------------------------------
    // Dual-port storage
    //-------------------------------------------------------------------
    fifo_mem #(.DSIZE(DSIZE), .ASIZE(ASIZE)) u_fifo_mem (
        .wclk    (wclk),
        .wclk_en (winc),
        .wfull   (wfull),
        .waddr   (waddr),
        .raddr   (raddr),
        .wdata   (wdata),
        .rdata   (rdata)
    );

    //-------------------------------------------------------------------
    // Write-domain pointer handler + FULL flag
    //-------------------------------------------------------------------
    wptr_full #(.ASIZE(ASIZE)) u_wptr_full (
        .wclk     (wclk),
        .wrst_n   (wrst_n),
        .winc     (winc),
        .wq2_rptr (wq2_rptr),
        .wptr     (wptr),
        .waddr    (waddr),
        .wfull    (wfull)
    );

    //-------------------------------------------------------------------
    // Read-domain pointer handler + EMPTY flag
    //-------------------------------------------------------------------
    rptr_empty #(.ASIZE(ASIZE)) u_rptr_empty (
        .rclk     (rclk),
        .rrst_n   (rrst_n),
        .rinc     (rinc),
        .rq2_wptr (rq2_wptr),
        .rptr     (rptr),
        .raddr    (raddr),
        .rempty   (rempty)
    );

endmodule
