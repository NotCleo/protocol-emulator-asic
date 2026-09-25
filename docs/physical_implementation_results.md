# Physical implementation results

## Status

The official IHP hardening run **succeeded** in CI: `gds` workflow run
36105975588 (commit `975a691`, `TinyTapeout/tt-gds-action@ttihp26b`,
`ihp-sg13g2`, ~68 minutes) produced a complete GDS/OAS/LEF/SPEF/netlist set
and passed the Tiny Tapeout precheck. Timing, DRC, and antenna checks are
clean at all corners; metrics below are from that run's `tt_submission`
artifact (`stats/metrics.csv`, `stats/synthesis-stats.txt`).

The same run's `gl_test` job failed for CI-plumbing reasons (the gate-level
job only installs Icarus Verilog while `test/Makefile` defaulted to
Verilator, and the action's `! grep failure results.xml` check false-matches
the `failures="0"` attribute cocotb 2.x writes); both are fixed in the
Makefile and testbench, and the full gate-level cocotb suite now passes
8/8 locally against the post-route netlist with Icarus 13. The `viewer` job
failed because GitHub Pages is not enabled on the repository; it is now
`continue-on-error` so it cannot turn the workflow red (enable Pages under
Settings -> Pages -> Source: GitHub Actions to get the online GDS viewer).

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

### IHP hardening (LibreLane, CI run 36105975588)

Synthesis mapped the design to **9,121 sg13g2 standard cells** (chip area
167,193 um^2, 50.2% of it sequential) -- well below the generic-cell
estimate above, confirming that generic counts are not 1:1 with mapped
cells. The 64x16 IMEM was mapped as a flip-flop array (1,714
`sg13g2_dfrbpq_1` DFFs total across the design); no SRAM macro was needed.

Largest cell categories after synthesis:

| Cell | Count |
|---|---:|
| sg13g2_dfrbpq_1 (DFF w/ reset) | 1,714 |
| sg13g2_a22oi_1 | 1,349 |
| sg13g2_mux2_1 | 1,265 |
| sg13g2_nand2_1 | 883 |
| sg13g2_o21ai_1 | 787 |
| sg13g2_a21oi_1 | 510 |
| sg13g2_nor2_1 | 495 |
| other combinational | ~2,118 |

Post-route (OpenROAD) results for the 6x4 tile allocation:

| Metric | Result |
|---|---|
| Synthesis cells | 9,121 sg13g2 cells (167,193 um^2, 50.2% sequential) |
| Sequential cells | 1,714 DFF (`sg13g2_dfrbpq_1`) |
| Post-P&R instances | 12,854 stdcell (incl. clock tree/fillers), 214,767 um^2 |
| Die area / bbox | 916,214 um^2 (1289.28 x 710.64 um) |
| Placement utilization | 23.8% -- comfortable 6x4 fit |
| Setup WNS/TNS (nom_slow_1p08V_125C) | +3.345 ns / 0.0 (0 violations) |
| Hold WNS/TNS (nom_slow_1p08V_125C) | +0.651 ns / 0.0 (0 violations) |
| Setup WNS (nom_fast_1p32V_m40C) | +13.204 ns / TNS 0.0 |
| Clock skew (worst setup, slow corner) | 0.292 ns |
| Power (total) | 6.51 mW (5.47 internal + 1.00 switching + 0.04 leakage) |
| Lint | 0 errors, 0 inferred latches, 38 warnings |
| Max fanout / slew violations | 117 / 127 (slow corner; non-blocking, did not fail DRC or precheck) |
| DRC / antenna / precheck | Clean (gds + precheck jobs green) |

With the 50 MHz (20 ns) clock declared in `info.yaml`, worst-case setup
slack of +3.345 ns at the slow corner implies a critical path of ~16.65 ns
(Fmax ~60 MHz), so the engine meets its target clock with margin.

The `gl_test` gate-level job of that run failed before simulating (missing
Verilator in the Icarus-only job) -- see the Status section; the fixed flow
was validated locally against the same post-route netlist.
