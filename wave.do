# wave.do
vlib work
vmap work work

vlog -sv src/two_ff_sync.sv src/fifo_mem.sv src/wptr_full.sv src/rptr_empty.sv src/async_fifo_top.sv
vlog -sv verif/async_fifo_tb.sv

vsim -voptargs=+acc work.async_fifo_tb

# --- native ModelSim waveform (view in the GUI, or reload later) ---
add wave -r /*

# --- also dump a portable VCD so GTKWave can open it ---
vcd file waves.vcd
vcd add -r /async_fifo_tb/*

run -all

# vsim -do wave.do
# vsim -c -do "source wave.do; quit -f" | tee sim.log    batch Mode
# gtkwave waves.vcd