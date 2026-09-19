# Management register map

The physical management plane uses a sampled, Mode-0 SPI transport. SPI commands
are translated to this single synchronous 32-bit management bus:

```
mgmt_valid, mgmt_write, mgmt_addr[15:0], mgmt_wdata[31:0], mgmt_wstrb[3:0]
mgmt_ready, mgmt_rdata[31:0], mgmt_error
```

All multi-byte SPI fields are big-endian. Program-memory words are packed with
the lower-address instruction in bits `[15:0]` and the next instruction in
bits `[31:16]`.

| Address | Register | Access | Description |
|---:|---|---|---|
| 0x000 | CTRL | W | bit 0 RUN, bit 1 HALT, bit 2 SOFT_RESET |
| 0x004 | STATUS | R | bit 0 RUNNING, bit 1 FAULT, bits 2:5 FIFO empty/full, PC from bit 6 |
| 0x008 | START_PC | RW halted | Start PC loaded by RUN |
| 0x00C | CLKDIV | RW halted | Integer divider; zero is stored as one |
| 0x010 | SET_CFG | RW halted | Contiguous SET/PINDIRS base |
| 0x014 | SIDESET_CFG | RW halted | base in low bits, count in bits [9:8] |
| 0x018 | TX_DATA | W | Push one 32-bit word into TX FIFO |
| 0x01C | RX_DATA | R | Read and pop one RX FIFO word |
| 0x020 | FIFO_STATUS | R | empty/full flags and TX/RX occupancy |
| 0x024 | PC_DEBUG | R | Current PC |
| 0x028 | GPIO_IN_DEBUG | R | Synchronized GPIO input |
| 0x02C | OUT_CFG | RW halted | OUT pin base |
| 0x030 | IN_CFG | RW halted | IN pin base |
| 0x034 | SHIFT_CFG | RW halted | Global shift direction configuration |
| 0x038 | X_DEBUG | R | X register |
| 0x03C | Y_DEBUG | R | Y register |
| 0x040 | OSR_DEBUG | R | OSR |
| 0x044 | ISR_DEBUG | R | ISR |
| 0x100+ | PROGRAM | RW halted | Two 16-bit instructions per aligned 32-bit word |

RX_DATA pops on accepted management read. Writes to read-only addresses,
invalid addresses, full TX FIFO writes, empty RX FIFO reads, and IMEM/config
writes while running assert the management error response. A running IMEM write
also sets the execution-plane sticky FAULT and halts the engine.

## SPI packet format

The sampled management SPI frontend supports Mode 0 (CPOL=0, CPHA=0),
MSB-first:

- 0x01 WRITE32: command, address high, address low, four data bytes.
- 0x02 READ32: command, address high, address low, then four response bytes.
- 0x03 BURST_WRITE32: command, address high, address low, count byte, then
  count data words. Address increments by four.
- 0x04 BURST_READ32: command, address high, address low, count byte, then
  count response words. Address increments by four.

CS high terminates and resets an incomplete transaction. Unknown commands,
zero-length bursts, and incomplete packets do not modify architectural state.
The current implementation returns 0xDEAD_BEEF for a read transaction whose
canonical target reports an error.

The external CFG_SCLK is not an ASIC clock. CFG_SCLK, CFG_MOSI, and CFG_CS_N
each pass through two flip-flops clocked by the main clk. The frontend detects
synchronized SCLK edges and therefore requires a conservative management rate,
initially at or below 5 MHz for a nominal 50 MHz clk.
