//=============================================================================
// File   : two_ff_sync.sv
// Module : two_ff_sync
//
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
