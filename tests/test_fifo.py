import random
from collections import deque

from tools.arch_sim import Fifo


def test_fifo_100000_randomized_operations():
    rng = random.Random(0x51CE)
    fifo = Fifo(4)
    reference = deque()
    for _ in range(100_000):
        operation = rng.randrange(3)
        if operation == 0:  # push
            value = rng.getrandbits(32)
            expected = len(reference) < 4
            assert fifo.push(value) == expected
            if expected:
                reference.append(value & 0xFFFFFFFF)
        elif operation == 1:  # pop
            expected = reference.popleft() if reference else None
            assert fifo.pop() == expected
        else:  # inspect
            assert fifo.level == len(reference)
            assert fifo.empty == (not reference)
            assert fifo.full == (len(reference) == 4)
        assert fifo.contents == list(reference)


def test_fifo_simultaneous_push_pop_and_wraparound():
    fifo = Fifo(2)
    assert fifo.push(1)
    assert fifo.push(2)
    assert fifo.push_pop(3, do_pop=True) == 1
    assert fifo.contents == [2, 3]
    assert fifo.pop() == 2
    assert fifo.pop() == 3
    assert fifo.pop() is None
