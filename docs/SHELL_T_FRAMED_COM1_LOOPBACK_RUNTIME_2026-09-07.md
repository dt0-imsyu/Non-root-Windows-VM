# Full text-framed shell COM1 loopback — 2026-09-07

## Result

A disposable non-Windows shell VM verified both directions of a byte-preserving
COM1 transport over ADB's text-like shell channel:

```text
host bytes -> continuous Base64 -> Android anonymous pipe -> crosvm ttyS0
ttyS0 bytes -> crosvm --console file -> Base64 O: records -> host bytes
```

The VM was CID `2106` (the final successful run), shut down normally, and no
Windows media, BCD, firmware, APK, or product baseline was touched.

| Check | Result |
|---|---|
| Source payload | 4,096 bytes (`00..FF` repeated) |
| Source SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| Decoded host output | 4,127 bytes (31-byte ready marker + payload) |
| Full output SHA-256 | `0C1B9F626639576BCF9BF31BAE0F595C9DE7C0DF0B2C6D4ECFE6CA48947F5597` |
| Returned payload SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| Byte comparison | exact (`4096 / 4096`) |
| crosvm wait-context error | absent |

## Corrected implementation facts

Android shell SELinux denies `mkfifo()` in `/data/local/tmp`.  The unsuccessful
FIFO attempt left a regular file, and crosvm correctly returned `EPERM` when
it tried to epoll that descriptor.  That result is a file-type error, not a
COM1 or platform-permission failure.

The final runner therefore uses the already-proven anonymous-pipe form:
`base64 -di | vm run` with no `--console-in`.  A small ARM64 tailer emits
appended bytes of the crosvm console file as `O:<Base64>` lines.  The host
decodes those records before comparing serial bytes.  This isolates all ADB
text conversion from the raw UART data.

## Status

```text
SHELL_BINARY_TRANSPARENT_COM1 = PASS (text-framed host bridge)
KD_HOST_TRANSPORT_PREREQUISITE = PASS
WINDOWS_KD_HANDSHAKE = INCONCLUSIVE (not retried)
```

The next runtime, if separately staged and authorized, is exactly one
shell-owned disposable Windows KD clone using this framed bridge.  It must not
reuse the removed Android staging directory or modify the immutable product
baseline.

