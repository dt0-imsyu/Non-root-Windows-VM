/* ARM64 Linux Image envelope for a 4-KiB-aligned, position-independent U-Boot. */
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
    mov x1, #0x3f8
    adr x2, marker
1:  ldrb w3, [x2], #1
    cbz w3, 2f
    strb w3, [x1]
    b 1b
2:  b uboot_start

marker:
    .asciz "WRAPPER: entering U-Boot\r\n"

.balign 4096
uboot_start:
    .incbin "../u-boot/u-boot.bin"

.balign 8
image_end:
