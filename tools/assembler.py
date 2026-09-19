"""Small two-pass assembler for the V0 protocol-engine ISA."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

try:  # Works both as ``python tools/assembler.py`` and as a package import.
    from .isa import (
        Endpoint, ExtOp, JmpCond, Major, SetDest, WaitCond, encode_ext,
        encode_jmp, encode_mov, encode_push_pull, encode_set, encode_shift,
        encode_timing, encode_wait,
    )
except ImportError:  # pragma: no cover - convenience for direct invocation
    from isa import (
        Endpoint, ExtOp, JmpCond, Major, SetDest, WaitCond, encode_ext,
        encode_jmp, encode_mov, encode_push_pull, encode_set, encode_shift,
        encode_timing, encode_wait,
    )


class AssemblyError(ValueError):
    pass


@dataclass
class _SourceLine:
    address: int
    tokens: list[str]
    sideset_count: int
    line_number: int
    text: str


_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _number(token: str, what: str = "number") -> int:
    try:
        return int(token, 0)
    except ValueError as exc:
        raise AssemblyError(f"expected {what}, got {token!r}") from exc


def _symbol_or_number(token: str, symbols: dict[str, int], what: str) -> int:
    if token in symbols:
        return symbols[token]
    return _number(token, what)


def _tokens(text: str) -> list[str]:
    # Comments are deliberately simple and deterministic for .pasm files.
    text = re.split(r";|#|//", text, maxsplit=1)[0]
    text = text.replace(",", " ")
    return text.split()


def _endpoint(token: str) -> Endpoint:
    names = {name.lower(): value for name, value in Endpoint.__members__.items()}
    try:
        return names[token.lower()]
    except KeyError as exc:
        raise AssemblyError(f"unknown endpoint {token!r}") from exc


class Assembler:
    def __init__(self, sideset_count: int = 0, program_words: int = 64):
        if sideset_count not in (0, 1, 2):
            raise ValueError("sideset_count must be 0, 1, or 2")
        self.sideset_count = sideset_count
        self.program_words = program_words
        self.labels: dict[str, int] = {}

    def assemble_file(self, path: str | Path) -> list[int]:
        path = Path(path)
        return self.assemble(path.read_text(), filename=str(path))

    def assemble(self, source: str, filename: str = "<string>") -> list[int]:
        lines: list[_SourceLine] = []
        labels: dict[str, int] = {}
        address = 0
        current_sideset = self.sideset_count

        for line_number, original in enumerate(source.splitlines(), 1):
            raw = original.strip()
            if not raw:
                continue
            # A label may precede an instruction or directive.
            while True:
                label_match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", raw)
                if not label_match:
                    break
                label = label_match.group(1)
                if label in labels:
                    raise AssemblyError(f"{filename}:{line_number}: duplicate label {label}")
                labels[label] = address
                raw = label_match.group(2).strip()
                if not raw:
                    break
            if not raw:
                continue
            tokens = _tokens(raw)
            if not tokens:
                continue
            op = tokens[0].lower()
            if op.startswith("."):
                if op == ".sideset":
                    if len(tokens) != 2:
                        raise AssemblyError(f"{filename}:{line_number}: .sideset expects 0, 1, or 2")
                    current_sideset = _number(tokens[1], "side-set count")
                    if current_sideset not in (0, 1, 2):
                        raise AssemblyError(f"{filename}:{line_number}: side-set count must be 0, 1, or 2")
                elif op == ".org":
                    if len(tokens) != 2:
                        raise AssemblyError(f"{filename}:{line_number}: .org expects an address")
                    address = _number(tokens[1], "program address")
                    if not 0 <= address < self.program_words:
                        raise AssemblyError(f"{filename}:{line_number}: address outside program memory")
                elif op in (".program", ".end"):
                    pass
                elif op == ".word":
                    if len(tokens) != 2:
                        raise AssemblyError(f"{filename}:{line_number}: .word expects one value")
                    lines.append(_SourceLine(address, tokens, current_sideset, line_number, original))
                    address += 1
                else:
                    raise AssemblyError(f"{filename}:{line_number}: unknown directive {op}")
                continue
            lines.append(_SourceLine(address, tokens, current_sideset, line_number, original))
            address += 1

        if address > self.program_words:
            raise AssemblyError(f"{filename}: program exceeds {self.program_words} words")
        self.labels = labels
        words = [encode_ext(ExtOp.NOP)] * max(address, 1)
        for line in lines:
            try:
                words[line.address] = self._assemble_line(line.tokens, line.sideset_count)
            except (ValueError, KeyError, IndexError) as exc:
                if isinstance(exc, AssemblyError):
                    raise
                raise AssemblyError(f"{filename}:{line.line_number}: {line.text.strip()}: {exc}") from exc
        return words

    def _timing(self, tokens: list[str], sideset_count: int) -> tuple[list[str], int]:
        remaining: list[str] = []
        side = 0
        delay = 0
        index = 0
        while index < len(tokens):
            token = tokens[index].lower()
            if token == "side":
                if index + 1 >= len(tokens):
                    raise AssemblyError("side expects a value")
                side = _number(tokens[index + 1], "side-set value")
                index += 2
            elif token.startswith("[") and token.endswith("]"):
                delay = _number(token[1:-1], "delay")
                index += 1
            else:
                remaining.append(tokens[index])
                index += 1
        return remaining, encode_timing(side, delay, sideset_count)

    def _assemble_line(self, original: list[str], sideset_count: int) -> int:
        op = original[0].lower()
        tokens, timing = self._timing(original[1:], sideset_count)

        if op == ".word":
            value = _number(tokens[0], "word")
            if not 0 <= value <= 0xFFFF:
                raise AssemblyError(".word must fit in 16 bits")
            return value
        if op in ("nop", "ext"):
            if op == "nop":
                if tokens:
                    raise AssemblyError("nop takes no operands")
                return encode_ext(ExtOp.NOP, timing)
            if len(tokens) != 1 or tokens[0].lower() != "nop":
                raise AssemblyError("only ext nop is implemented")
            return encode_ext(ExtOp.NOP, timing)
        if op == "jmp":
            if len(tokens) == 1:
                cond, target = JmpCond.ALWAYS, tokens[0]
            elif len(tokens) == 2:
                condition = tokens[0].lower()
                cond_map = {
                    "x--": JmpCond.X_DEC, "x==0": JmpCond.X_ZERO,
                    "y--": JmpCond.Y_DEC, "y==0": JmpCond.Y_ZERO,
                    "pin_high": JmpCond.PIN_HIGH, "pin_low": JmpCond.PIN_LOW,
                }
                if condition not in cond_map:
                    raise AssemblyError(f"unknown JMP condition {tokens[0]!r}")
                cond, target = cond_map[condition], tokens[1]
            else:
                raise AssemblyError("JMP expects target or condition,target")
            if timing:
                raise AssemblyError("JMP does not have side-set or delay in V0")
            return encode_jmp(cond, _symbol_or_number(target, self.labels, "jump target"))
        if op == "wait":
            if len(tokens) == 1:
                cond_name, pin = tokens[0].lower(), 0
            elif len(tokens) == 2:
                cond_name, pin = tokens[0].lower(), _number(tokens[1], "pin")
            else:
                raise AssemblyError("WAIT expects condition[, pin]")
            cond_map = {
                "pin_high": WaitCond.PIN_HIGH, "pin_low": WaitCond.PIN_LOW,
                "rising": WaitCond.RISING, "falling": WaitCond.FALLING,
                "tx_not_empty": WaitCond.TX_NOT_EMPTY, "rx_not_full": WaitCond.RX_NOT_FULL,
            }
            if cond_name not in cond_map:
                raise AssemblyError(f"unknown WAIT condition {cond_name!r}")
            return encode_wait(cond_map[cond_name], pin, timing)
        if op in ("in", "out"):
            if len(tokens) != 2:
                raise AssemblyError(f"{op.upper()} expects source/destination,count")
            endpoint = _endpoint(tokens[0])
            count = _number(tokens[1], "shift count")
            if op == "in":
                return encode_shift(Major.IN, endpoint, count, timing)
            return encode_shift(Major.OUT, endpoint, count, timing)
        if op in ("pull", "push"):
            if len(tokens) > 1:
                raise AssemblyError(f"{op.upper()} expects block or noblock")
            mode = tokens[0].lower() if tokens else "block"
            if mode not in ("block", "noblock"):
                raise AssemblyError(f"unknown {op.upper()} mode {mode!r}")
            return encode_push_pull(op == "push", mode == "block", timing)
        if op == "mov":
            if len(tokens) != 2:
                raise AssemblyError("MOV expects destination,source")
            return encode_mov(_endpoint(tokens[0]), _endpoint(tokens[1]), timing)
        if op == "set":
            if len(tokens) != 2:
                raise AssemblyError("SET expects destination,immediate")
            dest_map = {"pins": SetDest.PINS, "pindirs": SetDest.PINDIRS,
                        "x": SetDest.X, "y": SetDest.Y}
            try:
                dest = dest_map[tokens[0].lower()]
            except KeyError as exc:
                raise AssemblyError(f"unknown SET destination {tokens[0]!r}") from exc
            return encode_set(dest, _number(tokens[1], "immediate"), timing)
        raise AssemblyError(f"unknown instruction {op!r}")


def assemble(source: str, sideset_count: int = 0) -> list[int]:
    return Assembler(sideset_count=sideset_count).assemble(source)


def assemble_file(path: str | Path, sideset_count: int = 0) -> list[int]:
    return Assembler(sideset_count=sideset_count).assemble_file(path)


__all__ = ["Assembler", "AssemblyError", "assemble", "assemble_file"]
