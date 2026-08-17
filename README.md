# Asynchronous FIFO (16 x 32) — SystemVerilog

A synthesizable 16-deep, 32-bit-wide asynchronous FIFO written in SystemVerilog, built around Clifford Cummings' Gray-code pointer / dual-flip-flop synchronizer architecture, together with a self-checking SystemVerilog testbench.

## Table of Contents
- [Asynchronous FIFO (16 x 32) — SystemVerilog](#asynchronous-fifo-16-x-32--systemverilog)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Repository Layout](#repository-layout)
  - [Architecture](#architecture)
    - [Read and Write Operations](#read-and-write-operations)
    - [Full, Empty and Wrap-Around Detection](#full-empty-and-wrap-around-detection)
    - [Why Gray Code](#why-gray-code)
  - [Signal Glossary](#signal-glossary)
  - [Module Descriptions (`src/`)](#module-descriptions-src)
  - [Testbench (`verif/`)](#testbench-verif)
  - [Running the Simulation on ModelSim / QuestaSim (Linux)](#running-the-simulation-on-modelsim--questasim-linux)
  - [Design Justification](#design-justification)
  - [Results](#results)
  - [Known Limitations](#known-limitations)

## Introduction

FIFO stands for "First-In, First-Out" — a buffer in which the first word written is the first word read out. An **asynchronous FIFO** is a FIFO whose write side and read side are driven by two independent, unrelated clocks (`wclk`, `rclk`). It is the standard building block for safely moving data across a clock-domain crossing (CDC), e.g. between a fast processing core and a slower peripheral, or between two IP blocks in an SoC that run on unrelated clocks.

This implementation targets the project brief's configuration:

| Parameter | Value |
|---|---|
| FIFO depth | 16 words |
| Data width | 32 bits |
| Address/pointer width (`ASIZE`) | 4 bits (+1 wrap bit → 5-bit pointers) |
| Reset | Asynchronous, active-low, independent per domain |

The overall datapath and pointer/synchronizer topology follow the block diagram in [`doc/async_fifo_block_diagram.png`](doc/async_fifo_block_diagram.png), which was produced before any RTL was written, per the project's design-first requirement.

## Repository Layout

```
async-fifo-16x32/
├── README.md                       # this file
├── src/                            # synthesizable RTL (SystemVerilog)
│   ├── async_fifo_top.sv           # top-level FIFO wrapper
│   ├── fifo_mem.sv                 # dual-port 16 x 32 storage
│   ├── wptr_full.sv                # write-domain pointer + FULL flag
│   ├── rptr_empty.sv               # read-domain pointer + EMPTY flag
│   └── two_ff_sync.sv              # 2-flip-flop Gray-code synchronizer
├── verif/                          # verification (SystemVerilog)
│   └── async_fifo_tb.sv            # self-checking testbench + scoreboard
└── doc/                            # design diagram(s) and project spec
    ├── async_fifo_block_diagram.png
    └── project_specification.pdf
```

## Architecture

<img src="doc/async_fifo_block_diagram.png" alt="Async FIFO block diagram" width="900">

The FIFO is split into five modules, each confined to a single clock domain except the two synchronizers, which are the only points where a signal legally crosses from one domain to the other:

- `wptr_full` and the write side of `fifo_mem` run entirely on `wclk` / `wrst_n`.
- `rptr_empty` and the read side of `fifo_mem` run entirely on `rclk` / `rrst_n`.
- `two_ff_sync` (instantiated twice) is the only logic that samples a signal generated in one clock domain with the clock of the other domain.

### Read and Write Operations

The write pointer always points to the **next** location to be written; the read pointer always points to the **current** location to be read.

- On reset, both the binary and Gray write/read pointers are cleared to zero, `rempty` is forced high, and `wfull` is forced low.
- On a write (`winc` asserted and `wfull` low), `wdata` is stored at `mem[waddr]` and the write pointer increments.
- On a read (`rinc` asserted and `rempty` low), `rdata` combinationally reflects `mem[raddr]` and the read pointer increments to the next location.
- Because `raddr` is a registered (binary) pointer, `rdata` is stable for the entire read-domain cycle in which the word is consumed.

### Full, Empty and Wrap-Around Detection

Both pointers are `ASIZE+1 = 5` bits wide — one bit wider than needed to address the 16-word memory. The extra MSB is never used for addressing; it exists purely to disambiguate "pointers equal because empty" from "pointers equal because full" once the write pointer has wrapped around the memory one more time than the read pointer:

- **Empty**: the read pointer (Gray) equals the *synchronized* write pointer (Gray) exactly — both address and both wrap bits match.
- **Full**: the *next* write pointer (Gray) equals the synchronized read pointer (Gray) with its two MSBs (the wrap bit and the top address bit) inverted, and the remaining bits equal. This is the standard Cummings test and correctly distinguishes a full FIFO (write pointer one full lap ahead) from an empty one (pointers exactly equal).

`wfull` and `rempty` are both **registered** outputs, generated one clock ahead of the value they represent (`wfull_val` / `rempty_val` computed combinationally from the *next* pointer, then latched) so they are glitch-free and directly usable to gate the following cycle's write/read enable.

### Why Gray Code

A binary counter can toggle many bits simultaneously when it increments (e.g. `0111 → 1000`). If a multi-bit binary value like that is sampled by an unrelated clock via a synchronizer, different bits can resolve metastability at different times, producing a transient value that never actually existed on the source side. Gray code guarantees that **only one bit changes per increment**, so a synchronizer sampling a Gray-coded pointer mid-transition can only ever resolve to the old value or the new value — never to something arbitrary. This is why only the Gray-coded pointers (`wptr`, `rptr`), never the binary pointers (`wbin`, `rbin`), are allowed to cross clock domains.

## Signal Glossary

| Signal | Domain | Description |
|---|---|---|
| `wclk` | write | Write clock |
| `wrst_n` | write | Active-low asynchronous reset, write domain |
| `winc` | write | Write-enable / write-request pulse |
| `wdata` | write | 32-bit data to be written |
| `wfull` | write | FIFO-full flag; blocks writes when high |
| `waddr` | write | Binary write address into `fifo_mem` |
| `wptr` | write→read | Write pointer, Gray-coded (crosses into read domain) |
| `wq2_rptr` | write | Read pointer, Gray-coded, synchronized into the write domain |
| `rclk` | read | Read clock |
| `rrst_n` | read | Active-low asynchronous reset, read domain |
| `rinc` | read | Read-enable / read-request pulse |
| `rdata` | read | 32-bit data read out (combinational on `raddr`) |
| `rempty` | read | FIFO-empty flag; blocks reads when high |
| `raddr` | read | Binary read address into `fifo_mem` |
| `rptr` | read→write | Read pointer, Gray-coded (crosses into write domain) |
| `rq2_wptr` | read | Write pointer, Gray-coded, synchronized into the read domain |

## Module Descriptions (`src/`)

**`async_fifo_top.sv`** — Top-level wrapper. Instantiates `fifo_mem`, `wptr_full`, `rptr_empty`, and the two `two_ff_sync` synchronizers, and wires them together exactly as shown in the block diagram. `DSIZE` (default 32) and `ASIZE` (default 4) are exposed as parameters so the FIFO can be re-targeted to other widths/depths.

**`fifo_mem.sv`** — The 16 x 32 storage array (`logic [DSIZE-1:0] mem [0:DEPTH-1]`). Synchronous write on `wclk` when `wclk_en & !wfull`; combinational (asynchronous) read on `raddr`.

**`wptr_full.sv`** — Write-domain pointer handler. Maintains the binary write pointer (`wbin`, for addressing) and the Gray write pointer (`wptr`, for CDC), and generates the registered `wfull` flag from the Cummings full test described above.

**`rptr_empty.sv`** — Read-domain pointer handler. Maintains the binary read pointer (`rbin`, for addressing) and the Gray read pointer (`rptr`, for CDC), and generates the registered `rempty` flag.

**`two_ff_sync.sv`** — Generic, parameterized two-stage flip-flop synchronizer. One instance moves the Gray read pointer into the write domain (`sync_r2w`); a second instance moves the Gray write pointer into the read domain (`sync_w2r`).

## Testbench (`verif/`)

`async_fifo_tb.sv` is a **self-checking** testbench built around a behavioral SystemVerilog queue (`sb_queue`) that acts as the golden reference model:

- Every write the DUT actually accepts (`winc & !wfull`, sampled the same clock edge as the DUT) pushes `wdata` into `sb_queue`.
- Every read the DUT actually accepts (`rinc & !rempty`) pops `sb_queue` and compares the popped value against `rdata`; any mismatch is logged and counted as a failure.
- A running pass/fail tally is printed at the end of simulation, along with counts of accepted and blocked writes/reads.

Test sequence:

1. **Reset check** — `rempty` asserted and `wfull` deasserted immediately out of reset.
2. **Single write / single read** — basic sanity check of the datapath and flag transitions.
3. **Fill to FULL + overflow attempts** — write exactly 16 words, confirm `wfull`, then attempt three more writes and confirm the reference model (and therefore the DUT) does not grow past 16 entries.
4. **Drain to EMPTY + underflow attempts** — read all 16 words back in order, confirm `rempty`, then attempt three more reads and confirm nothing further is popped.
5. **Pointer wrap-around** — four repeated fill/drain cycles to walk the Gray pointers through multiple wraps of the memory and the extra MSB.
6. **Simultaneous read/write** — a concurrent writer and reader (`fork...join`) exercise the FIFO around the FULL/EMPTY boundaries at the same time.
7. **Randomized stress testing** — three passes of constrained-random data, random enable pulses, and random inter-transaction idle gaps, each pass with a different write/read clock-period relationship (`wclk` faster than `rclk`, `rclk` faster than `wclk`, and a non-integer-ratio pair), for several hundred transactions per pass.

`wclk_period` and `rclk_period` are ordinary integer variables (not `parameter`s), so the effective clock relationship can be changed between test phases without re-elaborating the design. A global watchdog (`#5_000_000`) guards against a stuck simulation (e.g. a design bug that leaves `wfull`/`rempty` stuck) and forces a clean `$finish` with a FAIL summary if tripped.

The testbench instantiates `async_fifo_top` with `DSIZE = 32`, `ASIZE = 4` — the exact configuration required by the project.

## Running the Simulation on ModelSim / QuestaSim (Linux)

From the repository root:

```bash
# 1. Create a work library
vlib work
vmap work work

# 2. Compile the RTL (src/) followed by the testbench (verif/) as SystemVerilog
vlog -sv src/two_ff_sync.sv src/fifo_mem.sv src/wptr_full.sv src/rptr_empty.sv src/async_fifo_top.sv
vlog -sv verif/async_fifo_tb.sv

# 3a. Run in batch mode (no GUI) with full log output
vsim -c work.async_fifo_tb -do "run -all; quit -f" | tee sim.log

# 3b. Or run interactively with the GUI
vsim work.async_fifo_tb
# then, at the ModelSim/QuestaSim prompt:
# run -all
```

Equivalent single-line invocation, useful for CI or scripting:

```bash
vlib work && vmap work work && \
vlog -sv src/*.sv verif/async_fifo_tb.sv && \
vsim -c work.async_fifo_tb -do "run -all; quit -f"
```

A successful run ends with a block of the form:

```
=================================================================
 TEST SUMMARY
   Writes accepted        : <N>
   Reads accepted/checked : <N>
   Writes blocked (FULL)  : <N>
   Reads blocked (EMPTY)  : <N>
   Checks passed          : <N>
   Checks failed          : 0
 RESULT: PASS - all checks passed
=================================================================
```

Any data mismatch, or any failed status-flag/scoreboard check, prints a `FAIL:` line with the simulation time and increments the failure count, and is reflected in the final `RESULT:` line.

> Waveform dumping/inspection is intentionally left out of the testbench — add a `$dumpfile`/`$dumpvars` (VCD) or a `.wlf`-based `add wave -r /*` in your `vsim -do` script if you want to inspect signals in the GUI; this is left for you to configure to taste.

## Design Justification

- **Pointer width (`ASIZE+1 = 5` bits)**: one bit wider than the 4 bits needed to address 16 locations. The extra bit is required to tell a "wrapped-around, full" condition apart from a "never touched, empty" condition when the lower address bits of the read and write pointers are numerically equal.
- **Gray-code pointers for CDC**: chosen specifically because only one bit changes per increment, which is what makes a two-flip-flop synchronizer safe to use in the first place (see [Why Gray Code](#why-gray-code)).
- **Two-flip-flop synchronizers**: the standard, minimum-latency solution for safely resynchronizing a single Gray-coded, slowly-changing signal into an unrelated clock domain; the second flip-flop exists purely to reduce the probability of a metastable value propagating downstream.
- **Registered `wfull` / `rempty`**: computed one cycle ahead from the *next* pointer value and then registered, so both flags are already stable and glitch-free by the time they are used to gate the following write/read — no combinational full/empty logic reaches the DUT's control inputs directly.
- **Binary pointers kept local**: `wbin`/`rbin` never leave their own clock domain; only the Gray-coded `wptr`/`rptr` are exported, keeping the CDC boundary to the smallest possible signal set.

## Results

Simulation with the provided testbench confirms:

1. **Data integrity** — every word read back matches the word written, in strict FIFO order, across directed tests, wrap-around cycles, concurrent read/write operation, and randomized stress testing under three different clock-period relationships.
2. **Overflow protection** — writes attempted while `wfull` is asserted are correctly discarded; the stored word count never exceeds 16.
3. **Underflow protection** — reads attempted while `rempty` is asserted do not advance the read pointer and do not produce spurious scoreboard entries.
4. **Flag correctness** — `wfull` and `rempty` transition at the expected points across reset, single-word, full-depth, and multi-cycle wrap-around scenarios.

## Known Limitations

- Simulation can validate functional correctness and CDC *protocol* correctness (Gray coding, dual-flop synchronization) but cannot reproduce real silicon metastability; synchronizer reliability in real hardware ultimately depends on the target technology's flop MTBF and proper timing constraints (e.g. `set_false_path`/`set_max_delay` across the two pointer-CDC paths) during implementation.
- No Ready-Valid handshake is implemented at the FIFO boundary, per the project constraints — `winc`/`wfull` and `rinc`/`rempty` are the complete write/read protocol.

