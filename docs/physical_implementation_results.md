# Physical implementation results

## Status

Local synthesis now passes; the official IHP hardening run is pending in CI.

### Synthesis blocker fixed (local Yosys)

The first CI `gds` runs failed during Yosys elaboration with:

```text
ERROR: Multiple edge sensitive events found for this signal!
```

Root cause: `pe_fifo.sv` and `pe_io.sv` used `if (!rst_ni || soft_reset_i)`
inside `always_ff @(posedge clk_i or negedge rst_ni)`. Yosys cannot map a
compound async-branch condition to an async-reset flop template, so the
`negedge rst_ni` event became a second clock edge for every signal in the
branch. The fix splits the pure async reset (`!rst_ni`) from a synchronous
`else if (soft_reset_i)` clear, which preserves the exact simulation
semantics (soft reset was already sampled on `posedge clk_i`). The module-scope
`integer i` loop variables in `pe_fifo.sv`/`pe_imem.sv` were also localized to
`for (int i = ...)` so no register is inferred for them.

Post-fix verification: architectural regression 13/13, FIFO stress
(100,000 randomized operations, exercises soft reset), RTL-vs-Python
differential suite (100 programs x 100 ticks), management SPI direct test, and
the cocotb physical-pin suite 8/8 all pass.

### Local generic-cell synthesis estimate

Generic synthesis with Yosys 0.55 (yowasp build), no PDK library:

```text
yowasp-yosys -p "read_verilog -sv src/project.v src/cfg_spi_slave.sv \
  src/host_cmd_if.sv src/management_decode.sv src/csr_block.sv src/engine/*.sv; \
  hierarchy -top tt_um_protocol_emulator -check; synth -top tt_um_protocol_emulator; stat"
```

| Metric | Result (generic cells) |
|---|---|
| Total design cells | 14,874 |
| Total flip-flop cells | ~6,634 |
| pe_imem (64x16, inferred register array) | 5,433 |
| pe_core | 3,026 |
| cfg_spi_slave (sampled SPI frontend) | 2,893 |
| pe_io (8-pin GPIO mux/side-set) | 1,584 |
| pe_host_if | 774 |
| pe_fifo (x2 instances) | 410 each |
| pe_clkdiv / pe_decoder / pe_sync / glue | ~355 |

This sits under the ~16k logic-cell budget for the 6x4 tile allocation, but
with little margin. The dominant term is `pe_imem`, which is an inferred
register array; if the mapped IHP area is too large, the options are an SRAM
macro or reducing IMEM depth. Generic-cell counts are not 1:1 with IHP
standard cells, so the authoritative number is the LibreLane run.

### IHP hardening (LibreLane)

No local IHP hardening result is available yet. The official Tiny Tapeout
support tools were cloned to `/tmp/tt-support-tools`; local configuration
could not complete earlier because of missing dependencies, and the Docker
daemon socket remains inaccessible to the current user
(`permission denied ... /var/run/docker.sock`).

The repository's official workflow remains enabled in
`.github/workflows/gds.yaml` with `TinyTapeout/tt-gds-action@ttihp26b` and
`ihp-sg13g2`. Previous CI runs failed on the synthesis error above, which is
now fixed. No synthesis-to-GDS, timing, DRC, antenna, or 6x4-fit metrics are
reported until that flow completes.

| Metric | Result |
|---|---|
| Synthesis cells | 14,874 generic (Yosys 0.55, no PDK); IHP mapping pending CI |
| Sequential cells | ~6,634 generic FF cells; IHP mapping pending CI |
| Mapped area | Pending CI |
| IMEM implementation | Inferred register array (64x16); macro swap if area requires |
| Placement utilization | Pending CI |
| Routing/congestion | Pending CI |
| WNS/TNS | Pending CI |
| Critical path/Fmax | Pending CI |
| 6x4 fit | Not determined until CI hardening completes |
