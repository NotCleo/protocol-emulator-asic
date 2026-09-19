#!/usr/bin/env python3
"""Compare a machine-readable RTL trace against a Python golden trace."""

from __future__ import annotations

import sys
from pathlib import Path


FIELDS = [
    "cycle", "engine_tick", "pc", "instruction", "x", "y", "osr", "isr",
    "gpio_in", "gpio_out", "gpio_oe", "tx_level", "rx_level",
    "fifo_activity", "wait_state", "delay_count", "sideset_state",
    "running", "fault", "stall_reason",
]


def rows(path: Path) -> list[dict[str, str]]:
    result = []
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        values = line.split()
        if len(values) != len(FIELDS):
            raise ValueError(f"{path}: expected {len(FIELDS)} fields, got {len(values)}")
        result.append(dict(zip(FIELDS, values)))
    return result


def compare(expected: Path, actual: Path) -> int:
    lhs, rhs = rows(expected), rows(actual)
    previous = None
    for index, (left, right) in enumerate(zip(lhs, rhs)):
        for field in FIELDS:
            if left[field].lower() != right[field].lower():
                print(f"Mismatch at trace row {index}, field: {field}")
                print(f"Python: {left[field]}")
                print(f"RTL:    {right[field]}")
                if previous is not None:
                    print(f"Previous instruction: {previous['instruction']} at PC {previous['pc']}")
                print(f"Current instruction: {left['instruction']} at PC {left['pc']}")
                return 1
        previous = left
    if len(lhs) != len(rhs):
        print(f"Mismatch in trace length: Python {len(lhs)}, RTL {len(rhs)}")
        return 1
    print(f"PASS RTL trace comparison ({len(lhs)} rows)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} PYTHON_TRACE RTL_TRACE")
    raise SystemExit(compare(Path(sys.argv[1]), Path(sys.argv[2])))
