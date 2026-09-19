# Protocol engine V0 — Milestone 0

This directory currently contains the executable ISA definition, assembler,
and Python architectural model. RTL is intentionally deferred until the
assembler, GPIO toggle program, and preliminary UART transmitter have been
validated.

One `ProtocolEngine.step()` is one engine-clock-enable event. An instruction
executes once on its event. A delay of `N` emits one execution event followed
by `N` delay-only events. Blocking PULL, blocking PUSH, and WAIT leave PC and
the instruction's destination state unchanged until their condition succeeds.

The default model uses 64 x 16-bit program memory (the RTL/model depth is parameterizable), 16-bit X/Y, 32-bit OSR/ISR, and
4 x 32-bit TX/RX FIFOs. GPIO mappings are contiguous from their configured
base pin and ignore bits that fall outside the eight physical pins.

The Python trace is a post-event trace. It includes the requested state plus
`pc_before`, `executed`, and a textual instruction rendering. Delay-only events
have `instruction=None` and `stall_reason=delay`; a blocked instruction keeps
its instruction word and reports its blocking reason.

The model samples GPIO inputs once per engine event and produces rising/falling
events from the current and previous samples. The future RTL implementation
will add the specified two-flip-flop system-clock synchronizer before those
events reach the engine.
