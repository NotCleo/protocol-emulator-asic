from pathlib import Path

from tools.arch_sim import ProtocolEngine
from tools.assembler import Assembler


ROOT = Path(__file__).parents[1]


def test_gpio_toggle_program_changes_output_and_direction():
    words = Assembler().assemble_file(ROOT / "programs" / "gpio_toggle.pasm")
    engine = ProtocolEngine()
    engine.load_program(words)
    engine.start()
    entries = [engine.step() for _ in range(30)]

    assert engine.gpio_oe & 1
    values = [entry["gpio_out"] & 1 for entry in entries if entry["executed"]]
    assert 0 in values and 1 in values
    assert engine.status["RUNNING"]
    assert all(0 <= entry["pc"] < 64 for entry in entries)


def test_wait_is_a_pc_stall_and_resumes_once():
    words = Assembler().assemble("wait pin_high, 0\nset x, 1\n")
    engine = ProtocolEngine()
    engine.load_program(words)
    engine.start()
    blocked = engine.step(0)
    assert blocked["pc"] == 0
    assert blocked["stall_reason"] == "wait"
    resumed = engine.step(1)
    assert resumed["pc"] == 1
    assert resumed["executed"]
    following = engine.step(1)
    assert following["x"] == 1
    assert following["pc"] == 2


def test_delay_executes_once_and_side_set_is_same_event():
    words = Assembler().assemble(".sideset 1\nset x, 1 side 1 [2]\nnop\n")
    engine = ProtocolEngine()
    engine.sideset_count = 1
    engine.sideset_base = 1
    engine.load_program(words)
    engine.start()
    first = engine.step()
    assert first["executed"]
    assert first["x"] == 1
    assert first["gpio_out"] & 2
    assert engine.delay_count == 2
    assert engine.step()["stall_reason"] == "delay"
    assert engine.step()["stall_reason"] == "delay"
    assert engine.step()["pc"] == 2


def test_pull_out_and_push_round_trip():
    source = """
        pull block
        out pins, 8
        in pins, 8
        push block
        jmp 0
    """
    engine = ProtocolEngine()
    engine.load_program(Assembler().assemble(source))
    engine.feed_tx([0x5A])
    engine.start()
    for _ in range(4):
        engine.step(0xA5)
    assert engine.gpio_out & 0xFF == 0x5A
    assert engine.rx_fifo.contents == [0xA5]


def test_parameterized_pc_faults_at_last_instruction():
    from tools.isa import SetDest, encode_set

    for depth in (64, 128):
        engine = ProtocolEngine(program_words=depth)
        engine.load_program([encode_set(SetDest.X, 1)], start=depth - 1)
        engine.start(pc=depth - 1)
        row = engine.step()
        assert row["pc"] == depth - 1
        assert row["fault"]
        assert not row["running"]
