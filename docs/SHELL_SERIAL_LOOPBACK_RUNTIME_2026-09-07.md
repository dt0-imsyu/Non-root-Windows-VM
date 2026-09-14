# Shell serial loopback runtime — 2026-09-07

## Result

```text
SHELL_RAW_SERIAL_TX                 = PASS (guest -> shell startup marker)
SHELL_RAW_SERIAL_RX                 = INCONCLUSIVE for this regular-file attempt
SHELL_BINARY_TRANSPARENT_COM1       = SUPERSEDED_BY_PIPE_PASS
KD_DEBUG_ONLY_PATH                  = SUPERSEDED_BY_SHELL_PIPE_PATH
```

This was one disposable, shell-owned, non-Windows AVF VM. It did not access
the current WinAVF VM, Windows image, BCD, firmware, WIM, or Android app.

## Probe

The probe is a 168-byte ARM64 Linux-Image-envelope bare-metal payload. It
uses the established crosvm UART MMIO base `0x3f8`, emits a fixed readiness
marker, polls UART RX, echoes exactly 4,096 bytes, then requests PSCI system
off. It has no disk, filesystem, network, OS, or Windows component.

| Item | Value |
|---|---|
| Probe image SHA-256 | `97D71CDB8422050D824685BDD390F2D0567C68D60F5DFBE5043416FA2966BE0E` |
| ARM64 Image header | magic `0x644D5241`, declared size `168` — PASS |
| Input payload | 4,096 bytes, 16 repetitions of `00..FF` |
| Input SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| VM shape | shell-owned custom VM, one vCPU, 128 MiB, GenieZone, `ttyS0` input device |
| Actual VM creation | CID `2098`, state `STARTING` |

The payload contains every required edge value: `0x00`, `0x0A`, `0x0D`,
`0x7F`, and `0x80..0xFF`, with repeated streaming-length coverage.

## One runtime launch

The only actual run was bounded with `timeout 25`:

```text
/apex/com.android.virt/bin/vm run
  --name winavf-shell-serial-loopback-20260907
  --console <disposable>/uart-output.bin
  --console-in <disposable>/uart-input-4096.bin
  <disposable>/vm-config.json
```

The first two invocations stopped at JSON validation before any VM was created:
an array-valued `params` field and then a missing `platform_version`. A third
prelaunch attempt corrected the JSON but exposed an incorrect kernel pathname.
Those are retained as setup evidence only. The fourth invocation is the sole
VM runtime; it created CID `2098` and started GenieZone crosvm.

The decisive crosvm diagnostic was:

```text
ERROR devices::serial] Failed to create wait context.
Operation not permitted (os error 1)
```

The bounded client timed out after 25 seconds (`exit=124`). Post-run `vm list`
contains no CID `2098`; no corresponding crosvm remains. The only remaining
VM is unrelated Samsung Terminal Debian VM CID `2097`.

## Output audit

The output file is 31 bytes, SHA-256
`241F2276F3A657480C425FBF7432798270298C8B379D8E93BF126CF1C4D258FF`.
It contains only the probe startup marker:

```text
SHELL_SERIAL_LOOPBACK_READY\\r\\n
```

The marker's `\\r\\n` bytes are literal backslash characters in this first
probe build and are not host-side newline transformation. Most importantly,
the post-marker echo length is exactly zero: **0 / 4,096 input bytes returned**.
No pass criterion for RX, ordering, NUL preservation, CR/LF preservation,
high-bit preservation, no echo injection, or no dropped bytes was met.

## Safety and cleanup

The timeout removed the shell-owned VM. A read-only post-run process check
found no matching crosvm. The dedicated temporary directory
`/data/local/tmp/winavf-shell-serial-loopback-20260907` was then removed by
name after its captured output had been pulled; cleanup returned
`DISPOSABLE_CLEANUP=PASS`.

No persistent image, BCD, firmware, or existing VM state was changed.

## Corrected decision

The failure does **not** establish a Samsung permission or SELinux blocker.
The `--console-in` object was an ordinary file; crosvm's serial input thread
tries to register that descriptor in epoll, which Linux rejects with `EPERM`.
The output FD remains independently proven for guest TX, but the first run did
not test RX with a pollable descriptor.

Do not try PTY/`vm console`: it is still not a byte-transparent KD candidate.
The separately authorized inherited-pipe loopback subsequently passed its full
binary audit. This report remains evidence only for the regular-file failure;
the current authoritative result is
`docs/SHELL_SERIAL_PIPE_LOOPBACK_RUNTIME_2026-09-07.md`.

## Evidence

All command outputs, binary payloads, post-run VM/process checks, and device
preflight are retained in `build-logs/shell-serial-loopback-20260907/`.
Probe source and config are retained in `tools/shell-serial-loopback/`.
