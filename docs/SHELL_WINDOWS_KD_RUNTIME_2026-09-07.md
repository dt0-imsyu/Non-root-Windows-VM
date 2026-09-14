# Shell-owned Windows KD runtime — 2026-09-07

## Scope and result

Exactly one shell-owned Windows diagnostic VM was launched. It used only the
host-only disposable KD clone; the immutable WinAVF Android baseline was not
opened for write, and no WIM, firmware, Android APK, driver, test-signing, or
signed Windows binary was changed.

```text
SHELL_KD_MEDIA_CLONE        = PASS
BCD_BOOTDEBUG_CANDIDATE     = PASS
SHELL_KD_BCD_INJECTED       = PASS
SHELL_BINARY_TRANSPARENT_COM1 = PASS (Android-shell-local loopback only)
KD_HOST_NAMED_PIPE          = PASS
SHELL_KD_COM1_RX_AT_RUNTIME = FAILED (wait-context EPERM; FD type unverified)
WINDOWS_KD_HANDSHAKE        = INCONCLUSIVE
```

The result is deliberately **not** `NOT_OBSERVED`: crosvm could not register
the input descriptor supplied through the PC-to-`adb exec-out` bridge, so this
run never provided the proven duplex COM1 prerequisite to Windows.

## Media and topology

The staged image was the disposable host candidate:

```text
size    = 9,126,805,504 bytes
SHA-256 = 563DA01DB2DADDA202B8475D280E064F0C5C5B60DC07ACA61B6009C38147C196
```

Android rehashed the uploaded file before launch and returned the identical
digest. The raw shell configuration used the existing U-Boot wrapper, one
virtio block disk, `ttyS0`, 4 GiB RAM, and one vCPU. Raw `vm run` does not
express the APK's GPU/display configuration, so
`SHELL_VM_TOPOLOGY_EQUIVALENT = PARTIAL` remains true.

## Bridge evidence

Microsoft WinDbg package `1.2606.22001.0` supplied `kd.exe`. The bridge
created `\\.\pipe\winavf-kd-com1-20260907` before starting KD; its status log
records:

```text
PIPE_LISTENING_UTC    = 2026-09-07T15:18:42.6978792Z
KD_PIPE_CONNECTED_UTC = 2026-09-07T15:18:43.0965068Z
ADB_VM_LAUNCH_UTC     = 2026-09-07T15:18:43.1238962Z
```

KD opened that named pipe and emitted 448 bytes of normal serial synchronizing
traffic, but its complete diagnostic log ends at `Waiting to reconnect...`.
No KD packet from Windows was received.

## Exact runtime blocker

The shell VM was assigned CID `2100` and reached U-Boot, EDK2, Windows Boot
Manager, and `Loading files...`. The independent `vm run` log records the
decisive error at startup:

```text
ERROR devices::serial] Failed to create wait context. Operation not permitted (os error 1)
```

This is the same wait-context class previously proven for an unsuitable input
descriptor. The shell-local inherited anonymous pipe used by the successful
loopback is pollable; the descriptor inherited through `adb exec-out` was not
equivalent in this run and crosvm rejected it. Its exact FD type is still
unverified. Thus the host named-pipe bridge was connected locally, but it did
**not** establish a usable crosvm COM1 RX endpoint.

The bounded shell command returned `124` after 100 seconds. CID `2100` is
absent afterwards; only the unrelated Terminal Debian VM remains. The host
capture (`raw-serial-rx.bin`) exactly equals the Android-side serial file:

```text
length = 32,679 bytes
SHA-256 = 16009B109E1D786BC10AFFA2B12DDCB3D1304580FF41A1F007AE7F52CFE05A8A
```

No post-run repair, second Windows launch, or change to the clone was made.
After copying all evidence to the host, the exact temporary shell directory
`/data/local/tmp/winavf-kd-shell-20260907` was removed. `CLEANUP_PASS`; no
shell VM from this run remains.

## Evidence

All raw captures, debugger log, bridge status, staged-image transfer log,
shell VM stdout/stderr, and crosvm log are retained in:

```text
build-logs/shell-windows-kd-runtime-20260907/
```

The bounded bridge and device runner are retained at:

```text
tools/shell-serial-loopback/run-windows-kd-bridge.ps1
tools/shell-serial-loopback/run-windows-kd.sh
tools/shell-serial-loopback/vm-config-windows-kd.json
```

## One next experiment

Do not launch another Windows VM yet. First perform a read-only descriptor
audit comparing `adb exec-out`, non-PTY `adb shell -T`, and the successful
shell-local pipeline: determine the exact type and poll/epoll capability of
stdin inherited by `/proc/self/fd/0`. Only a host-to-shell path that delivers a
pollable pipe/socket to crosvm can make a repeat KD run interpretable.
