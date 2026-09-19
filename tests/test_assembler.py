import pytest

from tools.assembler import Assembler, AssemblyError
from tools.isa import Major, SetDest, decode, decode_timing


def test_labels_and_all_milestone_zero_syntax():
    source = """
    .sideset 1
    start:
        set x, 7 side 1 [3]
        mov osr, x
        pull noblock
        push block
        in pins, 1
        out pins, 8
        wait tx_not_empty
        wait rising, 2
        jmp x-- start
        ext nop
    """
    asm = Assembler()
    words = asm.assemble(source)
    assert asm.labels["start"] == 0
    assert len(words) == 10
    assert decode(words[0]).major == Major.SET
    assert decode_timing(decode(words[0]).timing, 1) == (1, 3)
    assert decode(words[-2]).field_b == 0


def test_program_memory_and_immediate_errors():
    with pytest.raises(AssemblyError):
        Assembler().assemble("set pins, 32")
    with pytest.raises(AssemblyError):
        Assembler().assemble(".org 64\nnop")
    with pytest.raises(AssemblyError):
        Assembler(sideset_count=1).assemble(".sideset 1\nset x, 1 side 1 [16]")
