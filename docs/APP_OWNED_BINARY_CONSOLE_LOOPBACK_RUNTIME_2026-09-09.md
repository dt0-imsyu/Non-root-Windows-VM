# App-owned binary console loopback — 2026-09-09

## Purpose

This one disposable non-Windows test proves the full app-owned AVF serial
transport, not merely the Java `OutputStream` object:

```text
WinAVF getConsoleInput()
  -> app-owned AVF console-in FD
  -> crosvm ttyS0 / 16550 at 0x3f8
  -> ARM64 echo guest
  -> crosvm console-out FD
  -> WinAVF getConsoleOutput()
```

It used no Windows media, disk, firmware, BCD, WIM, display service, shell VM,
or Binder call.  The guest was a 360-byte ARM64 Linux-Image echo loader built
from `android-app/kernel-first/console-binary-echo.S`.  It emits exactly one
`WINAVF_ECHO_READY\n` marker and then returns every received byte verbatim.

## One runtime

The app created `winavf-console-binary-echo-20260909` with one vCPU, 512 MiB,
`ttyS0`, captured output, and console-input support.  It had no disk and ran
only until the echoed pattern was captured.  The host sent the 4,096-byte
pattern `00..FF` repeated 16 times after the readiness marker.

| Check | Result |
|---|---|
| Ready marker | offset 0, exact |
| Raw capture length | 4,114 bytes (`18` marker + `4,096` echo) |
| Expected SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| Echo SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| Byte order and count | exact, `4096/4096` |
| `00`, `0A`, `0D`, `7F`, `80`, `FF` | preserved exactly |

The app's own result report and independent offline reconstruction both say
`byteExact=true`.

```text
APP_OWNED_BINARY_CONSOLE_RX = PASS
APP_OWNED_BINARY_CONSOLE_TX = PASS
APP_OWNED_BINARY_TRANSPARENT_COM1 = PASS (ttyS0 / 0x3f8)
```

## Cleanup

The initial app finally block attempted deletion while the VM was still
running. AVF correctly retained it.  The probe was then updated to call
`VirtualMachine.stop()` before `VirtualMachineManager.delete()`, and this exact
named disposable VM was removed.  Final verification:

```text
hidden_api_policy = null
Running VMs: []
product image SHA-256 = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

The raw capture, app report, offline verification, policy transaction, cleanup
logcat, and hash records are in
`Non-root-Windows-VM/build-logs/app-owned-binary-console-loopback-20260909/`.

## Boundary established

This removes the product-app RX plumbing uncertainty.  It does not itself
enable Windows KD: a separate, reversible product-equivalent BCD serial-debug
experiment and a raw WinDbg bridge are still required.  That next experiment
would modify Windows boot configuration and is intentionally not started by
this probe.
