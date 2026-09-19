# Protocol Emulator ASIC

Tiny Tapeout IHP CMOS5L implementation of the Jane Street programmable
protocol-emulator ASIC. The project targets a 6x4 tile allocation and keeps
all eight bidirectional pins exclusively for programmable protocol GPIO.

## Physical mapping

- ui_in[0]: CFG_MOSI
- ui_in[1]: CFG_SCLK
- ui_in[2]: CFG_CS_N
- uo_out[0]: CFG_MISO
- uo_out[1] and uo_out[7:2]: reserved, driven low
- uio_in/out/oe[7:0]: programmable protocol GPIO

The management SPI is sampled into the main clk domain. It is Mode 0,
MSB-first, and initially constrained to at or below 5 MHz for a nominal
50 MHz system clock. CFG_SCLK is not used as an internal clock.

## Management path

~~~
CFG SPI pins
  -> cfg_spi_slave
  -> host_cmd_if
  -> canonical management bus
  -> management_decode
  -> pe_host_if
  -> IMEM / CSRs / FIFOs
  -> protocol engine
  -> uio[7:0]
~~~

The direct host-style transaction interface remains internal to RTL
verification and is not exposed as chip pins. There is one active IMEM and one
active TX/RX FIFO pair.

See docs/register_map.md for the register map and SPI packets.
See docs/asic_architecture.md for the full hierarchy and CDC policy.
See docs/milestone2_results.md for current verification results.

## Verification

Dependency-free architectural regression:

~~~
python3 tests/run_tests.py
~~~

Official Tiny Tapeout Cocotb wrapper smoke test:

~~~
cd test
PATH=../.venv/bin:$PATH make SIM=verilator
~~~

Public-pin management SPI test:

~~~
verilator --binary --timing --Wno-fatal --top-module tb_mgmt_spi
  --Mdir sim/mgmt_obj_dir tests/tb_mgmt_spi.sv src/project.v
  src/cfg_spi_slave.sv src/host_cmd_if.sv src/management_decode.sv
  src/csr_block.sv
  src/engine/*.sv
./sim/mgmt_obj_dir/Vtb_mgmt_spi
~~~

The execution engine implements the frozen Milestone 0 ISA model and supports
programmable SET, MOV, JMP, WAIT, IN, OUT, PUSH, PULL, delay, side-set,
clock-divider, GPIO output/OE, and 4x32 TX/RX FIFOs. UART/SPI/I2C remain
microcode programs; no dedicated protocol RTL is used.
