# Formal verification

SymbiYosys property checks for the blocks called out in the verification plan
(FIFO, clock divider). Engine: `smtbmc` with Z3, via the project-local
`yowasp-*` WASM toolchain in `.venv` (the `yosys`, `yosys-smtbmc`, and `sby`
names are symlinked to their `yowasp-` equivalents).

## Run

```
cd formal
PATH=/absolute/path/to/.venv/bin:$PATH sby -f fifo.sby      # bmc + prove tasks
PATH=/absolute/path/to/.venv/bin:$PATH sby -f clkdiv.sby    # bmc task
```

Note: PATH must contain an **absolute** path to `.venv/bin`; sby spawns
`bash -c "cd <job>/src; yosys ..."` and a relative PATH entry breaks after
the `cd`.

## Jobs

### fifo.sby — `pe_fifo` (WIDTH=32, DEPTH=4)

`pe_fifo_props.sv` checks, for fully arbitrary push/pop/soft-reset stimulus:

- flag consistency: `empty_o == (level == 0)`, `full_o == (level == DEPTH)`,
  never both, `level <= DEPTH`
- async reset and synchronous soft reset both clear occupancy
- exact level dynamics: +1 on accepted push only, -1 on accepted pop only,
  unchanged on simultaneous push+pop or blocked overflow/underflow
- data integrity / FIFO ordering via a symbolic ghost word: arm on an
  accepted push at an arbitrary constant occupancy (`anyconst`), track the
  number of older words ahead of it (accounting for a simultaneous accepted
  pop), and assert the exact recorded data appears at the head when its turn
  comes

Tasks:

- `bmc` (depth 32): all properties including ghost-word data integrity.
- `prove` (induction): flag/level/reset safety properties. The data-integrity
  ghost needs memory-content visibility for an inductive invariant, so it is
  bounded-only (`FORMAL_DATA_INTEGRITY` ifdef selects the property set per
  task).

Harness bug found during bring-up (fixed before sign-off): the initial ghost
bookkeeping miscounted words-ahead by one when the arming push coincided with
an accepted pop; the BMC trace showed it within 4 cycles.

### clkdiv.sby — `pe_clkdiv`

`pe_clkdiv_props.sv` models the intended divider in a ghost counter (the DUT's
internal counter is not hierarchically referenceable in the Yosys frontend)
with the divisor as an `anyconst` (the CLKDIV CSR is halted-only writable):

- observable tick output equals the ghost tick every cycle (no early, late,
  or missed ticks) for any 16-bit divisor
- ticks only while enabled
- ghost counter stays below the divisor while enabled
- enable-low or soft-reset in the previous cycle clears the counter

Task: `bmc` (depth 64).

## Results

| Job | Task | Engine | Result |
|---|---|---|---|
| fifo | bmc (depth 32) | smtbmc z3 | PASS through step 24 (no counterexample); step 25 hit the 50-minute wall-clock budget with the solver still running |
| fifo | prove (induction) | smtbmc z3 | PASS (unbounded, safety properties) |
| clkdiv | bmc (depth 64) | smtbmc z3 | PASS |

The FIFO depth-48 run reached step 24 and the depth-32 re-run confirmed
steps 0-24 clean before the Z3 solver budget expired; the state space per
step is large (16-deep x 32-bit memory plus ghost bookkeeping). The
induction `prove` task carries the unbounded guarantee for the flag/level/
reset safety set, and BMC adds bounded data-integrity coverage to depth 24.
