# SPDX-FileCopyrightText: 2026 Chidam
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer


def byte_value(signal):
    value = signal.value
    assert value.is_resolvable, f"{signal._name} contains X/Z: {value}"
    return int(value)


@cocotb.test()
async def test_project(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    await Timer(1, unit="ns")

    assert byte_value(dut.uo_out) == 0
    assert byte_value(dut.uio_out) == 0
    assert byte_value(dut.uio_oe) == 0

    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    vectors = [
        0x00, 0x15, 0x2A, 0x3F,
        0x40, 0x55, 0x6A, 0x7F,
        0x80, 0x95, 0xAA, 0xBF,
        0xC0, 0xD5, 0xEA, 0xFF,
        0x1C, 0x63, 0xB4, 0xE7,
        0x08, 0x49, 0x8E, 0xCF,
    ]

    seen = set()
    for value in vectors:
        await FallingEdge(dut.clk)
        dut.ui_in.value = value
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        seen.add(byte_value(dut.uo_out))
        assert byte_value(dut.uio_out) == 0
        assert byte_value(dut.uio_oe) == 0

    assert len(seen) > 4

    await FallingEdge(dut.clk)
    dut.ena.value = 0
    dut.ui_in.value = 0x55
    await RisingEdge(dut.clk)
    await Timer(2, unit="ns")
    byte_value(dut.uo_out)
