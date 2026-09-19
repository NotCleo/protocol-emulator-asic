from tools.isa import (
    Endpoint, ExtOp, JmpCond, Major, SetDest, WaitCond,
    decode, decode_shift_count, decode_timing, encode_ext, encode_jmp,
    encode_mov, encode_push_pull, encode_set, encode_shift, encode_timing,
    encode_wait,
)


def test_major_classes_and_round_trips():
    words = [
        encode_jmp(JmpCond.X_DEC, 63),
        encode_wait(WaitCond.RISING, 7, encode_timing(1, 3, 1)),
        encode_shift(Major.IN, Endpoint.PINS, 32, 0),
        encode_shift(Major.OUT, Endpoint.PINS, 8, 17),
        encode_push_pull(True, True, 2),
        encode_mov(Endpoint.X, Endpoint.OSR, 4),
        encode_ext(ExtOp.NOP, 5),
        encode_set(SetDest.PINDIRS, 3, 6),
    ]
    assert [decode(word).major for word in words] == list(Major)
    assert decode(words[0]).field_b == 63
    assert decode(words[2]).field_b == 0
    assert decode_shift_count(decode(words[2]).field_b) == 32
    assert decode(words[4]).field_a == 1
    assert decode(words[4]).field_b == 1


def test_timing_layout():
    for count, side, delay in ((0, 0, 31), (1, 1, 15), (2, 3, 7)):
        field = encode_timing(side, delay, count)
        assert decode_timing(field, count) == (side, delay)
