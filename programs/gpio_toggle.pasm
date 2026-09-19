.program gpio_toggle

; GPIO0 is a push-pull output.  SET instructions are intentionally used so
; this program exercises the first milestone's basic output path.
set pindirs, 1

toggle:
    set pins, 1 [1]
    set pins, 0 [1]
    jmp toggle
