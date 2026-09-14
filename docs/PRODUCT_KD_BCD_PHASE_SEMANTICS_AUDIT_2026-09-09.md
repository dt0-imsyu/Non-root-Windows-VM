# Product KD BCD phase-semantics audit — 2026-09-09

## Scope

Read-only audit after the complete product-equivalent app-owned KD run. No VM
was launched and no Android setting/media, BCD, firmware, WIM, or driver was
changed. The local Codex process cannot open an offline BCD store without
elevation, so this audit uses the saved exact candidate enumeration,
hash-pinned construction scripts, product runtime evidence, and Microsoft
documentation.

## Exact candidate

The injected BCD candidate is 20 KiB, SHA-256
`DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11`.
Its retained enumeration establishes:

```text
{default}.bootdebug                 = Yes
{default}.debug                     = Yes
{default} inherits {bootloadersettings}
{bootloadersettings} inherits {globalsettings}
{globalsettings} inherits {dbgsettings}
{dbgsettings}.debugtype             = Serial
{dbgsettings}.debugport             = 1
{dbgsettings}.baudrate              = 115200
{bootmgr}.bootdebug                 = absent
```

The serial settings match the r11 platform contract: app-owned raw console
`ttyS0`, SPCR, DBG2, and COM1 use the same 16550 MMIO UART at `0x3f8`; byte
exact RX/TX is independently PASS.

## Microsoft stage model

Microsoft documents three separately enabled startup debug stages:

```text
{bootmgr}.bootdebug on  -> Windows Boot Manager
{default}.bootdebug on  -> Windows boot loader (Winload)
{default}.debug on      -> Windows kernel
```

`/dbgsettings serial debugport:1 baudrate:115200` configures transport but
does not enable any debugger by itself. The current candidate is consequently
a Winload/kernel KD configuration, not a Boot Manager KD configuration.

The product bridge gate is emitted by EDK2 immediately after it invokes the
Windows EFI image (`BOOTAA64.EFI`). It safely avoids U-Boot serial ownership,
but it occurs before there is proof that Boot Manager has handed off to
Winload. Therefore the current `{default}` bootdebug configuration is not
required to answer the host's initial `0x69` synchronization packets at that
gate.

## Reconciliation with runtime evidence

The completed product run did establish all transport prerequisites after the
gate:

```text
APP_OWNED_BINARY_TRANSPARENT_COM1 = PASS
ANDROID_BRIDGE_AUTHENTICATED      = PASS
IMAGE_AUDIT_GATE_OBSERVED         = PASS
KD_PIPE_CONNECTED                 = PASS
KD -> guest                       = 450 raw bytes
```

KD received no target packet. The raw UART capture stopped after
`CONVERT_AUDIT request` without complete `BES`. This means the candidate did
not reach an observable Winload/kernel KD response in the bounded run; it does
not prove a serial bridge fault or failed kernel entry.

The absent `{bootmgr}.bootdebug` is intentional, not an unnoticed defect. A
prior one-change shell A/B enabled it and observed deterministic early
divergence while still receiving no target KD packet. That shell topology does
not reproduce the product EBS boundary, so it cannot justify replaying the
same BCD variation on product media.

An explicit `{default}.dbgtransport=kdcom.dll` attempt did not persist in the
offline store. It is not an active product setting. Normal serial configuration
already selects the signed serial transport by debug type; no evidence says an
additional transport string would alter this product result.

## Result

```text
SERIAL_KD_BCD_SETTINGS             = PASS
WINLOAD_BOOTDEBUG_CONFIGURATION    = PASS
KERNEL_DEBUG_CONFIGURATION         = PASS
BOOTMGR_BOOTDEBUG                  = INTENTIONALLY_OFF
EXPECT_KD_REPLY_AT_IMAGE_AUDIT     = NO
WINDOWS_KD_HANDSHAKE               = NOT_OBSERVED
BCD_KD_VARIANT_BRANCH              = CLOSED
```

No new BCD, firmware, WIM, or bridge runtime is justified. The remaining
unknown is whether the BCD-enabled path reaches Winload/KD initialization at
all. Resolving it needs a new direct observer, such as vendor-privileged VMM
trace, or a specifically justified Windows debug configuration with an
independently observable stage—not another blind serial KD retry.

## Sources

- [Microsoft: BCDEdit `/bootdebug`](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--bootdebug)
- [Microsoft: BCDEdit `/dbgsettings`](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--dbgsettings)
- [Microsoft: serial kernel debugging setup](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/setting-up-a-null-modem-cable-connection)
- Existing A/B: `docs/SHELL_WINDOWS_KD_BOOTMGR_AB_RUNTIME_2026-09-07.md`

