# ADB shell → crosvm COM1 FD audit — 2026-09-07

## Scope

This was a host/shell descriptor audit only. No `vm run`, Windows image, BCD,
firmware, APK, or driver was touched. A minimal ARM64 Android helper reported
`fstat`, `isatty`, `poll`, and the exact `epoll_ctl(ADD)` result for stdin and,
separately, for a fresh `open("/proc/self/fd/0")` descriptor. The latter
mirrors `vm run --console-in /proc/self/fd/0`.

## Direct ADB results

| ADB transport | stdin seen by helper | direct `epoll_ctl(ADD)` | reopen `/proc/self/fd/0` | Verdict for current `--console-in` path |
|---|---|---|---|---|
| `adb exec-out` | `/dev/pts/0`, character TTY | PASS | opens the same PTY; PASS | pollable, but a PTY rather than raw socket |
| `adb shell -T` | `socket:[…]` | PASS | `open()` → `ENXIO` | do **not** pass `/proc/self/fd/0` as a path |
| ordinary interactive `adb shell` | `socket:[…]` | PASS | `open()` → `ENXIO` | do **not** pass `/proc/self/fd/0` as a path |

The important AOSP path is unambiguous:

```text
vm run, no --console-in
  -> duplicate_fd(io::stdin())
  -> Binder ParcelFileDescriptor
  -> virtmgr preserved FD
  -> crosvm serial input
```

With `--console-in <path>`, `vm run` instead calls `File::open(<path>)`.
Therefore the `shell -T` socket should be supplied by **omitting**
`--console-in`, not by naming `/proc/self/fd/0`.

## Exact cause of the KD runtime EPERM

The previous runner started `vm run` in an asynchronous background subshell.
Android `sh` assigned stdin for that background child to `/dev/null`. The same
helper run in that exact shell shape proves:

```text
FD0_LINK             = /dev/null
FD0_TYPE             = character
REOPEN_LINK          = /dev/null
FD0_EPOLL_CTL_ADD_RC = -1
ERRNO                = 1 (EPERM)
```

This exactly explains the crosvm `Failed to create wait context. Operation not
permitted` message. It does **not** show that Windows, KD, GenieZone, or the
shell-only COM1 feature is broken.

## Result

```text
ADB_EXEC_OUT_STDIN_POLLABLE       = PASS (PTY)
ADB_SHELL_T_STDIN_POLLABLE        = PASS (socket)
ADB_SHELL_T_VM_DEFAULT_STDIN_PATH = AVAILABLE (source-proven)
KD_PREVIOUS_RX_FAILURE             = BACKGROUND_STDIN_TO_DEV_NULL
```

## One next experiment

Do not run Windows yet. Run exactly one disposable non-Windows byte loopback
through `adb shell -T` with the VM command kept in the foreground and with
**no** `--console-in` argument. That takes the source-proven `duplicate_fd`
socket path. Require the existing 4,096-byte `00..FF` byte-exact result before
repeating the Windows KD clone.

## Evidence

The ARM64 helper source is
`tools/shell-serial-loopback/fd-poll-audit.c`; its current SHA-256 is
`7C774594EE09609902D9B3CE3643363FCDE74CAEDCD67D9A62F4B0C33026E8D8`.
All per-transport output is retained in
`build-logs/shell-kd-fd-audit-20260907/`.
The exact temporary device audit directory was removed after capture
(`CLEANUP_PASS`); no audit VM exists.

## Follow-up runtime: text-safe foreground input

The prescribed non-Windows loopback was then performed once.  Raw bytes fed
directly to ADB are transformed by its shell transport, so the host payload
was instead Base64-encoded and decoded into a foreground raw pipe on Android.
`vm run` again omitted `--console-in`, preserving the source-proven stdin
duplication path.  CID `2102` returned all 4,096 `00..FF` bytes exactly in the
Android raw console file and crosvm exited normally without the wait-context
error.

This proves the host-to-guest COM1 RX route and the guest-to-device raw TX
route.  It does not by itself provide an unframed raw live ADB stdout stream;
the reverse direction must also be text-framed before KD can use it.  Details:
`docs/SHELL_T_BASE64_COM1_LOOPBACK_RUNTIME_2026-09-07.md`.
