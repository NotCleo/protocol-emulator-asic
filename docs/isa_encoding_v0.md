# V0 ISA encoding checkpoint

This is the Milestone 0 checkpoint consumed by the assembler and Python golden
model before RTL implementation. The major opcode is bits `[15:13]`:

| major | value | encoding |
|---|---:|---|
| JMP | `000` | condition `[12:10]`, target `[9:4]`, reserved `[3:0]` |
| WAIT | `001` | condition `[12:10]`, pin `[9:7]`, timing `[4:0]` |
| IN | `010` | endpoint `[12:10]`, count `[9:5]`, timing `[4:0]` |
| OUT | `011` | endpoint `[12:10]`, count `[9:5]`, timing `[4:0]` |
| PUSH/PULL | `100` | push `[12]`, blocking `[11]`, timing `[4:0]` |
| MOV | `101` | destination `[12:10]`, source `[9:7]`, timing `[4:0]` |
| EXT | `110` | operation `[12:10]`, timing `[4:0]` |
| SET | `111` | destination `[12:10]`, immediate `[9:5]`, timing `[4:0]` |

The count field encodes 32 as zero and 1..31 directly. The timing field is
delay `[4:0]` for zero side-set bits, `side[0]` plus delay `[3:0]` for one,
and `side[1:0]` plus delay `[2:0]` for two. V0 SET immediates are five bits.

For Milestone 1, only SET, JMP, and EXT NOP are legal in RTL. The decoder
still uses this complete field map so later RTL milestones cannot silently
invent a second encoding.

The existing Python files are the executable source of truth; this document
records the checkpoint for review and differential-test trace generation.
