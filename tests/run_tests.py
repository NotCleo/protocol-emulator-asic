#!/usr/bin/env python3
"""Dependency-free Milestone 0 regression entry point.

The existing test modules are intentionally small assertion functions.  This
runner invokes them without pytest so the Python model remains usable in a
minimal RTL/synthesis environment.
"""

from __future__ import annotations

import importlib.util
import sys
from contextlib import contextmanager
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _install_pytest_compatibility() -> None:
    """Permit the legacy test module to load without installing pytest."""
    try:
        import pytest  # noqa: F401
    except ModuleNotFoundError:
        class _PytestCompat:
            @staticmethod
            @contextmanager
            def raises(exception):
                try:
                    yield
                except exception:
                    return
                raise AssertionError(f"expected {exception.__name__}")

        sys.modules["pytest"] = _PytestCompat()


def _load(name: str):
    path = ROOT / "tests" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    _install_pytest_compatibility()
    isa = _load("test_isa")
    assembler = _load("test_assembler")
    fifo = _load("test_fifo")
    arch = _load("test_arch_sim")
    uart = _load("test_uart")
    tests = [
        ("ISA", isa.test_major_classes_and_round_trips),
        ("ISA timing", isa.test_timing_layout),
        ("assembler", assembler.test_labels_and_all_milestone_zero_syntax),
        ("assembler invalid syntax", assembler.test_program_memory_and_immediate_errors),
        ("FIFO randomized 100000 operations", fifo.test_fifo_100000_randomized_operations),
        ("FIFO wraparound", fifo.test_fifo_simultaneous_push_pop_and_wraparound),
        ("WAIT", arch.test_wait_is_a_pc_stall_and_resumes_once),
        ("parameterized PC bounds", arch.test_parameterized_pc_faults_at_last_instruction),
        ("delay", arch.test_delay_executes_once_and_side_set_is_same_event),
        ("sideset", arch.test_delay_executes_once_and_side_set_is_same_event),
        ("shift", arch.test_pull_out_and_push_round_trip),
        ("gpio_toggle", arch.test_gpio_toggle_program_changes_output_and_direction),
        ("uart_tx", uart.test_preliminary_uart_tx_8n1_in_python_model),
    ]
    passed = 0
    failed = 0
    for label, test in tests:
        try:
            test()
        except Exception as exc:  # noqa: BLE001 - report every regression
            failed += 1
            print(f"FAIL {label}: {type(exc).__name__}: {exc}")
        else:
            passed += 1
            print(f"PASS {label}")
    print(f"TOTAL: {passed + failed} run, {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
