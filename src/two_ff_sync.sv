//=============================================================================
// File   : two_ff_sync.sv
// Module : two_ff_sync
//
// Description:
//   Generic two-stage (double flip-flop) synchronizer used to bring a
//   Gray-coded pointer safely from one clock domain into another. Gray
//   coding guarantees only a single bit toggles between consecutive pointer
//   values, so even if the destination domain samples the bus mid-transition
//   the resulting metastability can only resolve to a value that is at most
//   one count away from the correct one - it can never be an arbitrary,
//   corrupted value.
//
// Parameters:
//   WIDTH : width of the vector being synchronized (pointer width, ASIZE+1)
//
// Ports:
//   clk    : destination domain clock
//   rst_n  : destination domain asynchronous active-low reset
//   din    : Gray-coded pointer, source domain
//   dout   : Gray-coded pointer, resynchronized into the destination domain
//=============================================================================

module two_ff_sync #(
    parameter int WIDTH = 5
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout
);

    logic [WIDTH-1:0] stage1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1 <= '0;
            dout   <= '0;
        end else begin
            stage1 <= din;
            dout   <= stage1;
        end
    end

endmodule
