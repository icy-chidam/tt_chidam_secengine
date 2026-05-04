# SPDX-FileCopyrightText: 2026 Chidam
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


MASK32 = (1 << 32) - 1
MASK16 = (1 << 16) - 1
SBOX = [0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD, 0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2]


def rol(value, width, shift):
    shift %= width
    mask = (1 << width) - 1
    return ((value << shift) | (value >> (width - shift))) & mask


def sub32(x):
    y = 0
    for i in range(8):
        y |= SBOX[(x >> (i * 4)) & 0xF] << (i * 4)
    return y


def crc8_dallas(crc, data):
    c = (crc ^ data) & 0xFF
    for _ in range(8):
        if c & 1:
            c = ((c >> 1) ^ 0x8C) & 0xFF
        else:
            c = (c >> 1) & 0xFF
    return c


class Model:
    def __init__(self):
        self.state = 0x6A09E667
        self.key = 0x243F
        self.crc = 0x5A
        self.ctr = 0
        self.out = 0

    def step(self, ui):
        mode = (ui >> 6) & 0x3
        din = ((ui & 0x3F) << 2) | mode

        mix_a = (self.state ^ (self.key << 16 | (~self.key & MASK16)) ^ int.from_bytes(bytes([din ^ self.ctr]) * 4, "big")) & MASK32
        mix_b = sub32(mix_a)
        mix_c = rol(mix_b, 32, 13) ^ rol(mix_b, 32, 25) ^ rol(mix_b, 32, 4)
        round_value = (mix_c + ((self.key << 16) | (self.crc << 8) | din) + 0x9E3779B9) & MASK32
        crc_next = crc8_dallas(self.crc, din ^ (self.state & 0xFF))

        old_state = self.state
        old_key = self.key
        old_crc = self.crc
        old_ctr = self.ctr
        self.ctr = (self.ctr + 1) & 0xFF

        if mode == 0:
            self.state = (round_value ^ (crc_next << 24) ^ (din << 16) ^ old_key) & MASK32
            self.key = (old_key ^ ((round_value >> 8) & MASK16) ^ ((din << 8) | old_ctr)) & MASK16
            self.crc = crc_next
            self.out = (round_value ^ (round_value >> 16) ^ old_crc) & 0xFF
        elif mode == 1:
            self.state = (((round_value & 0xFFFFFF) << 8) | (((round_value >> 24) ^ din) & 0xFF)) & MASK32
            self.key = (((old_key & 0xFF) << 8) | (((old_key >> 8) ^ round_value ^ din) & 0xFF)) & MASK16
            self.crc = crc8_dallas(old_crc ^ ((round_value >> 8) & 0xFF), din)
            self.out = ((round_value >> 8) ^ (round_value >> 24) ^ din) & 0xFF
        elif mode == 2:
            self.state = (old_state ^ ((round_value & 0xFFFF) << 16) ^ (crc_next << 8) ^ din) & MASK32
            self.key = (old_key + ((crc_next << 8) | din)) & MASK16
            self.crc = crc_next
            self.out = (crc_next ^ (old_state >> 8) ^ old_key) & 0xFF
        else:
            self.state = (rol(old_state, 32, 7) ^ (din << 24) ^ (old_crc << 16) ^ old_key) & MASK32
            self.key = (rol(old_key, 16, 5) ^ (din << 8) ^ old_ctr) & MASK16
            self.crc = 0xA5 ^ din ^ old_ctr
            self.out = ((old_key >> 8) ^ (old_state >> 24) ^ old_crc) & 0xFF

        return self.out


@cocotb.test()
async def test_project(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    assert int(dut.uio_oe.value) == 0
    assert int(dut.uio_out.value) == 0

    model = Model()
    vectors = [
        0x00, 0x15, 0x2A, 0x3F,
        0x40, 0x55, 0x6A, 0x7F,
        0x80, 0x95, 0xAA, 0xBF,
        0xC0, 0xD5, 0xEA, 0xFF,
        0x1C, 0x63, 0xB4, 0xE7,
        0x08, 0x49, 0x8E, 0xCF,
    ]

    for value in vectors:
        dut.ui_in.value = value
        expected = model.step(value)
        await ClockCycles(dut.clk, 1)
        assert int(dut.uo_out.value) == expected

    dut.ena.value = 0
    held = int(dut.uo_out.value)
    dut.ui_in.value = 0x00
    await ClockCycles(dut.clk, 3)
    assert int(dut.uo_out.value) == held
