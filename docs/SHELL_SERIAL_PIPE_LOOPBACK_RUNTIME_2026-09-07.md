# Shell serial pipe loopback runtime — 2026-09-07

## Result

```text
SHELL_RAW_SERIAL_TX           = PASS
SHELL_RAW_SERIAL_RX           = PASS
SHELL_BINARY_TRANSPARENT_COM1 = PASS
ADB_SHELL_BIDIRECTIONAL_COM1  = YES (shell-created VM only)
KD_DEBUG_ONLY_PATH            = AVAILABLE (diagnostic shell-VM path)
KD_HOST_BRIDGE                = NOT_YET_RUN
SHELL_VM_TOPOLOGY_EQUIVALENT  = PARTIAL
```

One disposable, non-Windows, shell-owned GenieZone VM was launched. No WinAVF
VM, Windows disk, BCD, WIM, firmware, Android APK, or system policy was
modified.

## Why the pipe was used

The preceding test supplied a regular file to `--console-in`; crosvm cannot
add such a descriptor to epoll. Android shell was also unable to create a
named FIFO in `/data/local/tmp` before VM creation. The AOSP `vm run` command
opens the requested `--console-in` pathname using `File::open()`. Passing
`/proc/self/fd/0` while its standard input is an inherited anonymous pipe gives
crosvm a pollable pipe descriptor without a PTY or a named FIFO.

The runtime crosvm argument proves that exact descriptor type:

```text
input=/proc/self/fd/27 (pipe:[4923896]),hardware=serial,num=1
```

There was no `Failed to create wait context` message. crosvm reported a normal
PSCI-requested shutdown and `exiting with success`; the client returned
`VM_EXIT=0`.

## Byte audit

The same 168-byte ARM64 bare-metal UART probe as the first loopback was used.
It emits a 31-byte fixed marker, waits for exactly 4,096 received bytes, echoes
each byte, then requests PSCI system-off. The pipe writer withheld the payload
until the marker appeared in the independent output file.

| Check | Result |
|---|---|
| Guest marker | exact 31 bytes — PASS |
| Input payload | 4,096 bytes, 16 repeats of `00..FF` |
| Echo length | `4096 / 4096` — PASS |
| Ordering / added or dropped bytes | exact equality — PASS |
| `0x00`, `0x0A`, `0x0D`, `0x7F`, `0x80..0xFF` | contained and exact — PASS |
| Payload SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| Echo SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| Full output length / SHA-256 | `4127`; `0C1B9F626639576BCF9BF31BAE0F595C9DE7C0DF0B2C6D4ECFE6CA48947F5597` |

The only persistent tablet state touched was a dedicated temporary shell
directory. It was removed after evidence extraction:

```text
DISPOSABLE_CLEANUP = PASS
```

The post-run VM listing contains only unrelated Samsung Terminal Debian VM CID
`2097`; the disposable CID `2099` and its crosvm process are absent.

## Scope of the KD conclusion

This proves a byte-transparent serial path between a shell process and UART
`hardware=serial,num=1` in a shell-created AVF VM. It does not export RX for
the app-owned production WinAVF VM and does not make that VM topology
equivalent. A host WinDbg bridge has not yet been connected, but it can use the
same inherited-pipe pattern through a binary-safe `adb` subprocess; it needs no
root or policy bypass. A separate approval is required before creating a
Windows diagnostic clone or changing its BCD bootdebug settings.

## Evidence

Raw files, crosvm/VM logs, byte audit, and cleanup evidence are in
`build-logs/shell-serial-fifo-loopback-20260907/` (the directory also retains
the FIFO creation prelaunch failure; the sole successful VM run is the
`pipe-*` set of files). The reproducible guest-side runner is
`tools/shell-serial-loopback/run-pipe-loopback.sh`.
