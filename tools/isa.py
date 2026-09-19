"""The V0 protocol-engine instruction set.

This module is intentionally the single source of truth for both the
assembler and the architectural model.  The RTL decoder in the next
milestone should mirror the bit fields documented here.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Optional


PROGRAM_WORDS = 64
INSTRUCTION_MASK = 0xFFFF
WORD_MASK = 0xFFFFFFFF


class Major(IntEnum):
    JMP = 0b000
    WAIT = 0b001
    IN = 0b010
    OUT = 0b011
    PUSH_PULL = 0b100
    MOV = 0b101
    EXT = 0b110
    SET = 0b111


class JmpCond(IntEnum):
    ALWAYS = 0
    X_ZERO = 1
    X_DEC = 2
    Y_ZERO = 3
    Y_DEC = 4
    PIN_HIGH = 5
    PIN_LOW = 6


class WaitCond(IntEnum):
    PIN_HIGH = 0
    PIN_LOW = 1
    RISING = 2
    FALLING = 3
    TX_NOT_EMPTY = 4
    RX_NOT_FULL = 5


class Endpoint(IntEnum):
    PINS = 0
    X = 1
    Y = 2
    OSR = 3
    ISR = 4
    NULL = 5


class SetDest(IntEnum):
    PINS = 0
    PINDIRS = 1
    X = 2
    Y = 3


class ExtOp(IntEnum):
    NOP = 0


@dataclass(frozen=True)
class DecodedInstruction:
    """Decoded fields.  Unused fields retain their harmless zero value."""

    word: int
    major: Major
    field_a: int = 0
    field_b: int = 0
    field_c: int = 0
    timing: int = 0


def _check_range(name: str, value: int, maximum: int) -> None:
    if not 0 <= value <= maximum:
        raise ValueError(f"{name}={value} is outside 0..{maximum}")


def encode_timing(side: int = 0, delay: int = 0, sideset_count: int = 0) -> int:
    """Pack the shared five-bit side-set/delay field.

    With zero side-set bits all five bits are delay.  With one or two side-set
    bits, the side value occupies the most significant bits.
    """

    _check_range("sideset_count", sideset_count, 2)
    _check_range("delay", delay, (1 << (5 - sideset_count)) - 1)
    _check_range("side", side, (1 << sideset_count) - 1 if sideset_count else 0)
    return (side << (5 - sideset_count)) | delay


def decode_timing(field: int, sideset_count: int) -> tuple[int, int]:
    _check_range("timing", field, 31)
    _check_range("sideset_count", sideset_count, 2)
    delay_mask = (1 << (5 - sideset_count)) - 1
    return field >> (5 - sideset_count), field & delay_mask


def encode_jmp(cond: JmpCond, target: int) -> int:
    _check_range("target", target, 63)
    return (Major.JMP << 13) | (int(cond) << 10) | (target << 4)


def encode_wait(cond: WaitCond, pin: int = 0, timing: int = 0) -> int:
    _check_range("pin", pin, 7)
    _check_range("timing", timing, 31)
    return (Major.WAIT << 13) | (int(cond) << 10) | (pin << 7) | timing


def encode_shift(major: Major, source_or_dest: Endpoint, count: int, timing: int = 0) -> int:
    if major not in (Major.IN, Major.OUT):
        raise ValueError("encode_shift only accepts IN or OUT")
    if count == 32:
        count_field = 0
    else:
        _check_range("count", count, 31)
        if count < 1:
            raise ValueError("count must be in 1..32")
        count_field = count
    _check_range("timing", timing, 31)
    return (major << 13) | (int(source_or_dest) << 10) | (count_field << 5) | timing


def decode_shift_count(field: int) -> int:
    return 32 if field == 0 else field


def encode_push_pull(is_push: bool, blocking: bool, timing: int = 0) -> int:
    _check_range("timing", timing, 31)
    return (Major.PUSH_PULL << 13) | (int(is_push) << 12) | (int(blocking) << 11) | timing


def encode_mov(destination: Endpoint, source: Endpoint, timing: int = 0) -> int:
    _check_range("destination", int(destination), 7)
    _check_range("source", int(source), 7)
    _check_range("timing", timing, 31)
    return (Major.MOV << 13) | (int(destination) << 10) | (int(source) << 7) | timing


def encode_ext(op: ExtOp = ExtOp.NOP, timing: int = 0) -> int:
    _check_range("timing", timing, 31)
    return (Major.EXT << 13) | (int(op) << 10) | timing


def encode_set(destination: SetDest, immediate: int, timing: int = 0) -> int:
    _check_range("immediate", immediate, 31)
    _check_range("timing", timing, 31)
    return (Major.SET << 13) | (int(destination) << 10) | (immediate << 5) | timing


def decode(word: int) -> DecodedInstruction:
    word &= INSTRUCTION_MASK
    major = Major((word >> 13) & 0x7)
    if major == Major.JMP:
        return DecodedInstruction(word, major, (word >> 10) & 0x7, (word >> 4) & 0x3F)
    if major == Major.WAIT:
        return DecodedInstruction(word, major, (word >> 10) & 0x7, (word >> 7) & 0x7, timing=word & 0x1F)
    if major in (Major.IN, Major.OUT):
        return DecodedInstruction(word, major, (word >> 10) & 0x7, (word >> 5) & 0x1F, timing=word & 0x1F)
    if major == Major.PUSH_PULL:
        return DecodedInstruction(word, major, (word >> 12) & 1, (word >> 11) & 1, timing=word & 0x1F)
    if major == Major.MOV:
        return DecodedInstruction(word, major, (word >> 10) & 0x7, (word >> 7) & 0x7, timing=word & 0x1F)
    if major == Major.EXT:
        return DecodedInstruction(word, major, (word >> 10) & 0x7, timing=word & 0x1F)
    return DecodedInstruction(word, major, (word >> 10) & 0x7, (word >> 5) & 0x1F, timing=word & 0x1F)


def format_instruction(word: int) -> str:
    """Return a compact deterministic representation useful in traces."""

    ins = decode(word)
    if ins.major == Major.JMP:
        return f"JMP {JmpCond(ins.field_a).name.lower()} {ins.field_b}"
    if ins.major == Major.WAIT:
        return f"WAIT {WaitCond(ins.field_a).name.lower()} {ins.field_b}"
    if ins.major in (Major.IN, Major.OUT):
        return f"{ins.major.name} {Endpoint(ins.field_a).name.lower()} {decode_shift_count(ins.field_b)}"
    if ins.major == Major.PUSH_PULL:
        return f"{'PUSH' if ins.field_a else 'PULL'} {'BLOCK' if ins.field_b else 'NOBLOCK'}"
    if ins.major == Major.MOV:
        return f"MOV {Endpoint(ins.field_a).name.lower()} {Endpoint(ins.field_b).name.lower()}"
    if ins.major == Major.EXT:
        return f"EXT {ExtOp(ins.field_a).name.lower()}"
    return f"SET {SetDest(ins.field_a).name.lower()} {ins.field_b}"


__all__ = [
    "PROGRAM_WORDS", "WORD_MASK", "Major", "JmpCond", "WaitCond",
    "Endpoint", "SetDest", "ExtOp", "DecodedInstruction", "encode_timing",
    "decode_timing", "encode_jmp", "encode_wait", "encode_shift",
    "decode_shift_count", "encode_push_pull", "encode_mov", "encode_ext",
    "encode_set", "decode", "format_instruction",
]
