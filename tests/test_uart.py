from pathlib import Path

from tools.arch_sim import ProtocolEngine
from tools.assembler import Assembler
from tools.isa import decode


ROOT = Path(__file__).parents[1]


def test_preliminary_uart_tx_8n1_in_python_model():
    words = Assembler().assemble_file(ROOT / "programs" / "uart_tx.pasm")
    engine = ProtocolEngine()
    engine.load_program(words)
    engine.feed_tx([0x55])
    engine.start()

    observed = []
    for _ in range(160):
        entry = engine.step()
        if entry["executed"] and entry["pc_before"] in (3, 4, 6):
            observed.append((entry["pc_before"], entry["gpio_out"] & 1))
        if len(observed) >= 10:
            break

    # start, eight LSB-first data bits, stop
    assert [level for _, level in observed[:10]] == [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
    assert engine.gpio_oe & 1
