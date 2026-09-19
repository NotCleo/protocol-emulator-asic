#!/usr/bin/env python3
"""Seeded constrained Python-vs-RTL execution-engine differential test."""
from __future__ import annotations
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.arch_sim import ProtocolEngine
from tools.isa import (Endpoint, ExtOp, JmpCond, WaitCond, Major, SetDest,
                       encode_ext, encode_jmp, encode_mov, encode_push_pull,
                       encode_set, encode_shift, encode_wait, encode_timing)
from tests.compare_rtl_trace import compare

SEED = 0x51A5EED
CASES = 100
WORDS = 8
CYCLES = 100
OUT_DIR = ROOT / "tests" / "generated_random"
INCLUDE = ROOT / "tests" / "random_programs.svh"


def trace_text(rows: list[dict[str, object]]) -> str:
    lines = ["# cycle engine_tick pc instruction x y osr isr gpio_in gpio_out gpio_oe tx_level rx_level fifo_activity wait_state delay_count sideset_state running fault stall_reason"]
    for row in rows:
        ins = "----" if row["instruction"] is None else f"{int(row['instruction']):04x}"
        lines.append(
            f"{int(row['cycle']):04d} {int(row['cycle']):04d} {int(row['pc']):02d} {ins} "
            f"{int(row['x']):04x} {int(row['y']):04x} {int(row['osr']):08x} {int(row['isr']):08x} "
            f"{int(row['gpio_in']):02x} {int(row['gpio_out']):02x} {int(row['gpio_oe']):02x} "
            f"{int(row['tx_level'])} {int(row['rx_level'])} {row['fifo_activity']} {int(bool(row['wait_state']))} "
            f"{int(row['delay_count']):02d} {int(row['sideset_state']):02x} "
            f"{int(bool(row['running']))} {int(bool(row['fault']))} {row['stall_reason'] or '-'}"
        )
    return "\n".join(lines) + "\n"


def word(r: random.Random, sideset_count: int) -> int:
    timing = encode_timing(
        side=r.randrange(1 << sideset_count) if sideset_count else 0,
        delay=r.randrange(1 << (5 - sideset_count)),
        sideset_count=sideset_count,
    )
    choice = r.randrange(10)
    if choice == 0:
        return encode_set(SetDest.X, r.randrange(32), timing)
    if choice == 1:
        return encode_set(SetDest.Y, r.randrange(32), timing)
    if choice == 2:
        return encode_set(SetDest.PINS, r.randrange(32), timing)
    if choice == 3:
        return encode_set(SetDest.PINDIRS, r.randrange(32), timing)
    if choice == 4:
        return encode_ext(ExtOp.NOP, timing)
    if choice == 5:
        return encode_shift(Major.IN, r.choice(list(Endpoint)), r.choice([1, 2, 8, 16, 31, 32]), timing)
    if choice == 6:
        return encode_shift(Major.OUT, r.choice(list(Endpoint)), r.choice([1, 2, 8, 16, 31, 32]), timing)
    if choice == 7:
        return encode_mov(r.choice(list(Endpoint)), r.choice(list(Endpoint)), timing)
    if choice == 8:
        # Nonblocking PULL is always progress-making, while PUSH is allowed
        # to block once RX becomes full so stall semantics are exercised.
        return encode_push_pull(r.choice([False, True]), False if r.random() < 0.75 else True, timing)
    if choice == 9:
        branch = r.choice(list(JmpCond))
        if branch in (JmpCond.PIN_HIGH,):
            branch = JmpCond.PIN_LOW
        return encode_jmp(branch, r.randrange(WORDS))
    return encode_wait(WaitCond.PIN_LOW, 0, timing)


def make_case(seed: int):
    r = random.Random(seed)
    sideset_count = r.randrange(3)
    sideset_base = r.randrange(8)
    set_base = r.randrange(8)
    in_base = r.randrange(8)
    out_base = r.randrange(8)
    shift_cfg = r.choice([0, 1, 2, 3])
    program = [word(r, sideset_count) for _ in range(WORDS)]
    # Force every case to contain at least one instance of each datapath class
    # while retaining random surrounding control flow.
    program[0] = encode_set(SetDest.X, r.randrange(32), encode_timing(delay=0, sideset_count=sideset_count))
    program[1] = encode_shift(Major.IN, Endpoint.PINS, 8, encode_timing(sideset_count=sideset_count))
    program[2] = encode_shift(Major.OUT, Endpoint.PINS, 8, encode_timing(sideset_count=sideset_count))
    program[3] = encode_push_pull(False, False, encode_timing(sideset_count=sideset_count))
    program[4] = encode_push_pull(True, False, encode_timing(sideset_count=sideset_count))
    program[5] = encode_wait(WaitCond.PIN_LOW, 0, encode_timing(sideset_count=sideset_count))
    program[6] = encode_mov(Endpoint.Y, Endpoint.ISR, encode_timing(sideset_count=sideset_count))
    program[7] = encode_jmp(JmpCond.ALWAYS, 0)
    return program, (sideset_count, sideset_base, set_base, in_base, out_base, shift_cfg)


def main() -> int:
    OUT_DIR.mkdir(exist_ok=True)
    cases = []
    for index in range(CASES):
        program, cfg = make_case(SEED + index * 0x9E3779B9)
        cases.append((program, cfg))
        engine = ProtocolEngine()
        sideset_count, sideset_base, set_base, in_base, out_base, shift_cfg = cfg
        engine.sideset_count = sideset_count
        engine.sideset_base = sideset_base
        engine.set_base = set_base
        engine.in_base = in_base
        engine.out_base = out_base
        engine.in_shift_right = bool(shift_cfg & 1)
        engine.out_shift_right = bool(shift_cfg & 2)
        engine.load_program(program)
        engine.start()
        rows = [engine.step(0) for _ in range(CYCLES)]
        (OUT_DIR / f"golden_{index:03d}.trace").write_text(trace_text(rows))

    with INCLUDE.open("w") as f:
        f.write(f"localparam integer RANDOM_CASES = {CASES};\n")
        f.write(f"localparam integer RANDOM_WORDS = {WORDS};\n")
        f.write(f"localparam integer RANDOM_CYCLES = {CYCLES};\n")
        f.write("logic [15:0] random_programs [0:RANDOM_CASES-1][0:RANDOM_WORDS-1];\n")
        f.write("integer random_side_cfg [0:RANDOM_CASES-1];\n")
        f.write("integer random_set_cfg [0:RANDOM_CASES-1];\n")
        f.write("integer random_in_cfg [0:RANDOM_CASES-1];\n")
        f.write("integer random_out_cfg [0:RANDOM_CASES-1];\n")
        f.write("integer random_shift_cfg [0:RANDOM_CASES-1];\n")
        f.write("initial begin\n")
        for i, (program, cfg) in enumerate(cases):
            s, sb, xb, ib, ob, sh = cfg
            f.write(f"  random_side_cfg[{i}] = {sb | (s << 8)}; random_set_cfg[{i}] = {xb}; random_in_cfg[{i}] = {ib}; random_out_cfg[{i}] = {ob}; random_shift_cfg[{i}] = {sh};\n")
            for j, value in enumerate(program):
                f.write(f"  random_programs[{i}][{j}] = 16'h{value:04x};\n")
        f.write("end\n")

    compile_cmd = ["verilator", "--binary", "--timing", "--Wno-fatal",
                   "--top-module", "tb_random_diff", "-Itests", "-Mdir", "sim/obj_random",
                   "-o", "tb_random_diff", "tests/tb_random_diff.sv"]
    compile_cmd += sorted(str(p) for p in (ROOT / "src" / "engine").glob("*.sv"))
    result = subprocess.run(compile_cmd, cwd=ROOT)
    if result.returncode:
        return result.returncode
    result = subprocess.run([str(ROOT / "sim/obj_random/tb_random_diff")], cwd=ROOT)
    if result.returncode:
        return result.returncode
    mismatches = 0
    for i in range(CASES):
        mismatches += compare(OUT_DIR / f"golden_{i:03d}.trace", ROOT / f"sim/random_{i:03d}.trace")
    if mismatches:
        print(f"FAIL randomized differential: seed base 0x{SEED:x}, mismatches={mismatches}")
        return 1
    print(f"PASS randomized differential: {CASES} programs x {CYCLES} engine ticks, seed base 0x{SEED:x}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
