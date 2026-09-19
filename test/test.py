# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_reset_and_pin_contract(dut):
    """Template smoke test for the fixed CMOS5L top-level contract."""
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    assert dut.uio_oe.value == 0
    assert dut.uio_out.value == 0
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    # The smoke test leaves management SPI idle; public-pin SPI coverage is in tests/tb_mgmt_spi.sv.
    assert (int(dut.uo_out.value) & 1) == 0
    assert dut.uio_oe.value == 0
