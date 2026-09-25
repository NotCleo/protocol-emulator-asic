#!/usr/bin/env python3
"""Generate compact deterministic architectural reference traces."""
from __future__ import annotations
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.arch_sim import ProtocolEngine
from tools.assembler import Assembler

HEADER = "# cycle engine_tick pc instruction x y osr isr gpio_in gpio_out gpio_oe tx_level rx_level fifo_activity wait_state delay_count sideset_state running fault stall_reason"

def write_trace(name: str, source: str, cycles: int, *, sideset_count: int = 0,
                sideset_base: int = 0, initial_x: int = 0, initial_y: int = 0,
                initial_tx=None) -> None:
    engine = ProtocolEngine()
    engine.sideset_count = sideset_count
    engine.sideset_base = sideset_base
    engine.x = initial_x
    engine.y = initial_y
    if initial_tx:
        engine.feed_tx(initial_tx)
    engine.load_program(Assembler().assemble(source))
    engine.start()
    lines = [HEADER]
    for _ in range(cycles):
        row = engine.step()
        instruction = "----" if row["instruction"] is None else f"{row['instruction']:04x}"
        lines.append(
            f"{row['cycle']:04d} {row['cycle']:04d} {row['pc']:02d} {instruction} "
            f"{row['x']:04x} {row['y']:04x} {row['osr']:08x} {row['isr']:08x} "
            f"{row['gpio_in']:02x} {row['gpio_out']:02x} {row['gpio_oe']:02x} "
            f"{row['tx_level']} {row['rx_level']} {row['fifo_activity']} {int(row['wait_state'])} "
            f"{row['delay_count']:02d} {row['sideset_state']:02x} {int(row['running'])} "
            f"{int(row['fault'])} {row['stall_reason'] or '-'}"
        )
    (ROOT / "tests" / "golden" / f"{name}.trace").write_text("\n".join(lines) + "\n")

write_trace("gpio_toggle", "set pindirs, 1\nset pins, 1 [1]\nset pins, 0 [1]\njmp 1\n", 12)
write_trace("delay_test", "set pins, 1 [3]\nset pins, 0\n", 8)
write_trace("sideset_test", ".sideset 1\nset x, 7 side 1 [1]\nnop side 0\n", 6,
            sideset_count=1, sideset_base=1)
write_trace("jmp_test", "set x, 2\nloop: jmp x-- loop\nset y, 1\n", 8)
# pin_width pins the model to the RTL pin-write widths: MOV PINS drives all 8
# pins, SET PINS only the 5-pin immediate window, OUT PINS,1 only one pin.
write_trace("pin_width", "pull block\nmov pins, osr\nset pins, 31\nout pins, 1\njmp 0\n", 8,
            initial_tx=[0xFFFFFFFF])
