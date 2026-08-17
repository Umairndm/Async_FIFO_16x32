//=============================================================================
// File   : rptr_empty.sv
// Module : rptr_empty
//
// Description:
//   Read-domain pointer handler. Maintains the binary read pointer (used to
//   address memory locally), derives its Gray-coded equivalent (used to
//   cross into the write clock domain), and generates the registered EMPTY
//   flag by directly comparing the next Gray read pointer against the write
//   pointer that has already been synchronized into the read domain
//   (rq2_wptr).
//
//   EMPTY detection: unlike FULL, no MSB inversion is needed - the FIFO is
//   empty exactly when the read pointer catches up to the (synchronized)
//   write pointer, i.e. the two Gray pointers are numerically equal.
//
// Parameters:
//   ASIZE : address bus width (pointer width = ASIZE+1)
//
// Ports:
//   rclk, rrst_n : read clock domain / async active-low reset
//   rinc         : read-increment request
//   rq2_wptr     : write pointer (Gray), synchronized into the read domain
//   rptr         : read pointer (Gray) - exported for CDC into write domain
//   raddr        : binary read address into fifo_mem
//   rempty       : registered FIFO-empty flag
//=============================================================================

module rptr_empty #(
    parameter int ASIZE = 4
) (
    input  logic               rclk,
    input  logic               rrst_n,
    input  logic                rinc,
    input  logic [ASIZE:0]      rq2_wptr,
    output logic [ASIZE:0]      rptr,
    output logic [ASIZE-1:0]    raddr,
    output logic                rempty
);

    logic [ASIZE:0] rbin;
    logic [ASIZE:0] rbin_next;
    logic [ASIZE:0] rgray_next;
    logic           rempty_val;

    // Binary and Gray pointer registers
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin <= '0;
            rptr <= '0;
        end else begin
            rbin <= rbin_next;
            rptr <= rgray_next;
        end
    end

    assign raddr      = rbin[ASIZE-1:0];
    assign rbin_next  = rbin + (rinc & ~rempty);
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;   // binary -> Gray

    // Empty occurs when the next read pointer (Gray) equals the
    // synchronized write pointer.
    assign rempty_val = (rgray_next == rq2_wptr);

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rempty <= 1'b1;
        else         rempty <= rempty_val;
    end

endmodule
