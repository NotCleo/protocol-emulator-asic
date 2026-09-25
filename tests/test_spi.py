from pathlib import Path

from tools.arch_sim import ProtocolEngine
from tools.assembler import Assembler


ROOT = Path(__file__).parents[1]


class Mode0Slave:
    """Full-duplex SPI mode 0 slave word model.

    Presents the MSB of ``word`` on MISO as soon as CS_N asserts, advances
    to the next bit on every SCK falling edge, and captures MOSI on every
    rising edge -- the mode 0 (CPOL=0, CPHA=0) contract.
    """

    def __init__(self, word: int):
        self.word = word & 0xFFFFFFFF
        self.miso = 0
        self.received = None
        self._bit_index = 0
        self._shift = 0
        self._captured = 0

    def select(self):
        self._bit_index = 31
        self._shift = 0
        self._captured = 0
        self.miso = (self.word >> 31) & 1

    def rising(self, mosi: int):
        self._shift = ((self._shift << 1) | (mosi & 1)) & 0xFFFFFFFF
        self._captured += 1

    def falling(self):
        self._bit_index -= 1
        if self._bit_index >= 0:
            self.miso = (self.word >> self._bit_index) & 1

    def deselect(self):
        if self._captured == 32:
            self.received = self._shift
        self.miso = 0


def test_spi_master_mode0_full_duplex_in_python_model():
    words = Assembler().assemble_file(ROOT / "programs" / "spi_master.pasm")
    engine = ProtocolEngine()
    engine.sideset_count = 2
    engine.sideset_base = 0
    engine.out_base = 2   # MOSI on uio2
    engine.in_base = 3    # MISO on uio3
    engine.set_base = 0
    engine.out_shift_right = False  # MSB-first transmit
    engine.in_shift_right = False   # MSB-first receive
    engine.load_program(words)

    tx_words = [0xA5C33C5A, 0x0000FFFF]
    slaves = [Mode0Slave(0x12345678), Mode0Slave(0xDEADBEEF)]
    engine.feed_tx(tx_words)
    engine.start()

    active = None
    sck_prev = 0
    cs_prev = 1
    frames = 0
    rising_edges = 0
    falling_edges = 0
    mosi_samples = []

    for _ in range(600):
        gpio_in = (active.miso << 3) if active else 0
        engine.step(gpio_in)
        sck = engine.gpio_out & 1
        cs = (engine.gpio_out >> 1) & 1
        mosi = (engine.gpio_out >> 2) & 1
        if cs_prev and not cs:
            active = slaves[frames]
            active.select()
            frames += 1
        if active is not None:
            if not sck_prev and sck:
                rising_edges += 1
                mosi_samples.append(mosi)
                active.rising(mosi)
            elif sck_prev and not sck:
                falling_edges += 1
                active.falling()
        if not cs_prev and cs and active is not None:
            active.deselect()
            active = None
        sck_prev, cs_prev = sck, cs
        if len(engine.rx_fifo.contents) == len(tx_words):
            break

    # Let the tail of the second frame finish (CS_N deassert, back to pull).
    for _ in range(4):
        engine.step(0)
        cs = (engine.gpio_out >> 1) & 1
        if not cs_prev and cs and active is not None:
            active.deselect()
            active = None
        cs_prev = cs

    expected_mosi = [bit for word in tx_words for bit in
                     ((word >> (31 - index)) & 1 for index in range(32))]
    assert frames == 2
    assert rising_edges == 64
    assert falling_edges == 64
    assert mosi_samples == expected_mosi
    assert [slave.received for slave in slaves] == tx_words
    assert engine.rx_fifo.contents == [0x12345678, 0xDEADBEEF]
    # Mode 0 idle and pin directions: SCK low, CS_N high, pins 0-2 outputs.
    assert engine.gpio_out & 0b11 == 0b10
    assert engine.gpio_oe == 0b0000_0111
    assert engine.tx_fifo.empty
