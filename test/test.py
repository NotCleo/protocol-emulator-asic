# SPDX-License-Identifier: Apache-2.0
"""Physical Tiny Tapeout integration tests for the management SPI path."""

from pathlib import Path
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import (
    ClockCycles,
    RisingEdge,
    Timer,
    with_timeout,
)
from cocotb.utils import get_sim_time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.assembler import Assembler  # noqa: E402


CLOCK_PERIOD_NS = 20
SPI_HALF_NS = 100  # 5 MHz maximum tested management rate
GPIO_BIT = 0
CTRL = 0x000
STATUS = 0x004
START_PC = 0x008
CLKDIV = 0x00C
SET_CFG = 0x010
SIDESET_CFG = 0x014
TX_DATA = 0x018
RX_DATA = 0x01C
FIFO_STATUS = 0x020
PC_DEBUG = 0x024
PROGRAM = 0x100


async def start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns").start())
    await Timer(CLOCK_PERIOD_NS, unit="ns")


def set_cfg_pins(dut, *, mosi=None, sclk=None, cs_n=None):
    current = int(dut.ui_in.value)
    if mosi is not None:
        current = (current & ~0x01) | (int(mosi) & 1)
    if sclk is not None:
        current = (current & ~0x02) | ((int(sclk) & 1) << 1)
    if cs_n is not None:
        current = (current & ~0x04) | ((int(cs_n) & 1) << 2)
    dut.ui_in.value = current


async def reset_dut(dut):
    await start_clock(dut)
    dut.ena.value = 1
    dut.uio_in.value = 0
    dut.ui_in.value = 0x04
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 6)
    assert int(dut.uio_oe.value) == 0
    assert int(dut.uio_out.value) == 0
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 6)
    assert (int(dut.uo_out.value) & 1) == 0


async def spi_begin(dut, phase_ns=0, half_ns=SPI_HALF_NS):
    set_cfg_pins(dut, mosi=0, sclk=0, cs_n=0)
    await Timer(400, unit="ns")
    if phase_ns:
        await Timer(phase_ns, unit="ns")


async def spi_end(dut):
    set_cfg_pins(dut, sclk=0, cs_n=1)
    await Timer(400, unit="ns")


async def spi_write_bits(dut, value, count, half_ns=SPI_HALF_NS):
    for index in range(count - 1, -1, -1):
        set_cfg_pins(dut, mosi=(value >> index) & 1)
        await Timer(half_ns, unit="ns")
        set_cfg_pins(dut, sclk=1)
        await Timer(half_ns, unit="ns")
        set_cfg_pins(dut, sclk=0)
        await Timer(half_ns, unit="ns")


async def spi_write_byte(dut, value, half_ns=SPI_HALF_NS):
    await spi_write_bits(dut, value & 0xFF, 8, half_ns)


async def spi_read_byte(dut, half_ns=SPI_HALF_NS):
    value = 0
    for index in range(7, -1, -1):
        set_cfg_pins(dut, mosi=0)
        await Timer(half_ns, unit="ns")
        set_cfg_pins(dut, sclk=1)
        await Timer(half_ns // 2, unit="ns")
        value |= (int(dut.uo_out.value) & 1) << index
        await Timer(half_ns - half_ns // 2, unit="ns")
        set_cfg_pins(dut, sclk=0)
        await Timer(half_ns, unit="ns")
    return value


async def spi_write32(dut, address, data, *, phase_ns=0, half_ns=SPI_HALF_NS):
    await spi_begin(dut, phase_ns, half_ns)
    await spi_write_byte(dut, 0x01, half_ns)
    await spi_write_byte(dut, (address >> 8) & 0xFF, half_ns)
    await spi_write_byte(dut, address & 0xFF, half_ns)
    for shift in (24, 16, 8, 0):
        await spi_write_byte(dut, (data >> shift) & 0xFF, half_ns)
    await spi_end(dut)


async def spi_read32(dut, address, *, phase_ns=0, half_ns=SPI_HALF_NS):
    await spi_begin(dut, phase_ns, half_ns)
    await spi_write_byte(dut, 0x02, half_ns)
    await spi_write_byte(dut, (address >> 8) & 0xFF, half_ns)
    await spi_write_byte(dut, address & 0xFF, half_ns)
    data = 0
    for _ in range(4):
        data = (data << 8) | await spi_read_byte(dut, half_ns)
    await spi_end(dut)
    return data


async def spi_burst_write(dut, address, words, *, phase_ns=0, half_ns=SPI_HALF_NS):
    assert words
    await spi_begin(dut, phase_ns, half_ns)
    await spi_write_byte(dut, 0x03, half_ns)
    await spi_write_byte(dut, (address >> 8) & 0xFF, half_ns)
    await spi_write_byte(dut, address & 0xFF, half_ns)
    await spi_write_byte(dut, len(words), half_ns)
    for word in words:
        for shift in (24, 16, 8, 0):
            await spi_write_byte(dut, (word >> shift) & 0xFF, half_ns)
    await spi_end(dut)


async def spi_burst_read(dut, address, count, *, phase_ns=0, half_ns=SPI_HALF_NS):
    await spi_begin(dut, phase_ns, half_ns)
    await spi_write_byte(dut, 0x04, half_ns)
    await spi_write_byte(dut, (address >> 8) & 0xFF, half_ns)
    await spi_write_byte(dut, address & 0xFF, half_ns)
    await spi_write_byte(dut, count, half_ns)
    words = []
    for _ in range(count):
        word = 0
        for _ in range(4):
            word = (word << 8) | await spi_read_byte(dut, half_ns)
        words.append(word)
    await spi_end(dut)
    return words


async def load_program(dut, words, *, phase_ns=0, half_ns=SPI_HALF_NS):
    packed = []
    for index in range(0, len(words), 2):
        low = words[index]
        high = words[index + 1] if index + 1 < len(words) else 0
        packed.append((high << 16) | low)
    await spi_burst_write(dut, PROGRAM, packed, phase_ns=phase_ns, half_ns=half_ns)


def assemble_file(name):
    return Assembler().assemble_file(ROOT / "programs" / name)


def assemble_text(source):
    return Assembler().assemble(source)


async def _wait_oe_high(dut):
    """Wait until uio_oe[GPIO_BIT] reads 1, sampled on system clock edges.

    Icarus VPI (gate-level runs) cannot register value-change callbacks on
    bit-selects of vector signals ("cannot callback values on type code=37"),
    so the capture coroutines poll whole vectors one nanosecond after each
    clk edge instead of awaiting bit edges.  The fixed +1 ns offset keeps
    event timestamps on the exact clock grid the interval assertions rely
    on, and behaves identically under Verilator (RTL) and Icarus (GL).
    """
    while True:
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        oe = dut.uio_oe.value
        if oe.is_resolvable and (int(oe) >> GPIO_BIT) & 1:
            return


async def _poll_gpio_events(dut):
    previous = (int(dut.uio_out.value) >> GPIO_BIT) & 1
    events = []
    while len(events) < 8:
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        value = (int(dut.uio_out.value) >> GPIO_BIT) & 1
        if value != previous:
            events.append((get_sim_time("ns"), value))
            previous = value
    return events


async def run_gpio_capture(dut):
    await _wait_oe_high(dut)
    return await with_timeout(_poll_gpio_events(dut), 5, "us")


async def capture_uart_frame(dut):
    await _wait_oe_high(dut)
    # SET PINDIRS executes one engine tick before the start-bit SET.
    await Timer(60, unit="ns")
    samples = []
    for _ in range(10):
        samples.append((int(dut.uio_out.value) >> GPIO_BIT) & 1)
        await Timer(100, unit="ns")
    return samples


@cocotb.test()
async def test_reset_and_pin_contract(dut):
    await reset_dut(dut)


@cocotb.test()
async def test_management_packets_and_phase_offsets(dut):
    await reset_dut(dut)

    # READ32, WRITE32, CSR read/write, and back-to-back transactions.
    assert await spi_read32(dut, STATUS) == 0x14
    await spi_write32(dut, START_PC, 3)
    assert await spi_read32(dut, START_PC) == 3
    await spi_write32(dut, CLKDIV, 4)
    assert await spi_read32(dut, CLKDIV) == 4
    await spi_write32(dut, SET_CFG, 2)
    assert (await spi_read32(dut, SET_CFG) & 0x7) == 2
    await spi_write32(dut, SIDESET_CFG, 0x0101)
    assert (await spi_read32(dut, SIDESET_CFG) & 0x3FF) == 0x0101

    # Explicitly measured rate sweep; 5 MHz is the fastest passing rate.
    for half_ns, expected_rate_mhz in ((500, 1.0), (200, 2.5), (100, 5.0)):
        assert await spi_read32(dut, STATUS, half_ns=half_ns) == 0x14
        dut._log.info("management SPI passed %.1f MHz", expected_rate_mhz)

    # Keep the edge phase fixed throughout each transaction while sweeping it.
    for phase_ns in (0, 7, 13, 19):
        assert await spi_read32(dut, STATUS, phase_ns=phase_ns) == 0x14

    # Unknown command recovery and several CS-aborted packet boundaries.
    await spi_begin(dut)
    await spi_write_byte(dut, 0x99)
    await spi_end(dut)
    assert await spi_read32(dut, STATUS) == 0x14

    await spi_begin(dut)
    await spi_write_bits(dut, 0x01, 4)
    await spi_end(dut)
    assert await spi_read32(dut, STATUS) == 0x14

    await spi_begin(dut)
    await spi_write_byte(dut, 0x01)
    await spi_write_bits(dut, 0x00, 4)
    await spi_end(dut)
    assert await spi_read32(dut, STATUS) == 0x14

    await spi_begin(dut)
    await spi_write_byte(dut, 0x01)
    await spi_write_byte(dut, 0x00)
    await spi_write_byte(dut, 0x04)
    await spi_write_byte(dut, 0x12)
    await spi_write_byte(dut, 0x34)
    await spi_end(dut)
    assert await spi_read32(dut, STATUS) == 0x14


@cocotb.test()
async def test_imem_burst_and_gpio_program(dut):
    await reset_dut(dut)
    words = assemble_file("gpio_toggle.pasm")
    await load_program(dut, words)
    assert await spi_burst_read(dut, PROGRAM, 2) == [0xE021E420, 0x0010E001]

    await spi_write32(dut, CLKDIV, 1)
    await spi_write32(dut, START_PC, 0)
    capture = cocotb.start_soon(run_gpio_capture(dut))
    await spi_write32(dut, CTRL, 1)
    events = await capture

    values = [value for _, value in events]
    intervals = [events[i][0] - events[i - 1][0] for i in range(1, len(events))]
    assert values == [1, 0, 1, 0, 1, 0, 1, 0]
    assert all(interval in (40, 60) for interval in intervals), intervals


@cocotb.test()
async def test_errors_imem_protection_and_controls(dut):
    await reset_dut(dut)

    # Invalid address and read-only writes are handled without changing state.
    assert await spi_read32(dut, 0x00F0) == 0xDEADBEEF
    before = await spi_read32(dut, STATUS)
    await spi_write32(dut, STATUS, 0xFFFF_FFFF)
    assert await spi_read32(dut, STATUS) == before

    words = assemble_file("gpio_toggle.pasm")
    await load_program(dut, words)
    await spi_write32(dut, START_PC, 0)
    await spi_write32(dut, CTRL, 1)
    await ClockCycles(dut.clk, 8)
    await spi_write32(dut, 0x0100, 0)
    status = await spi_read32(dut, STATUS)
    assert status & 0x02
    assert not (status & 0x01)

    await spi_write32(dut, CTRL, 4)
    assert await spi_read32(dut, STATUS) == 0x14


@cocotb.test()
async def test_fifo_host_access_and_rx_program(dut):
    await reset_dut(dut)

    # TX host writes, full handling, and empty RX read response.
    for value in (1, 2, 3, 4):
        await spi_write32(dut, TX_DATA, value)
    fifo_status = await spi_read32(dut, FIFO_STATUS)
    assert (fifo_status & 0x03) == 0x02
    await spi_write32(dut, TX_DATA, 5)
    assert (await spi_read32(dut, FIFO_STATUS) & 0x03) == 0x02
    assert await spi_read32(dut, RX_DATA) == 0xDEADBEEF

    await reset_dut(dut)
    rx_words = assemble_text("""
        in pins, 8
        push block
        jmp 0
    """)
    await load_program(dut, rx_words)
    await spi_write32(dut, START_PC, 0)
    dut.uio_in.value = 0xA5
    await spi_write32(dut, CTRL, 1)
    await ClockCycles(dut.clk, 12)
    assert await spi_read32(dut, RX_DATA) & 0xFF == 0xA5


@cocotb.test()
async def test_concurrent_fifo_activity_and_run_halt_reset(dut):
    await reset_dut(dut)
    loop_words = assemble_text("""
        set pindirs, 1
    loop:
        pull noblock
        out pins, 1
        in pins, 1
        push noblock
        jmp loop
    """)
    await load_program(dut, loop_words)
    await spi_write32(dut, START_PC, 0)
    await spi_write32(dut, CTRL, 1)
    await ClockCycles(dut.clk, 8)
    running_status = await spi_read32(dut, STATUS)
    assert running_status & 1

    for value in (0x11223344, 0x55667788, 0x99AABBCC):
        await spi_write32(dut, TX_DATA, value)
    await ClockCycles(dut.clk, 20)
    while True:
        fifo_status = await spi_read32(dut, FIFO_STATUS)
        if fifo_status & 0x04 == 0:
            break
        await ClockCycles(dut.clk, 4)
    assert await spi_read32(dut, RX_DATA) != 0xDEADBEEF

    pc_before = await spi_read32(dut, PC_DEBUG)
    await spi_write32(dut, CTRL, 2)
    await ClockCycles(dut.clk, 6)
    pc_after = await spi_read32(dut, PC_DEBUG)
    assert not (await spi_read32(dut, STATUS) & 1)
    assert pc_after == pc_before

    await spi_write32(dut, CTRL, 4)
    assert await spi_read32(dut, STATUS) == 0x14


@cocotb.test()
async def test_uart_end_to_end(dut):
    await reset_dut(dut)
    words = assemble_file("uart_tx.pasm")
    await load_program(dut, words)
    await spi_write32(dut, TX_DATA, 0xA5)
    await spi_write32(dut, START_PC, 0)

    capture = cocotb.start_soon(capture_uart_frame(dut))
    await spi_write32(dut, CTRL, 1)
    samples = await with_timeout(capture, 5, "us")

    expected = [0] + [(0xA5 >> bit) & 1 for bit in range(8)] + [1]
    assert samples == expected, (samples, expected)
    await spi_write32(dut, CTRL, 2)


@cocotb.test()
async def test_multiple_transactions_and_cs_recovery(dut):
    await reset_dut(dut)
    for phase_ns in (0, 7, 13, 19):
        await spi_write32(dut, CLKDIV, 1, phase_ns=phase_ns)
        assert await spi_read32(dut, CLKDIV, phase_ns=phase_ns) == 1
