/*
 * Disposable ARM64 AVF serial loopback probe.
 *
 * It is a minimal Linux-Image-envelope payload for `vm run`, not a Windows
 * or product artifact. crosvm supplies a 16550-compatible UART at 0x3f8.
 * The probe announces readiness, echoes exactly 4096 received UART bytes, and
 * requests PSCI SYSTEM_OFF. No disk, filesystem, or guest OS is used.
 */
.section .text
.global _start

.equ UART_BASE, 0x3f8
.equ UART_LSR,  5
.equ PAYLOAD_BYTES, 4096

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
    mov x1, #UART_BASE
    adr x2, ready
1:  ldrb w3, [x2], #1
    cbz w3, 2f
    strb w3, [x1]
    b 1b

2:  mov w4, #PAYLOAD_BYTES
3:  ldrb w3, [x1, #UART_LSR]
    tbz w3, #0, 3b
    ldrb w3, [x1]
    strb w3, [x1]
    subs w4, w4, #1
    b.ne 3b

    /* PSCI_0_2_SYSTEM_OFF, via the FDT-declared HVC conduit. */
    movz w0, #0x0008
    movk w0, #0x8400, lsl #16
    hvc #0
4:  wfe
    b 4b

ready:
    .ascii "SHELL_SERIAL_LOOPBACK_READY\\r\\n"
    .byte 0
.balign 8
image_end:
