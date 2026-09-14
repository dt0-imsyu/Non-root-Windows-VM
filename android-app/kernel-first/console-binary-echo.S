/*
 * Disposable ARM64 Linux-Image guest for the AVF console-input probe.
 * It uses the established crosvm ttyS0 16550 MMIO address (0x3f8), writes a
 * readiness marker once, then echoes every received byte verbatim.  It has no
 * disk, filesystem, network, firmware, or Windows dependency.
 */
.section .text
.global _start

_start:
    b payload
    .word 0
    .quad 0x80000
    .quad image_end - _start
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .word 0x644d5241
    .word 0

payload:
    mov x1, #0x3f8                 /* 16550 data register */
    add x4, x1, #5                 /* line-status register */
    adr x2, ready
1:  ldrb w3, [x2], #1
    cbz w3, 2f
3:  ldrb w5, [x4]
    tbz w5, #5, 3b                 /* wait for THR empty */
    strb w3, [x1]
    b 1b

2:  ldrb w5, [x4]
    tbz w5, #0, 2b                 /* wait for received byte */
    ldrb w3, [x1]
4:  ldrb w5, [x4]
    tbz w5, #5, 4b                 /* preserve byte ordering */
    strb w3, [x1]
    b 2b

ready:
    .asciz "WINAVF_ECHO_READY\n"

.balign 8
image_end:
