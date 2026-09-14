# r10 installed ACPI serial audit — 2026-09-08

## Scope

This was the one authorized firmware-only A/B. It used no Windows-media, BCD,
driver, Android APK, or AVF configuration change. r10 adds only pre-Boot-Manager
raw-UART observation of the installed RSDP/XSDT, SPCR, and DBG2 records. The
launcher applied one self-verifying firmware range, ran the VM once, and rolled
that range back.

## Integrity and rollback

| Item | Value |
|---|---|
| immutable baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| r10 FD | `firmware-work/edk2/artifacts/KVMTOOL_EFI-r10-acpi-serial.fd` |
| r10 FD SHA-256 | `161C15E93B1FB1E7E7E266702973EFDB012829049B5FB4458F79F7795EB06D63` |
| patch SHA-256 | `90F4F0333969B37C296AC09B67C42725A2861877F762C7E7F6AD3C543CACA29E` |
| patch size | `4,194,436` bytes |
| changed range | offset `7,250,927,616`, length `2,097,152` |
| raw serial | `build-logs/runtime-acpi-serial-r10-20260908/runtime-r10-acpi-serial.raw-serial.log` |
| raw serial SHA-256 | `7681B52DB4E39B814F51F7DAFBD264D07269A7E3FE16E909A139F42BA2928375` |

Before the run, the external immutable source image was independently hashed
on the tablet and matched the expected baseline. The patch bundle contains the
original 2 MiB firmware bytes and passed an in-memory apply/rollback simulation:
both embedded range hashes validate, the replacement equals the r10 FD, and
restoring the old bytes reproduces the baseline range hash
`3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995`.

After the run the launcher reported: `Small image patch rolled back and the
runtime image was verified.` This is retained in
`build-logs/runtime-acpi-serial-r10-20260908/runtime-r10-after-rollback-ui.xml`.
The external immutable source image was then independently rehashed again and
matched the exact baseline SHA-256 above. The staging patch was removed by the
launcher.

## Runtime evidence

The raw records occur immediately before the normal BDS ACPI audit and before
the Windows boot image is launched:

```text
A0
SP=00,20,00,01,00000000000003F8,08,00000020,07
DG=8000,0012,00,20,00,01,00000000000002F8,N=\_SB_.COM0?
XR=02,1,1
...
BES
```

`XR=02,1,1` means RSDP revision 2 and that the installed XSDT references both
SPCR and DBG2. `BES` is the familiar complete post-return EBS sequence; it is
the final three bytes of the raw serial capture. `VA0`, `VA1`, and `VA2` remain
absent, as in r9.

| Record | Installed value |
|---|---|
| SPCR console GAS | SystemMemory, width 32, byte access, base `0x3F8` |
| SPCR interrupt / baud enum | GIC interrupt `32`, `115200` |
| DBG2 debug device | serial port type `0x8000`, 16550-with-GAS subtype `0x0012` |
| DBG2 debug GAS | SystemMemory, width 32, byte access, base `0x2F8` |
| DBG2 namespace | `\_SB_.COM0` (the trailing `?` is the diagnostic rendering of the NUL) |

## Interpretation

The different bases are deliberate outputs of the DynamicTables FDT parser,
not a malformed SPCR record. `SerialPortParser.c` maps the FDT `stdout-path`
node to `EArchCommonObjConsolePortInfo`, then maps the first serial node that
is *not* the console to `EArchCommonObjSerialDebugPortInfo`. `SpcrGenerator.c`
consumes the former, while `Dbg2Generator.c` consumes the latter. The same
debug-port object fixes up the `\\_SB_.COM0._CRS` address in
`SsdtSerialPortFixupLib.c`. The r10 raw observer did not execute a general AML
decoder, so `COM0._CRS = 0x2F8` is a source-proven consequence of the same
runtime FDT object, rather than an independently decoded AML record.

Thus the earlier source-only assumption that SPCR and DBG2 named one UART was
incomplete. Runtime tables prove two UART identities:

```text
console / observed product serial bridge : 0x3F8
ACPI DBG2 debug UART                    : 0x2F8
```

This is a concrete explanation for the completed shell KD runs: binary
transport was proved on the console bridge, but the ACPI debug path offered to
Windows is a distinct UART. r10 does **not** prove whether crosvm exposes a
usable RX/TX backend for the second UART, nor that Windows selects DBG2 rather
than the BCD COM setting on every boot phase. It is an actionable
serial-topology finding, not proof of the post-EBS hang cause.

## Result and one next experiment

```text
INSTALLED_ACPI_SERIAL_TOPOLOGY = PASS
SPCR_CONSOLE_UART              = 0x3F8
DBG2_DEBUG_UART                = 0x2F8
WINDOWS_KD_HANDSHAKE            = NOT_OBSERVED (prior completed runs)
```

The one most informative next experiment is a **shell-only, disposable
non-Windows loopback on the crosvm backend for the second (`0x2F8`) UART**. It
must prove byte-exact RX and TX before any further Windows KD run. If shell
tooling cannot expose that backend, the next candidate is a separately
authorized firmware-only A/B that makes DBG2/COM0 describe the already-proved
`0x3F8` console UART; it must not be applied automatically.
