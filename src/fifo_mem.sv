//=============================================================================
// File   : fifo_mem.sv
// Module : fifo_mem
//
// Parameters:
//   DSIZE : data bus width      (default 32)
//   ASIZE : address bus width   (default 4  -> depth = 16)
//
// Ports:
//   wclk    : write clock
//   wclk_en : write enable (winc qualified by fullness at the caller)
//   wfull   : FIFO full flag - blocks the write even if wclk_en is high
//   waddr   : binary write address
//   raddr   : binary read address
//   wdata   : write data
//   rdata   : read data (combinational read of mem[raddr])
//=============================================================================

module fifo_mem #(
    parameter int DSIZE = 32,
    parameter int ASIZE = 4
) (
    input  logic                  wclk,
    input  logic                  wclk_en,
    input  logic                  wfull,
    input  logic [ASIZE-1:0]      waddr,
    input  logic [ASIZE-1:0]      raddr,
    input  logic [DSIZE-1:0]      wdata,
    output logic [DSIZE-1:0]      rdata
);

    localparam int DEPTH = 1 << ASIZE;

    logic [DSIZE-1:0] mem [0:DEPTH-1];

    assign rdata = mem[raddr];

    always_ff @(posedge wclk) begin
        if (wclk_en && !wfull) begin
            mem[waddr] <= wdata;
        end
    end

endmodule
