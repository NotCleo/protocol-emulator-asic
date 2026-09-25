# V0 ISA (Milestone 0)

The instruction is 16 bits wide. Bits 15:13 select the major class:

| class | value | fields |
|---|---:|---|
| JMP | 000 | condition 12:10, target 9:4 |
| WAIT | 001 | condition 12:10, pin 9:7, timing 4:0 |
| IN | 010 | endpoint 12:10, count 9:5, timing 4:0 |
| OUT | 011 | endpoint 12:10, count 9:5, timing 4:0 |
| PUSH/PULL | 100 | push 12, blocking 11, timing 4:0 |
| MOV | 101 | destination 12:10, source 9:7, timing 4:0 |
| EXT | 110 | operation 12:10, timing 4:0 |
| SET | 111 | destination 12:10, immediate 9:5, timing 4:0 |

The shift count field uses value 0 for 32 bits and values 1..31 directly.
`JMP X--` and `JMP Y--` test nonzero and decrement only when the branch is
taken. `JMP pin_high` and `JMP pin_low` use GPIO pin 0; this is the simplest
deterministic choice because V0 has no separate JMP-pin configuration.

The timing field is interpreted using the configured side-set count:

* count 0: delay[4:0]
* count 1: side[0], delay[3:0]
* count 2: side[1:0], delay[2:0]

The assembler's `.sideset N` directive selects the interpretation used while
encoding subsequent instructions. The hardware configuration must match it.
`SET` immediates are five bits in V0, which is enough for the initial GPIO and
protocol programs; values above 31 are rejected.

`IN` with right shifting moves the newly sampled bits into the most significant
part of ISR, while left shifting appends them in the least significant part.
`OUT` with right shifting emits OSR's least significant bits first.

## Pin-write widths

Pin destinations write a bounded window starting at their configured base,
matching PIO semantics; they never zero-extend across the rest of the port.
This is normative for both the RTL and the Python model (`tools/arch_sim.py`):

| Instruction | Pins written (from base) |
|---|---|
| `SET PINS` / `SET PINDIRS` | exactly 5 (the immediate width) |
| `OUT PINS, n` | `min(n, 8)` (the shift count, clamped to the port) |
| `MOV PINS, src` | 8 (the whole mapped port) |
| side-set | `sideset_count` (0-2), applied after the instruction's own write |

An earlier model revision zero-extended `SET PINS` and `OUT PINS,n` to 8
pins, silently clearing neighboring pins the RTL left untouched. The
`pin_width` golden trace case and `test_pin_write_widths_match_rtl` pin the
corrected behavior so the divergence cannot reappear.
