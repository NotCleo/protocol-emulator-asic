# Milestone 2 results

## Scope

Milestone 1 execution RTL is frozen. Milestone 2 adds the complete sampled
management path without using CFG_SCLK as an internal clock:

```
Tiny Tapeout pins
  -> cfg_spi_slave
  -> host_cmd_if
  -> management_decode
  -> canonical pe_host_if target
  -> IMEM / CSR / FIFO / protocol engine
```

The physical management interface is Mode 0, MSB-first, with a nominal maximum
of 5 MHz at a 50 MHz main clock. All management state is synchronous to `clk`.

## Implemented

- canonical management transaction interface and single active decode target
- generic WRITE32, READ32, BURST_WRITE32, and BURST_READ32 packets
- two-flop synchronization for CFG_MOSI, CFG_SCLK, and CFG_CS_N
- synchronized SCLK edge detection and Mode-0 MISO shifting
- frozen register map in `docs/register_map.md`
- halted-only configuration/IMEM writes
- concurrent TX/RX FIFO management access
- invalid/read-only/error handling and CS-aborted transaction recovery
- public-pin GPIO-toggle and UART microcode smoke tests

## Verification commands

Direct public-pin Verilator test (canonical source set):

```
verilator --binary --timing --Wno-fatal --top-module tb_mgmt_spi \
  --Mdir sim/mgmt_obj_dir tests/tb_mgmt_spi.sv src/project.v src/cfg_spi_slave.sv \
  src/host_cmd_if.sv src/management_decode.sv src/csr_block.sv src/engine/*.sv
./sim/mgmt_obj_dir/Vtb_mgmt_spi
```

The direct test passes phase-offset, burst-load, register, malformed-packet,
RUN/HALT, IMEM protection, GPIO, and UART-management checks.

The complete physical-pin Cocotb suite is run with:

```
cd test
PATH=../.venv/bin:$PATH make SIM=verilator -B
```

It contains 8 tests and passes 8/8. It exercises generic packet operations,
CSR/IMEM/FIFO access, controls, malformed and CS-aborted transactions,
phase offsets, a GPIO waveform, and decoded UART TX. Management traffic was
tested at 1.0 MHz, 2.5 MHz, and 5.0 MHz with phase offsets of 0, 7, 13, and
19 ns relative to the 50 MHz system clock.

The seeded RTL-vs-Python differential suite passes 100 programs x 100 engine
ticks, and the RTL FIFO stress test passes 100,000 randomized operations.
No dedicated UART/SPI/I2C RTL has been added.

Physical hardening status is tracked in `docs/physical_implementation_results.md`.


## Physical hardening status

The official Tiny Tapeout support-tools checkout was obtained at
`/tmp/tt-support-tools`. The documented `--create-user-config --ihp` step was
attempted, but the local `.venv` lacks the support-tool dependencies and package
installation could not complete because the package index was unreachable.
Docker is installed, but its daemon socket is not accessible to the current
user. Therefore no local LibreLane/IHP hardening run or physical metrics are
claimed yet. The repository workflow `.github/workflows/gds.yaml` remains
configured for the official `TinyTapeout/tt-gds-action@ttihp26b` IHP build path.
