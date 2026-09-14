# r11 debug-UART alignment — 2026-09-08

## Scope

This was one bounded, firmware-only A/B after the r10 runtime table audit.
Windows media, BCD, drivers, Android APK, AVF configuration, and the immutable
external image were not changed. The test changed exactly one 2 MiB firmware
range temporarily and rolled it back immediately after the single run.

## One platform-scoped change

`ArmVirtPkg/KvmtoolCfgMgrDxe/ConfigurationManager.c` now retains the parsed
`EArchCommonObjConsolePortInfo` and supplies a copied descriptor for
`EArchCommonObjSerialDebugPortInfo`. The dynamic repository copies the data,
so no parser-owned memory is retained. This is restricted to Kvmtool; the
generic FDT serial parser is unchanged.

Consequently:

```text
console FDT object       -> SPCR -> 0x3F8  (unchanged)
copied console object    -> DBG2 -> 0x3F8  (r11 change)
copied debug object      -> COM0._CRS fixup -> 0x3F8 (source-proven)
```

The final `COM0._CRS` value is a source-proven consequence of the same
Configuration Manager object; r11 does not add a general AML decoder.

## Build and integrity

| Item | Value |
|---|---|
| build replay | `R4_BUILD_ENV_REPLAY = PASS`, `- Done -`, 00:03:17 |
| build log | `build-logs/edk2-r11-debug-uart-align-20260908-201602.log` |
| r11 FD | `firmware-work/edk2/artifacts/KVMTOOL_EFI-r11-debug-uart-align.fd` |
| r11 FD SHA-256 | `9ED3DD035116A39FEAC7C79A9C0C9AC640EA222D499A8EC3B1C6FCEE1ADFE72F` |
| immutable baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| patch | `build-logs/runtime-debug-uart-r11-20260908/runtime-r11-debug-uart-align-firmware.patch` |
| patch SHA-256 | `0D78B91BDA1B2C3EB241CF8B1D731280DB511958B3B196662046C76AF7E8364E` |
| patch size | `4,194,436` bytes |
| changed range | offset `7,250,927,616`, length `2,097,152` |
| old range SHA-256 | `3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995` |
| rollback simulation | PASS: embedded old/new range hashes exactly validate |

The external immutable baseline SHA-256 was checked before application and
again after rollback; both results were exact matches. The launcher then
reported: `Small image patch rolled back and the runtime image was verified.`

## Runtime evidence

| Item | Value |
|---|---|
| raw serial | `build-logs/runtime-debug-uart-r11-20260908/runtime-r11-debug-uart-align.raw-serial.log` |
| raw serial size | `1,290,837` bytes |
| raw serial SHA-256 | `503FD98CE183C581C4E09232EC782E282E1EC8C5176F9904792BC4890BF8822C` |
| rollback UI evidence | `build-logs/runtime-debug-uart-r11-20260908/runtime-r11-after-rollback-ui.xml` |
| rollback UI SHA-256 | `C3B875CED945314C98C8FA68EBC786C363F20028140DB5A9A3E165782BFDB3E3` |

The installed pre-Boot-Manager records were:

```text
SP=00,20,00,01,00000000000003F8,08,00000020,07
DG=8000,0012,00,20,00,01,00000000000003F8,N=\_SB_.COM0?
XR=02,1,1
...
BES
```

`SP` stayed at the observed console UART `0x3F8`; `DG` changed from r10's
`0x2F8` to `0x3F8`. `XR=02,1,1` again proves that the installed XSDT contains
both SPCR and DBG2. The raw log reached the complete `BES` marker at offset
`1,290,834`; `VA0`, `VA1`, and `VA2` remained absent.

## Result

```text
ACPI_DBG2_CONSOLE_ALIGNMENT = PASS
SPCR_CONSOLE_UART           = 0x3F8
DBG2_DEBUG_UART             = 0x3F8
EXIT_BOOT_SERVICES_RETURN   = PASS (BES)
WINDOWS_KD_HANDSHAKE        = NOT_TESTED_BY_R11
```

The old KD negative result cannot now be attributed to the r10 UART identity
mismatch. The single next diagnostic, if separately authorized, is one
**disposable shell-owned Windows KD run** using this r11 firmware range and
the already audited serial-KD BCD candidate. It must retain the framed,
byte-exact COM1 bridge and must not modify the Android product baseline.
