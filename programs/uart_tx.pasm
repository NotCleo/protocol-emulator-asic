.program uart_tx

; Preliminary UART 8N1 transmitter.
; Host words place the byte in OSR[7:0].  SHIFT_CFG selects right shifting,
; so OUT PINS,1 emits the least-significant bit first.
; One engine tick plus the delay field is one bit cell in this demonstration.

tx:
    pull block
    set x, 7
    set pindirs, 1
    set pins, 0 [3]       ; start bit

bit:
    out pins, 1 [3]
    jmp x-- bit

    set pins, 1 [3]       ; stop bit and idle level
    jmp tx
