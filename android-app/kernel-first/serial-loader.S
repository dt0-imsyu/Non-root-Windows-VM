/*
 * Minimal unprotected ARM64 Linux-Image payload for AVF/crosvm.
 * crosvm requires the 64-byte Image header, enters at its load address,
 * and passes the guest FDT in x0. The 16550 UART address comes from the
 * crosvm-generated FDT topology (first serial device at MMIO 0x3f8).
 */
.section .text
.global _start

_start:
    b payload
    .word 0
    .quad 0x80000                 /* Linux Image text_offset */
    .quad image_end - _start      /* image_size */
    .quad 0                       /* flags: little endian */
    .quad 0
    .quad 0
    .quad 0
    .word 0x644d5241              /* ARM64 Image magic */
    .word 0

payload:
    mov x1, #0x3f8
    adr x2, message
1:  ldrb w3, [x2], #1
    cbz w3, 2f
    strb w3, [x1]
    b 1b
2:  wfe
    b 2b

message:
    .asciz "KERNEL-FIRST LOADER PASS\r\n"
.balign 8
image_end:
