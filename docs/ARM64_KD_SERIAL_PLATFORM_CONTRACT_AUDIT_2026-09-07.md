# ARM64 serial KD platform-contract audit — 2026-09-07

## Scope

Read-only source and evidence audit following the two shell-owned Windows KD
runs.  No VM was started.  No Android state, BCD, Windows image, firmware
source, or build artifact was changed.

## Question

Does the current ArmVirtKvmTool firmware describe the proven crosvm `ttyS0`
UART to Windows as an ARM memory-mapped, 16550-compatible COM debug port?

## Evidence and result

| Contract field | Evidence | Result |
| --- | --- | --- |
| Guest UART | U-Boot serial logs report `serial addr = 0x00000000000003f8`, width 1, shift 0, baud 115200. | PASS |
| Firmware access model | `ArmVirtKvmTool.dsc` selects `BaseSerialPortLib16550` and `PcdSerialUseMmio|TRUE`. | PASS |
| FDT-to-firmware handoff | `Fdt16550SerialPortHookLib` copies the early FDT console address into `PcdSerialRegisterBase`. | PASS |
| ACPI base address | The FDT serial parser takes the `stdout-path` node's `reg` address; the SPCR/DBG2 generators use that same `BaseAddress`. | PASS for the observed `0x3f8` topology |
| Address space | `ARM_GAS32()` explicitly uses ACPI `SystemMemory`, not x86 System I/O; this is the correct ARM representation of MMIO `0x3f8`. | PASS |
| UART subtype | `ns16550a` maps to DBG2 subtype `16550 with GAS` (`0x12`), byte access, 115200. Microsoft recommends this subtype for new MMIO 16550 platforms. | PASS |
| ACPI namespace link | DBG2 identifies `\\_SB_.COM0`; the paired generated SSDT creates and fixes up that same device, its `_CRS`, IDs, and interrupt. | PASS by generator construction |
| Interrupt | The exact FDT interrupt number was not preserved in a host artifact, but both SPCR and the COM0 SSDT receive it from the same parsed FDT record. | INCONCLUSIVE for the numeric value; no source-level split found |

The source is internally consistent: the exact FDT `stdout-path` serial record
feeds EDK2's 16550 driver, SPCR, DBG2, and the COM0 SSDT.  It does **not**
describe `0x3f8` as legacy x86 port I/O.

Microsoft's DBG2 documentation says Windows uses the DBG2 port type/subtype,
address, and ACPI namespace device to select and configure KD.  Its 16550
guidance specifically recommends subtype `0x12` (16550 with GAS) for MMIO
platforms such as ARM.  The BCD serial settings used here — COM1 and 115200 —
are also the documented defaults.

```text
ARM64_KD_SERIAL_PLATFORM_CONTRACT = PASS (source/evidence level)
UART_TTYS0_TO_ACPI_MAPPING        = PASS
SPCR_DBG2_GAS_MODEL               = PASS
ACTUAL_ACPI_TABLE_BYTES           = NOT_CAPTURED
WINDOWS_KD_HANDSHAKE              = NOT_OBSERVED
```

## What this rules out

There is no evidence for the tempting explanation that ARM Windows receives
an x86-style I/O-port COM1 description, a PL011 subtype, a baud mismatch, or a
DBG2 namespace omission.  The absent handshake therefore cannot be attributed
to any of those source-level errors.

This is not a proof that the dynamic table installation succeeded at runtime:
the final serialized SPCR/DBG2/SSDT bytes were never captured.  It also cannot
show whether Windows receives or accepts the first KD packet.

## One bounded next experiment, not performed

Do not change the firmware, product image, WIM, or Android app.  On a new
disposable shell clone, retain kernel serial KD exactly as already proved, but
set the signed Microsoft serial transport explicitly on `{default}`:

```text
dbgtransport = kdcom.dll
```

Keep `{bootmgr}.bootdebug` **off** for that run because the prior A/B showed it
changes Boot Manager behaviour before the normal UI.  Reuse the byte-exact
framed bridge, run once, and stop at the first target packet or timeout.  This
tests the only remaining low-risk BCD ambiguity without changing any signed
binary or platform description.

The exact candidate-preparation script is
`tools/shell-serial-loopback/prepare-kdcom-explicit-bcd.ps1`.  It refuses to
overwrite a file, pins the expected source BCD SHA-256, asserts explicit
`kdcom.dll`, and rejects an accidental `{bootmgr}.bootdebug` setting.

## Sources

- [Microsoft DBG2 specification](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/acpi-debug-port-table)
- [Microsoft ACPI table guidance](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/acpi-system-description-tables)
- [Microsoft serial KD settings](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--dbgsettings)
- [Microsoft SPCR specification](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/serial-port-console-redirection-table)
