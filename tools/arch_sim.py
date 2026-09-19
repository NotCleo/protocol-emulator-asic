"""Reference architectural model for the V0 programmable I/O engine.

One call to :meth:`ProtocolEngine.step` represents one engine-ce event.  The
model deliberately has no protocol-specific behavior; UART, SPI, and I2C are
ordinary programs using the instructions in :mod:`isa`.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Optional

try:
    from .isa import (
        Endpoint, ExtOp, JmpCond, Major, SetDest, WaitCond, WORD_MASK,
        PROGRAM_WORDS, decode, decode_shift_count, decode_timing,
        format_instruction,
    )
except ImportError:  # pragma: no cover
    from isa import (
        Endpoint, ExtOp, JmpCond, Major, SetDest, WaitCond, WORD_MASK,
        PROGRAM_WORDS, decode, decode_shift_count, decode_timing,
        format_instruction,
    )


class Fifo:
    """A small bounded FIFO with deterministic non-destructive failures."""

    def __init__(self, depth: int = 4):
        if depth < 1:
            raise ValueError("FIFO depth must be positive")
        self.depth = depth
        self._data: list[int] = []

    @property
    def level(self) -> int:
        return len(self._data)

    @property
    def empty(self) -> bool:
        return not self._data

    @property
    def full(self) -> bool:
        return len(self._data) >= self.depth

    @property
    def contents(self) -> list[int]:
        return list(self._data)

    def clear(self) -> None:
        self._data.clear()

    def push(self, value: int) -> bool:
        if self.full:
            return False
        self._data.append(value & WORD_MASK)
        return True

    def pop(self) -> Optional[int]:
        if self.empty:
            return None
        return self._data.pop(0)

    def push_pop(self, push_value: int | None = None, do_pop: bool = False) -> Optional[int]:
        """Perform a simultaneous operation, useful for FIFO unit tests.

        A pop frees a slot in the same operation, so push+pop is accepted even
        when the FIFO was full.  The returned value is the popped word.
        """

        popped = self._data.pop(0) if do_pop and self._data else None
        if push_value is not None:
            if self.full:
                if popped is not None:
                    # This case cannot occur after the pop above, but keeps
                    # the behavior obvious if this implementation changes.
                    raise AssertionError("FIFO simultaneous operation invariant")
                raise OverflowError("push into full FIFO")
            self._data.append(push_value & WORD_MASK)
        return popped


@dataclass
class TraceEntry:
    cycle: int
    pc: int
    instruction: Optional[int]
    x: int
    y: int
    osr: int
    isr: int
    gpio_in: int
    gpio_out: int
    gpio_oe: int
    tx_level: int
    rx_level: int
    fifo_activity: str
    wait_state: bool
    delay_count: int
    sideset_state: int
    running: bool
    fault: bool
    stall_reason: str
    pc_before: int
    executed: bool

    def as_dict(self) -> dict[str, object]:
        return {
            "cycle": self.cycle,
            "pc": self.pc,
            "instruction": self.instruction,
            "instruction_text": format_instruction(self.instruction) if self.instruction is not None else None,
            "x": self.x,
            "y": self.y,
            "osr": self.osr,
            "isr": self.isr,
            "gpio_in": self.gpio_in,
            "gpio_out": self.gpio_out,
            "gpio_oe": self.gpio_oe,
            "tx_level": self.tx_level,
            "rx_level": self.rx_level,
            "fifo_activity": self.fifo_activity,
            "wait_state": self.wait_state,
            "delay_count": self.delay_count,
            "sideset_state": self.sideset_state,
            "running": self.running,
            "fault": self.fault,
            "stall_reason": self.stall_reason,
            "pc_before": self.pc_before,
            "executed": self.executed,
        }


class ProtocolEngine:
    """Golden model with parameterized instruction depth and two four-word FIFOs."""

    def __init__(self, program_words: int = PROGRAM_WORDS, fifo_depth: int = 4):
        if program_words < 1:
            raise ValueError("program memory must contain at least one word")
        self.program_words = program_words
        self.tx_fifo = Fifo(fifo_depth)
        self.rx_fifo = Fifo(fifo_depth)
        self.program = [0] * program_words

        # Host-visible configuration registers modeled directly.
        self.start_pc = 0
        self.clkdiv = 1
        self.out_base = 0
        self.in_base = 0
        self.set_base = 0
        self.sideset_base = 0
        self.sideset_count = 0
        self.in_shift_right = False
        self.out_shift_right = True

        self.gpio_in = 0
        self._previous_sample = 0
        self.rising_edge = 0
        self.falling_edge = 0
        self.trace: list[dict[str, object]] = []
        self.cycle = 0
        self.reset()

    def reset(self, clear_program: bool = False) -> None:
        if clear_program:
            self.program = [0] * self.program_words
        self.pc = 0
        self.x = 0
        self.y = 0
        self.osr = 0
        self.isr = 0
        self.osr_count = 0
        self.isr_count = 0
        self.delay_count = 0
        self.gpio_out = 0
        self.gpio_oe = 0
        self.gpio_in &= 0xFF
        self._previous_sample = self.gpio_in
        self.rising_edge = 0
        self.falling_edge = 0
        self.running = False
        self.fault = False
        self.last_stall_reason = ""
        self.fifo_activity = "-"
        self.wait_state = False
        self.sideset_event = 0
        self.cycle = 0
        self.trace.clear()
        self.tx_fifo.clear()
        self.rx_fifo.clear()

    def load_program(self, words: Iterable[int], start: int = 0) -> None:
        words = list(words)
        if not 0 <= start < self.program_words or start + len(words) > self.program_words:
            raise ValueError("program does not fit in program memory")
        for offset, word in enumerate(words):
            self.program[start + offset] = word & 0xFFFF

    def start(self, pc: Optional[int] = None) -> None:
        if pc is not None:
            if not 0 <= pc < self.program_words:
                raise ValueError("start PC outside program memory")
            self.start_pc = pc
        self.pc = self.start_pc
        self.running = True
        self.fault = False

    def halt(self) -> None:
        self.running = False

    def feed_tx(self, words: Iterable[int]) -> int:
        pushed = 0
        for word in words:
            if not self.tx_fifo.push(word):
                break
            pushed += 1
        return pushed

    def read_rx(self) -> Optional[int]:
        return self.rx_fifo.pop()

    @property
    def status(self) -> dict[str, bool]:
        return {
            "TX_EMPTY": self.tx_fifo.empty,
            "TX_FULL": self.tx_fifo.full,
            "RX_EMPTY": self.rx_fifo.empty,
            "RX_FULL": self.rx_fifo.full,
            "WAITING": self.last_stall_reason in {"wait", "pull_block", "push_block", "delay"},
            "RUNNING": self.running,
            "FAULT": self.fault,
        }

    def set_gpio_in(self, value: int) -> None:
        self.gpio_in = value & 0xFF

    def _mapped_read(self, value: int, base: int, count: int = 8) -> int:
        result = 0
        for bit in range(count):
            pin = base + bit
            if pin < 8 and (value & (1 << pin)):
                result |= 1 << bit
        return result

    def _mapped_write(self, current: int, value: int, base: int, count: int = 8) -> int:
        result = current
        for bit in range(count):
            pin = base + bit
            if pin >= 8:
                continue
            mask = 1 << pin
            result = (result | mask) if (value & (1 << bit)) else (result & ~mask)
        return result & 0xFF

    def _apply_side_set(self, timing: int) -> int:
        side, delay = decode_timing(timing, self.sideset_count)
        if self.sideset_count:
            self.gpio_out = self._mapped_write(
                self.gpio_out, side, self.sideset_base, self.sideset_count
            )
        return delay

    def _shift_in(self, value: int, count: int) -> None:
        mask = (1 << count) - 1 if count < 32 else WORD_MASK
        value &= mask
        if self.in_shift_right:
            self.isr = ((self.isr >> count) | (value << (32 - count))) & WORD_MASK
        else:
            self.isr = ((self.isr << count) | value) & WORD_MASK
        self.isr_count = min(32, self.isr_count + count)

    def _shift_out(self, count: int) -> int:
        mask = (1 << count) - 1 if count < 32 else WORD_MASK
        if self.out_shift_right:
            value = self.osr & mask
            self.osr = (self.osr >> count) & WORD_MASK
        else:
            value = (self.osr >> (32 - count)) & mask
            self.osr = (self.osr << count) & WORD_MASK
        self.osr_count = max(0, self.osr_count - count)
        return value

    def _pin_is_high(self, pin: int) -> bool:
        return 0 <= pin < 8 and bool(self.gpio_in & (1 << pin))

    def _wait_condition(self, condition: WaitCond, pin: int) -> bool:
        if condition == WaitCond.PIN_HIGH:
            return self._pin_is_high(pin)
        if condition == WaitCond.PIN_LOW:
            return not self._pin_is_high(pin)
        if condition == WaitCond.RISING:
            return bool(self.rising_edge & (1 << pin))
        if condition == WaitCond.FALLING:
            return bool(self.falling_edge & (1 << pin))
        if condition == WaitCond.TX_NOT_EMPTY:
            return not self.tx_fifo.empty
        if condition == WaitCond.RX_NOT_FULL:
            return not self.rx_fifo.full
        return False

    def _source_value(self, endpoint: Endpoint) -> int:
        if endpoint == Endpoint.PINS:
            return self._mapped_read(self.gpio_in, self.in_base)
        if endpoint == Endpoint.X:
            return self.x
        if endpoint == Endpoint.Y:
            return self.y
        if endpoint == Endpoint.OSR:
            return self.osr
        if endpoint == Endpoint.ISR:
            return self.isr
        if endpoint == Endpoint.NULL:
            return 0
        raise ValueError(f"reserved endpoint {endpoint}")

    def _write_endpoint(self, endpoint: Endpoint, value: int) -> None:
        value &= WORD_MASK
        if endpoint == Endpoint.PINS:
            self.gpio_out = self._mapped_write(self.gpio_out, value, self.out_base)
        elif endpoint == Endpoint.X:
            self.x = value & 0xFFFF
        elif endpoint == Endpoint.Y:
            self.y = value & 0xFFFF
        elif endpoint == Endpoint.OSR:
            self.osr = value
            self.osr_count = 32
        elif endpoint == Endpoint.ISR:
            self.isr = value
            self.isr_count = 32
        elif endpoint == Endpoint.NULL:
            pass
        else:
            raise ValueError(f"reserved endpoint {endpoint}")

    def _complete_timed_instruction(self, timing: int) -> None:
        side, delay = decode_timing(timing, self.sideset_count)
        self.sideset_event = side if self.sideset_count else 0
        self.delay_count = self._apply_side_set(timing)

    def step(self, gpio_in: Optional[int] = None) -> dict[str, object]:
        if gpio_in is not None:
            self.gpio_in = gpio_in & 0xFF
        current = self.gpio_in & 0xFF
        self.rising_edge = current & (~self._previous_sample & 0xFF)
        self.falling_edge = (~current & 0xFF) & self._previous_sample
        self._previous_sample = current
        self.cycle += 1

        pc_before = self.pc
        instruction: Optional[int] = None
        executed = False
        reason = ""
        self.fifo_activity = "-"
        self.wait_state = False
        self.sideset_event = 0

        if not self.running:
            reason = "halted"
        elif self.fault:
            reason = "fault"
        elif self.delay_count:
            self.delay_count -= 1
            reason = "delay"
        else:
            instruction = self.program[self.pc]
            ins = decode(instruction)
            next_pc = self.pc + 1
            try:
                if ins.major == Major.JMP:
                    cond = JmpCond(ins.field_a)
                    take = False
                    if cond == JmpCond.ALWAYS:
                        take = True
                    elif cond == JmpCond.X_ZERO:
                        take = self.x == 0
                    elif cond == JmpCond.X_DEC:
                        take = self.x != 0
                        if take:
                            self.x = (self.x - 1) & 0xFFFF
                    elif cond == JmpCond.Y_ZERO:
                        take = self.y == 0
                    elif cond == JmpCond.Y_DEC:
                        take = self.y != 0
                        if take:
                            self.y = (self.y - 1) & 0xFFFF
                    elif cond == JmpCond.PIN_HIGH:
                        take = self._pin_is_high(0)
                    elif cond == JmpCond.PIN_LOW:
                        take = not self._pin_is_high(0)
                    next_pc = ins.field_b if take else next_pc
                    if next_pc >= self.program_words:
                        self.pc = self.program_words - 1
                        self.fault = True
                        self.running = False
                    else:
                        self.pc = next_pc
                    executed = True
                elif ins.major == Major.WAIT:
                    condition = WaitCond(ins.field_a)
                    if self._wait_condition(condition, ins.field_b):
                        self._complete_timed_instruction(ins.timing)
                        if next_pc >= self.program_words:
                            self.pc = self.program_words - 1
                            self.fault = True
                            self.running = False
                        else:
                            self.pc = next_pc
                        executed = True
                    else:
                        reason = "wait"
                        self.wait_state = True
                elif ins.major == Major.IN:
                    endpoint = Endpoint(ins.field_a)
                    count = decode_shift_count(ins.field_b)
                    self._shift_in(self._source_value(endpoint), count)
                    self._complete_timed_instruction(ins.timing)
                    if next_pc >= self.program_words:
                        self.pc = self.program_words - 1
                        self.fault = True
                        self.running = False
                    else:
                        self.pc = next_pc
                    executed = True
                elif ins.major == Major.OUT:
                    endpoint = Endpoint(ins.field_a)
                    count = decode_shift_count(ins.field_b)
                    self._write_endpoint(endpoint, self._shift_out(count))
                    self._complete_timed_instruction(ins.timing)
                    if next_pc >= self.program_words:
                        self.pc = self.program_words - 1
                        self.fault = True
                        self.running = False
                    else:
                        self.pc = next_pc
                    executed = True
                elif ins.major == Major.PUSH_PULL:
                    is_push, blocking = bool(ins.field_a), bool(ins.field_b)
                    if is_push:
                        if self.rx_fifo.full and blocking:
                            reason = "push_block"
                            self.fifo_activity = "push_block"
                        else:
                            if not self.rx_fifo.full:
                                self.rx_fifo.push(self.isr)
                                self.isr_count = 0
                                self.fifo_activity = "push"
                            self._complete_timed_instruction(ins.timing)
                            if next_pc >= self.program_words:
                                self.pc = self.program_words - 1
                                self.fault = True
                                self.running = False
                            else:
                                self.pc = next_pc
                            executed = True
                    else:
                        if self.tx_fifo.empty and blocking:
                            reason = "pull_block"
                            self.fifo_activity = "pull_block"
                        else:
                            word = self.tx_fifo.pop()
                            if word is not None:
                                self.osr = word
                                self.osr_count = 32
                                self.fifo_activity = "pull"
                            self._complete_timed_instruction(ins.timing)
                            if next_pc >= self.program_words:
                                self.pc = self.program_words - 1
                                self.fault = True
                                self.running = False
                            else:
                                self.pc = next_pc
                            executed = True
                elif ins.major == Major.MOV:
                    destination, source = Endpoint(ins.field_a), Endpoint(ins.field_b)
                    self._write_endpoint(destination, self._source_value(source))
                    self._complete_timed_instruction(ins.timing)
                    if next_pc >= self.program_words:
                        self.pc = self.program_words - 1
                        self.fault = True
                        self.running = False
                    else:
                        self.pc = next_pc
                    executed = True
                elif ins.major == Major.EXT:
                    if ExtOp(ins.field_a) != ExtOp.NOP:
                        raise ValueError("unimplemented EXT operation")
                    self._complete_timed_instruction(ins.timing)
                    if next_pc >= self.program_words:
                        self.pc = self.program_words - 1
                        self.fault = True
                        self.running = False
                    else:
                        self.pc = next_pc
                    executed = True
                elif ins.major == Major.SET:
                    destination = SetDest(ins.field_a)
                    immediate = ins.field_b
                    if destination == SetDest.X:
                        self.x = immediate
                    elif destination == SetDest.Y:
                        self.y = immediate
                    elif destination == SetDest.PINS:
                        self.gpio_out = self._mapped_write(self.gpio_out, immediate, self.set_base)
                    elif destination == SetDest.PINDIRS:
                        self.gpio_oe = self._mapped_write(self.gpio_oe, immediate, self.set_base)
                    self._complete_timed_instruction(ins.timing)
                    if next_pc >= self.program_words:
                        self.pc = self.program_words - 1
                        self.fault = True
                        self.running = False
                    else:
                        self.pc = next_pc
                    executed = True
            except (ValueError, IndexError) as exc:
                self.fault = True
                self.running = False
                reason = f"fault:{exc}"

        self.last_stall_reason = reason
        entry = TraceEntry(
            cycle=self.cycle,
            pc=self.pc,
            instruction=instruction,
            x=self.x,
            y=self.y,
            osr=self.osr,
            isr=self.isr,
            gpio_in=self.gpio_in,
            gpio_out=self.gpio_out,
            gpio_oe=self.gpio_oe,
            tx_level=self.tx_fifo.level,
            rx_level=self.rx_fifo.level,
            fifo_activity=self.fifo_activity,
            wait_state=self.wait_state,
            delay_count=self.delay_count,
            sideset_state=self.sideset_event,
            running=self.running,
            fault=self.fault,
            stall_reason=reason,
            pc_before=pc_before,
            executed=executed,
        ).as_dict()
        self.trace.append(entry)
        return entry

    def run(self, cycles: int, start: bool = True) -> list[dict[str, object]]:
        if start:
            self.start()
        return [self.step() for _ in range(cycles)]


# Short alias useful in scripts and tests.
ArchSim = ProtocolEngine


__all__ = ["Fifo", "TraceEntry", "ProtocolEngine", "ArchSim"]
