//=============================================================================
// File   : wptr_full.sv
// Module : wptr_full
//
// Description:
//   Write-domain pointer handler. Maintains the binary write pointer (used
//   to address memory locally), derives its Gray-coded equivalent (used to
//   cross into the read clock domain), and generates the registered FULL
//   flag by comparing the next Gray write pointer against the read pointer
//   that has already been synchronized into the write domain (wq2_rptr).
//
//   FULL detection (Cummings' classic test): the FIFO is full when the next
//   write pointer, in Gray code, is equal to the synchronized read pointer
//   with its two MSBs inverted. Comparing the two MSBs inverted is what
//   distinguishes "pointers equal because full" from "pointers equal
//   because empty" in a Gray-coded, wrap-around pointer scheme.
//
// Parameters:
//   ASIZE : address bus width (pointer width = ASIZE+1)
//
// Ports:
//   wclk, wrst_n : write clock domain / async active-low reset
//   winc         : write-increment request
//   wq2_rptr     : read pointer (Gray), synchronized into the write domain
//   wptr         : write pointer (Gray) - exported for CDC into read domain
//   waddr        : binary write address into fifo_mem
//   wfull        : registered FIFO-full flag
//=============================================================================

module wptr_full #(
    parameter int ASIZE = 4
) (
    input  logic               wclk,
    input  logic               wrst_n,
    input  logic                winc,
    input  logic [ASIZE:0]      wq2_rptr,
    output logic [ASIZE:0]      wptr,
    output logic [ASIZE-1:0]    waddr,
    output logic                wfull
);

    logic [ASIZE:0] wbin;
    logic [ASIZE:0] wbin_next;
    logic [ASIZE:0] wgray_next;
    logic           wfull_val;

    // Binary and Gray pointer registers
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin <= '0;
            wptr <= '0;
        end else begin
            wbin <= wbin_next;
            wptr <= wgray_next;
        end
    end

    assign waddr      = wbin[ASIZE-1:0];
    assign wbin_next  = wbin + (winc & ~wfull);
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;   // binary -> Gray

    // Full occurs when the next write pointer (Gray) equals the
    // synchronized read pointer with the two MSBs flipped.
    assign wfull_val = (wgray_next == {~wq2_rptr[ASIZE:ASIZE-1], wq2_rptr[ASIZE-2:0]});

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) wfull <= 1'b0;
        else         wfull <= wfull_val;
    end

endmodule
