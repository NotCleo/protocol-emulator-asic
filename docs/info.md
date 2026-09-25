<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project is a programmable protocol emulator: a small microcoded engine
that bit-bangs serial protocols (UART, SPI, I2C, and similar) entirely in
software, in the style of the RP2040 PIO. No dedicated protocol RTL exists;
every protocol is a microcode program loaded by the host.

The chip is split into a management plane and an execution plane:

- **Management plane.** A sampled Mode-0, MSB-first SPI slave on
  `ui_in[2:0]` / `uo_out[0]` (CFG_CS_N, CFG_SCLK, CFG_MOSI, CFG_MISO) accepts
  WRITE32, READ32, BURST_WRITE32, and BURST_READ32 packets. The pins are
  double-synchronized into the 50 MHz main clock domain; CFG_SCLK is never
  used as an internal clock, and management traffic is supported up to
  5 MHz. Packets reach a single canonical 32-bit management bus that decodes
  to the register map: control/status, clock divider, pin-mapping
  configuration, 32-bit TX/RX FIFO data ports, debug registers, and program
  memory at 0x100+ (two 16-bit instructions per word). IMEM and configuration
  writes are only allowed while the engine is halted.
- **Execution plane.** The protocol engine fetches 16-bit instructions from a
  64-entry IMEM and executes the frozen Milestone-0 ISA: SET, MOV, JMP, WAIT,
  IN, OUT, PUSH, PULL, programmable delays, side-set pins, and an integer
  clock divider, with X/Y scratch registers, OSR/ISR shift registers, and 4x32
  TX/RX FIFOs to the host. All eight bidirectional `uio[7:0]` pins are
  programmable protocol GPIO with per-pin output-enable control and
  configurable base/count pin mapping.

Typical operation: the host holds the engine halted, burst-writes an assembled
microcode program into IMEM, configures pin mapping and clock divider, pushes
TX data, asserts RUN, and then streams words through the TX/RX FIFO registers
while the engine drives the protocol waveforms on `uio[7:0]`.

## How to test

1. Connect an SPI master (e.g. a USB-SPI adapter or MCU) to the management
   pins: `ui_in[0]`=CFG_MOSI, `ui_in[1]`=CFG_SCLK, `ui_in[2]`=CFG_CS_N,
   `uo_out[0]`=CFG_MISO. Use SPI Mode 0, MSB-first, at 5 MHz or slower.
2. While the engine is halted (CTRL.RUN=0), use BURST_WRITE32 (command 0x03)
   to address 0x100+ to load the microcode program, and WRITE32 (command 0x01)
   to configure START_PC (0x008), CLKDIV (0x00C), SET_CFG (0x010),
   SIDESET_CFG (0x014), OUT_CFG (0x02C), IN_CFG (0x030), and SHIFT_CFG (0x034).
3. Optionally preload TX data by writing TX_DATA (0x018).
4. Write CTRL (0x000) with bit 0 set to start execution, then observe the
   protocol waveform on `uio[7:0]` with a logic analyzer, or read RX_DATA
   (0x01C) and STATUS (0x004) over SPI.

Example programs are provided in `src/rtl/`: `gpio_toggle.pasm` toggles a pin
(the minimal smoke test), and `uart_tx.pasm` transmits 8N1 UART at the baud
rate set by CLKDIV. They assemble with `tools/assembler.py`. Invalid SPI
commands, writes to read-only registers, FIFO overflow/underflow, and IMEM
writes while running all raise the management error response
(read data 0xDEADBEEF) and, for running IMEM writes, the sticky FAULT bit, so
error paths can be verified directly over SPI. Raising CS_N mid-transaction
safely aborts and resets the packet state machine.

The repository also carries the full verification environment used during
development: a dependency-free Python regression (`python3
tests/run_tests.py`), a randomized RTL-vs-model differential suite
(`python3 tests/random_differential.py`), direct Verilator testbenches under
`tests/`, and the cocotb physical-pin suite under `test/`.

## External hardware

- SPI master (USB-SPI adapter, MCU, or FT232H-class bridge) for the management
  interface on `ui_in[2:0]` / `uo_out[0]`.
- Logic analyzer or oscilloscope to observe the emulated protocol waveforms on
  `uio[7:0]` (optional).
- Protocol-specific pull-ups as required by the emulated device, e.g. 4.7k
  resistors on the two `uio` pins used as I2C SDA/SCL (open-drain OE control
  is provided by the engine; the chip itself has no internal pull-ups).
