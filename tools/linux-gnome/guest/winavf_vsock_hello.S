/*
 * Tiny, libc-free Linux/ARM64 AF_VSOCK listener for the disposable Ubuntu
 * initramfs.  It is intentionally only a transport probe: accept an Android
 * AVF connectVsock() client on port 4051, return a fixed 16-byte LVH1 record,
 * and leave an independent marker on ttyS0.
 */

        .global _start
        .text

/* Linux AArch64 syscall ABI: x8=syscall number, x0..x5=arguments. */
_start:
retry:
        mov     x0, #40                 // AF_VSOCK
        mov     x1, #1                  // SOCK_STREAM
        mov     x2, #0
        mov     x8, #198                // __NR_socket
        svc     #0
        tbnz    x0, #63, sleep_retry
        mov     x19, x0

        adr     x1, sockaddr_vm
        mov     x0, x19
        mov     x2, #16                 // sizeof(struct sockaddr_vm)
        mov     x8, #200                // __NR_bind
        svc     #0
        tbnz    x0, #63, close_retry

        mov     x0, x19
        mov     x1, #1
        mov     x8, #201                // __NR_listen
        svc     #0
        tbnz    x0, #63, close_retry

        mov     x0, #1                  // stdout inherited from /dev/console
        adr     x1, listen_marker
        mov     x2, #10
        mov     x8, #64                 // __NR_write
        svc     #0

accept_again:
        mov     x0, x19
        mov     x1, #0
        mov     x2, #0
        mov     x8, #202                // __NR_accept
        svc     #0
        tbnz    x0, #63, accept_again
        mov     x20, x0

        mov     x0, x20
        adr     x1, hello_record
        mov     x2, #16
        mov     x8, #64
        svc     #0

        mov     x0, #1
        adr     x1, hello_marker
        mov     x2, #9
        mov     x8, #64
        svc     #0

        mov     x0, x20
        mov     x8, #57                 // __NR_close
        svc     #0
        b       accept_again

close_retry:
        mov     x0, x19
        mov     x8, #57
        svc     #0
sleep_retry:
        mov     x0, #1
        adr     x1, retry_marker
        mov     x2, #7
        mov     x8, #64
        svc     #0
        adr     x0, retry_delay
        mov     x1, #0
        mov     x8, #101                // __NR_nanosleep
        svc     #0
        b       retry

        .balign 8
sockaddr_vm:
        .hword  40                      // svm_family = AF_VSOCK
        .hword  0
        .word   4051                    // svm_port
        .word   0xffffffff              // VMADDR_CID_ANY
        .word   0
retry_delay:
        .quad   1                       // struct timespec.tv_sec
        .quad   0                       // struct timespec.tv_nsec
listen_marker:
        .ascii  "LV:LISTEN\n"
hello_marker:
        .ascii  "LV:HELLO\n"
retry_marker:
        .ascii  "LV:RETRY\n"
hello_record:
        .ascii  "LVH1"
        .word   1                       // protocol revision (little endian)
        .word   0                       // status = success
        .word   1                       // capability: one-keyframe probe
