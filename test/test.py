import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def test_project(dut):
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset sequence
    dut.rst_n.value = 0
    dut.ena.value = 0
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    dut.ena.value = 1
    await RisingEdge(dut.clk)

    # Set mode 00 and data
    dut.ui_in.value = (0b00 << 6) | 0x2A   # mode=00, data=0x2A
    await RisingEdge(dut.clk)   # first edge: internal registers update
    await RisingEdge(dut.clk)   # second edge: uo_out updates

    # Now read output – it should no longer be X
    value = dut.uo_out.value
    if value.is_resolvable:
        actual = value.integer
        dut._log.info(f"uo_out = {actual:02X}")
        # Add your assertion here (e.g., compare with expected CRC)
    else:
        dut._log.error("uo_out still contains X – check VPWR/VGND connections")
        assert False, "Gate-level simulation missing power/ground"
