# Milestone 1 results

## Scope

Milestone 1 is complete for the protocol execution plane. The RTL includes the
64 x 16 instruction memory, PC, X/Y, OSR/ISR, decoder, SET, MOV, JMP, IN, OUT,
WAIT, PUSH/PULL, integrated 4 x 32 TX/RX FIFOs, delay, side-set, integer
clock divider, synchronized GPIO input, GPIO output/OE, RUN/HALT, SOFT_RESET,
START_PC, and sticky FAULT handling. The fixed management SPI frontend is
still an idle stub by design and is not part of this milestone.

## RTL hierarchy

```text
tt_um_protocol_emulator
├── cfg_spi_slave                 idle management boundary
└── protocol_emulator_top         internal verification/programming boundary
    ├── pe_host_if
    ├── pe_imem
    ├── pe_sync                    two FFs per GPIO input
    ├── pe_clkdiv
    ├── pe_fifo                     TX and RX instances
    ├── pe_core
    │   └── pe_decoder
    └── pe_io
```

The active execution-side memory is `pe_imem`; `program_mem.sv` remains an
inert future management-facing boundary. The active FIFOs are
`engine/pe_fifo.sv`; top-level `tx_fifo.sv` and `rx_fifo.sv` are future
management boundaries. This is documented in `docs/asic_architecture.md`.

## Tools

- Simulator: Verilator 5.049 development build (`/usr/local/bin/verilator`)
- Cocotb: 2.1.0 in a project-local virtual environment
- Other simulator: `iverilog` not installed
- Synthesis: no Yosys or other synthesis tool installed

## Exact test commands

```text
python3 tests/run_tests.py
python3 tests/generate_golden.py
verilator --lint-only --timing --Wno-fatal --top-module tt_um_protocol_emulator \
  src/project.v src/*.sv src/engine/*.sv
verilator --binary --timing --Wno-fatal --top-module tb_milestone1 \
  -Mdir sim/obj_dir -o tb_milestone1 tests/tb_milestone1.sv src/engine/*.sv
sim/obj_dir/tb_milestone1
python3 tests/compare_rtl_trace.py tests/golden/gpio_toggle.trace sim/rtl_gpio_toggle.trace
verilator --binary --timing --Wno-fatal --top-module tb_milestone13 \
  -Mdir sim/obj_m13 -o tb_milestone13 tests/tb_milestone13.sv src/engine/*.sv
sim/obj_m13/tb_milestone13
verilator --binary --timing --Wno-fatal --top-module tb_fifo_stress \
  -Mdir sim/obj_fifo -o tb_fifo_stress tests/tb_fifo_stress.sv src/engine/pe_fifo.sv
sim/obj_fifo/tb_fifo_stress
verilator --binary --timing --Wno-fatal --top-module tb_clkdiv \
  -Mdir sim/obj_clkdiv -o tb_clkdiv tests/tb_clkdiv.sv src/engine/pe_clkdiv.sv
sim/obj_clkdiv/tb_clkdiv
python3 tests/random_differential.py
cd test && PATH=../.venv/bin:$PATH make SIM=verilator
```

## Results

- Dependency-free Milestone-0 regression: **13 passed, 0 failed**.
- Deterministic golden traces: GPIO toggle, delay, side-set, and JMP all
  matched; **0 mismatches**.
- Public Milestone-1 host-interface testbench: **PASS**.
- M1.1/M1.2/M1.3 directed testbench: **PASS**, including IN/OUT, MOV, WAIT
  with synchronized input, PULL/PUSH, FIFO full/empty behavior, and GPIO OE.
- RTL FIFO randomized stress: **100,000 operations, PASS**.
- Clock-divider test: divisors **1, 2, 3, 4, and 15, PASS**.
- Constrained randomized differential testing: **100 programs x 100 engine
  ticks = 10,000 architectural comparisons, 0 mismatches**. Seed base:
  `0x051a5eed`.
- Cocotb Tiny Tapeout wrapper smoke test: **PASS** on Verilator.
- Verilator top-level lint/elaboration: **PASS** with nonfatal width-expansion
  warnings.
- Parameterized PC boundary tests: **PASS** for 64-word and 128-word memories;
  both fault at the final sequential instruction without wrapping.

The differential trace compares cycle/engine tick, PC/instruction, X/Y, OSR/ISR,
engine-visible GPIO input, GPIO output/OE, TX/RX FIFO levels and activity, WAIT
state, delay, side-set effect, run/fault state, and stall reason.

## Semantics and decisions

- `CLKDIV=0` is interpreted as 1. No generated clock is used.
- `wdata[15:0]` programs the lower-address instruction and `wdata[31:16]`
  programs the next instruction. Byte strobes are honored.
- Blocking WAIT/PULL/PUSH holds PC and architectural datapath state until its
  condition becomes true.
- IN shifts GPIO data into ISR; OUT shifts OSR data to its selected destination.
  The default shift configuration is input-left accumulation and output-right
  shifting, matching the Python model.
- GPIO inputs pass through the two-flop `pe_sync` wrapper before WAIT, branches,
  and IN observe them. The Python architectural model remains deterministic;
  physical-input tests explicitly allow for synchronizer latency.
- PC width is `$clog2(IMEM_DEPTH)`. Sequential execution faults at the final
  valid instruction when the next fetch would be outside memory; PC remains at
  the last valid address and does not wrap.
- The six-bit encoded JMP target remains an ISA encoding limitation for memories
  deeper than 64 words; this is documented rather than silently redesigned.

## Known limitations

- Functional management SPI, CDC transaction bridging, final CSR ownership, and
  SRAM macro replacement are not implemented yet.
- Verilator reports width-expansion diagnostics in arithmetic/comparison sites;
  they are nonfatal and do not produce lint errors.
- No synthesis, area, timing, or Fmax numbers are available because no synthesis
  tool is installed in the environment.

## Remaining work before management SPI

The execution-plane M1 work is complete. Before implementing functional management
SPI, the next architectural work is to replace the idle SPI boundary with a
packet decoder, define the internal transaction/CSR ownership, and add explicit
CDC handling for the future SPI-clock-to-`clk` path. No protocol-specific RTL
block is required or planned.
