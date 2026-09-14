# Linux ACPI-only reference feasibility — 2026-09-10

## Purpose

Determine whether an already-local artifact can provide an independent
post-`ExitBootServices` ARM64 Linux control on the same AVF/GenieZone platform.
Such a control must boot through EDK2, consume the firmware ACPI tables, and
execute a real kernel/userspace path. A direct `vm run` serial payload is not
an ACPI or UEFI control.

## Read-only inventory

The only local ARM64 Linux-labelled payload is:

```text
tools/shell-serial-loopback/winavf-shell-serial-loopback.Image
size = 168 bytes
```

Its source, `tools/shell-serial-loopback/shell-serial-loopback.S`, explicitly
defines it as a disposable serial loopback probe. It has no disk, initrd,
filesystem, UEFI boot manager, or ACPI consumer; `vm-config.json` passes it
directly in the AVF `kernel` field with no disks. It checks only the legacy
16550 serial loopback and then requests PSCI `SYSTEM_OFF`.

No complete local ARM64 Linux UEFI/ACPI boot asset (EFI loader plus kernel,
initrd and root filesystem) was found in the active project workspace. No
local `qemu-system-aarch64`, `qemu-system-arm`, or `qemu-img` command is
available either, so there is no installed QEMU ARM64 reference environment.

## Result at the initial read-only audit

```text
LOCAL_LINUX_UEFI_ACPI_CONTROL_ASSET = NOT_AVAILABLE
LOCAL_QEMU_AARCH64_REFERENCE         = NOT_AVAILABLE
EXISTING_SERIAL_LOOPBACK_AS_ACPI_TEST = INVALID
```

Launching the 168-byte loopback now would be non-informative: it bypasses the
product EDK2-to-OS transition and does not validate the ACPI tables Windows
receives after EBS.

## Boundary

No VM was launched, and no firmware, Windows media, BCD, Android application,
or baseline image was changed.

Creating the proposed Linux control requires bringing in a standard ARM64
Linux UEFI boot asset and constructing a disposable boot medium/topology. That
is a new media/infrastructure branch rather than a continuation of the proven
Windows baseline, so it was intentionally not started without a separate
explicit decision.

## Asset acquisition after approval — 2026-09-11

After explicit approval, the official Debian Bookworm ARM64 `netboot.tar.gz`
was downloaded into `build-logs/linux-acpi-control-20260911/` and verified
against Debian's published SHA-256 manifest:

```text
netboot.tar.gz
SHA-256 = 48AEB468FEE03576CB0DF3FE6BAD97974ADE41F57A814FBA744A55E202BF9EAF
```

The extracted, checked inputs are Debian ARM64 `grubaa64.efi`, kernel and
initrd. `tools/linux-acpi-control/prepare-linux-acpi-control.ps1` creates a
disposable copy through Windows FAT32 tooling and immediately audits it. The
candidate has not yet been materialized, copied to Android, or run.

```text
LINUX_ACPI_ONLY_CONTROL_ASSETS = VERIFIED
LINUX_ACPI_ONLY_CANDIDATE      = PASS
LINUX_ACPI_ONLY_RUNTIME        = NOT_CONFIRMED
```

## One bounded product-topology runtime — 2026-09-11

The candidate was materialized through the Windows FAT32 driver and audited
successfully. It was transferred only as a reversible 24-range transactional
overlay and run exactly once on the product AVF topology. The source immutable
baseline SHA-256 was
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`; the
candidate raw SHA-256 was
`76FFCEEFCA0ECFC8900D0C5C70B47B5DF9B8DFBCF05F9E2D60C7DD9D9A1F14BB`; the
overlay SHA-256 was
`ACA05CE553342822DB7D727F77279E91C66CF6CBF13127642D60E03F445EE7BC`.

The control used Debian ARM64 GRUB, kernel and initrd with `acpi=force`, known
`ttyS0`, and explicit 16550 earlycon. Windows BCD and boot.wim were unchanged.
The real VM ran for 100 seconds after a forced app restart. Firmware emitted
successful `AVF_BDS_START_IMAGE \\EFI\\BOOT\\BOOTAA64.EFI` and image start
records followed by the established raw post-EBS `ER` boundary. The 10,367-byte
raw serial log then ended at `ER`, with no GRUB message, `Booting Linux`,
`Linux version`, `ACPI:`, `RSDP`, or Linux early-console line.

Serial silence is not an instruction-pointer observer, so this does not prove
the first Linux instruction did not run. It does establish that the independent
UEFI/ACPI consumer reached no observable Linux early-console milestone, so the
post-EBS silence is not established as WinPE/Setup-specific. Rollback restored
the external baseline hash exactly. Raw serial SHA-256:
`619500F9B395654341665844A1AAEB0CB4CF3FE81A8919B5ED284EDC6A1D0242`.

```text
LINUX_ACPI_ONLY_OFFLINE_AUDIT = PASS
LINUX_ACPI_ONLY_RUNTIME       = NOT_CONFIRMED
LINUX_KERNEL_EARLY_SERIAL     = NOT_OBSERVED
COMMON_POST_EBS_SERIAL_SILENCE= OBSERVED
BASELINE_ROLLBACK              = PASS
```

Runtime evidence: `build-logs/linux-acpi-runtime-20260911-160500/`.
