.program spi_master
.sideset 2

; V0 SPI master: mode 0 (CPOL=0, CPHA=0), MSB-first, full duplex.
; One frame transfers one 32-bit host word in each direction; the host
; feeds TX words and reads RX words through the FIFO registers.
;
; Pin map (configured through the CSRs while the engine is halted):
;   uio0 = SCK   side-set bit 0 (SIDESET_CFG base 0, count 2)
;   uio1 = CS_N  side-set bit 1 (1 = deasserted/idle)
;   uio2 = MOSI  OUT_CFG base 2
;   uio3 = MISO  IN_CFG base 3
; SHIFT_CFG: out left-shift (MSB first), in left-shift (MSB first).
;
; Each bit takes six engine ticks (three SCK-low, three SCK-high), so with
; CLKDIV=1 on the 50 MHz clock SCK runs at roughly 8.3 MHz; raise CLKDIV
; for slower slaves.  JMP carries no side-set in V0, so the loop-back tick
; extends the SCK-high phase by one tick -- the [2] delay on OUT balances
; the two half periods.

init:
    set pindirs, 7 side 2   ; SCK, CS_N, MOSI outputs; CS_N idle high
frame:
    pull block side 2       ; OSR <= TX word; CS_N stays high while waiting
    nop side 0              ; assert CS_N, SCK low: frame start
    set x, 31 side 0        ; 32 bits per frame
bit:
    out pins, 1 side 0 [2]  ; SCK low: drive MOSI = OSR[31], setup phase
    in pins, 1 side 1 [1]   ; SCK rises: sample edge, MISO -> ISR
    jmp x-- bit             ; SCK stays high one extra tick (no side-set)
    push block side 0       ; RX word <= ISR; SCK falls after the last bit
    nop side 2 [1]          ; deassert CS_N: frame end
    jmp frame
