# Shell Windows KD runtime through framed COM1 — 2026-09-07

## Scope

Exactly one shell-owned Windows diagnostic VM was launched after the full
text-framed COM1 loopback passed.  Only the disposable KD clone was staged;
the immutable Android product baseline, firmware, WIM, APK, signed binaries,
and BCD on product media were not modified.

## Preflight

| Item | Result |
|---|---|
| Host disposable clone SHA-256 | `563DA01DB2DADDA202B8475D280E064F0C5C5B60DC07ACA61B6009C38147C196` |
| Android staged clone SHA-256 | exact match |
| COM1 bridge | prior 4,096-byte exact text-framed loopback PASS |
| KD endpoint | `kd.exe` named pipe connected before VM launch |
| Test VM | shell-owned CID `2108`, one vCPU, 4 GiB, `ttyS0` |

## Runtime evidence

The shell VM reached U-Boot, EDK2, Windows Boot Manager, and `Loading
files...`.  The bridge captured 32,679 bytes of guest serial output and
forwarded 483 bytes from KD to guest COM1.  The raw KD transmit stream begins
with repeating `69 69 69 69 06 ...` synchronization traffic, proving that KD
actually wrote through the named pipe, Base64 ingress, Android anonymous pipe,
and crosvm serial RX path.

The guest emitted no KD packet and WinDbg remained at `Waiting to reconnect`.
There was no crosvm `Failed to create wait context` error.  The bounded runner
was stopped after its 100-second limit; no second Windows run was performed.

| Artifact | SHA-256 / fact |
|---|---|
| `raw-serial-rx.bin` | `BF32E3450ED9245A080405E46363003896D426078C369F5E01785F5BDFB2C561` |
| `raw-serial-tx.bin` | `26A0DD64AFCC6C7F3C7D4C453B33C83CF5ACCA073EE15382D14B93949459BE74` |
| KD log | named pipe opened; no target response |
| crosvm COM1 RX | established; no EPERM |

## Result

```text
KD_HOST_NAMED_PIPE             = PASS
SHELL_BINARY_TRANSPARENT_COM1  = PASS
SHELL_KD_COM1_RX_AT_RUNTIME    = PASS
SHELL_WINDOWS_BOOT_PATH        = PASS
WINDOWS_KD_HANDSHAKE           = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY           = UNKNOWN
```

This run removes the previous FD/EPERM ambiguity.  It does **not** establish
why Windows did not answer: remaining explanations include bootdebug/KD BCD
semantics, COM1 selection during the loader/kernel debug transition, and the
fact that this shell-owned machine is only a partial topology match to product
WinAVF.  No change is justified from this one negative handshake.

## Cleanup

The exact Android temporary staging directory was removed immediately after
evidence extraction (`STAGING_CLEANUP_PASS`).  No test VM remains.  The
immutable product baseline was independently rehashed after cleanup and
exactly matches `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

## One next informative step

Read-only audit the exact BCD `bootdebug` / serial-debug settings against
Microsoft ARM64 KD requirements and the shell VM's COM1 mapping.  Do not rerun
Windows or alter product media until that configuration audit identifies a
single concrete discrepancy.

