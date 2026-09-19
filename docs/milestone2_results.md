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

## Verification command

```
verilator --binary --timing --Wno-fatal --top-module tb_mgmt_spi \
  --Mdir sim/mgmt_obj_dir tests/tb_mgmt_spi.sv src/project.v src/cfg_spi_slave.sv \
  src/host_cmd_if.sv src/management_decode.sv src/csr_block.sv src/program_mem.sv \
  src/tx_fifo.sv src/rx_fifo.sv src/engine/*.sv
./sim/mgmt_obj_dir/Vtb_mgmt_spi
```

The test covers four asynchronous phase offsets, burst IMEM load/readback,
malformed command recovery, read-only and invalid-address access, running IMEM
write protection, RUN/HALT/SOFT_RESET, GPIO output, and UART microcode loaded
through SPI. Verilator 5.049 passes the test.

The remaining work is broader protocol stress (especially concurrent FIFO
traffic and exhaustive malformed packet sweeps), Cocotb end-to-end coverage of
the physical management packets, and synthesis/P&R measurement. No dedicated
UART/SPI/I2C RTL has been added.
