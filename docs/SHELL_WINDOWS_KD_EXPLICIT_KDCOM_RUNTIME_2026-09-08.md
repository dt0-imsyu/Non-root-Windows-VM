# Explicit `kdcom.dll` serial KD A/B — 2026-09-08

## Scope

One shell-owned disposable Windows diagnostic VM was launched.  Relative to
the preceding valid shell KD candidate, the only intended Windows-media delta
was the explicit BCD element:

```text
{default}.dbgtransport = kdcom.dll
```

`{bootmgr}.bootdebug` was absent.  No product Android image, WIM, firmware,
APK, driver, test-signing setting, or signed Windows binary was changed.

## Offline evidence

| Item | SHA-256 / result |
| --- | --- |
| Input disposable clone | `563DA01DB2DADDA202B8475D280E064F0C5C5B60DC07ACA61B6009C38147C196` |
| Injected BCD read-back | `034362E7531FF242E32F24F1ABD37EBECA05CC888981D95094E7986A75521784` |
| New disposable raw clone | `AFD59943DFCC16048E767F66E4620215739B2E640FC3C3B1316D905408E4172B` |
| `BOOTAA64.EFI` before/after | exact, `EFCC88441775A1ECEF644E05A52D7A01DC98388EA4426F133B9132CBE1483A19` |
| ESP / BCD mtools audit | PASS |
| Device rehash before launch | exact `AFD59943...E4172B` |

The injected BCD's saved `bcdedit /enum all` output contains serial COM1 at
115200, `{default}.bootdebug = Yes`, `{default}.debug = Yes`, and
`dbgtransport kdcom.dll`.

## Runtime

The framed byte-exact bridge opened its named pipe before launching the shell
VM.  KD connected and transmitted 513 serial bytes.  The shell VM acquired
CID `2111`; raw UART reached Windows Boot Manager and `Loading files...`.
The bridge collected 32,678 UART bytes (SHA-256
`42AD0906EC4E3F1CE66AB8227AF7651A54A5472251E3938AFDD2DCD06A7D204C`).

KD received no target packet and remained at `Waiting to reconnect...` until
the bounded bridge timeout.  There was no crosvm wait-context/EPERM error.

```text
EXPLICIT_KDCOM_BCD_CONFIGURATION = PASS
SHELL_KD_COM1_RX_AT_RUNTIME      = PASS
SHELL_WINDOWS_BOOT_PATH          = PASS (through Loading files...)
WINDOWS_KD_HANDSHAKE             = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY             = UNKNOWN
```

This removes the remaining low-risk BCD ambiguity: explicitly selecting the
Microsoft-signed `kdcom.dll` transport does not produce a target handshake.
It does not prove whether Windows reaches kernel KD initialization.

## Cleanup

The exact temporary shell staging directory was removed; `vm list` is empty.
The immutable product baseline remains exact:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

All useful evidence is retained in
`build-logs/shell-windows-kd-kdcom-runtime-20260907/`.  An interrupted
recursive evidence pull left one incomplete 2,417,426,432-byte copy of the
temporary raw image under its `device/` subdirectory; it is not evidence and
was not used for runtime.

## Next step

Do not repeat serial-KD BCD variants.  The remaining direct-observer routes
are vendor-privileged VMM/GZVM tracing or a runtime ACPI-table capture; neither
is justified as another blind KD retry.
