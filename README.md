# Protocol Emulator ASIC

Tiny Tapeout IHP CMOS5L implementation of the Jane Street programmable protocol-emulator ASIC concept. The project targets a 6x4 tile allocation and keeps the eight `uio` pins exclusively for protocol GPIO.

## Fixed top-level mapping

- `ui_in[0]`: CFG_MOSI
- `ui_in[1]`: CFG_SCLK
- `ui_in[2]`: CFG_CS_N
- `uo_out[0]`: CFG_MISO
- `uio_in/out/oe[7:0]`: programmable protocol GPIO

The management SPI transport is sampled into the main clk domain (Mode 0, MSB-first, initially at or below 5 MHz). It carries generic register and burst transactions to the same internal management target used by RTL verification; the old host-style interface remains internal and is not exposed as chip pins.

## Verification

From the repository root:

```text
python3 tests/run_tests.py
python3 tests/generate_golden.py
```

The existing Milestone 1 engine can be linted with Verilator using the source list in `info.yaml`. The official Cocotb test requires the template's Python dependencies.
