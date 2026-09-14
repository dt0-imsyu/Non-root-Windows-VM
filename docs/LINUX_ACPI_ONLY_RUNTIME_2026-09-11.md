# Linux ACPI-only product control runtime — 2026-09-11

## Question

Can an independent ARM64 Linux UEFI/ACPI consumer reach a visible post-EBS
kernel milestone on the product AVF/GenieZone topology that leaves Windows
silent after `ER`?

## Fixed scope

- One disposable media overlay only: no firmware, Android app, Windows BCD,
  Windows WIM, driver, or system-setting modification.
- Debian Bookworm ARM64 GRUB, kernel, and initrd.
- Explicit GRUB kernel arguments:
  `acpi=force console=ttyS0,115200n8 earlycon=uart8250,mmio32,0x3f8
  ignore_loglevel loglevel=7`.
- One 100-second run only, with no automatic retry.

## Preflight

```text
immutable baseline SHA-256
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7

candidate raw SHA-256
76FFCEEFCA0ECFC8900D0C5C70B47B5DF9B8DFBCF05F9E2D60C7DD9D9A1F14BB

transactional overlay SHA-256
ACA05CE553342822DB7D727F77279E91C66CF6CBF13127642D60E03F445EE7BC

overlay ranges / changed payload bytes
24 / 100663296

FAT32, ARM64 PE, GRUB ACPI-force and serial/earlycon checks
PASS
```

The disposable candidate replaced only its `EFI/BOOT/BOOTAA64.EFI` with Debian
GRUB and added GRUB modules, a Debian kernel and an initrd. The original
Windows BCD and boot.wim hashes were checked unchanged.

## Runtime evidence

The runner verified the external baseline SHA, staged the exact overlay, and
force-stopped WinAVF before launch so Android could not merely foreground an
existing activity. The VM then ran for 100 seconds. The 10,367-byte raw serial
file SHA-256 is
`619500F9B395654341665844A1AAEB0CB4CF3FE81A8919B5ED284EDC6A1D0242`.

Its terminal records are:

```text
AVF_BDS_START_IMAGE \EFI\BOOT\BOOTAA64.EFI fs=0
IMAGE_AUDIT load exit status=Success ...
IMAGE_AUDIT start enter ...
ER
```

There is no GRUB error, `Booting Linux`, `Linux version`, `ACPI:`, `RSDP`, or
Linux early-console output after `ER`. The established firmware ACPI audit
printed valid FADT/MADT/GTDT/RSDP/XSDT records before GRUB was started.

## Classification

```text
LINUX_ACPI_ONLY_RUNTIME   = NOT_CONFIRMED
LINUX_KERNEL_EARLY_SERIAL = NOT_OBSERVED
COMMON_POST_EBS_SERIAL_SILENCE = OBSERVED
```

This is deliberately not labelled `kernel entry = FAIL`: serial silence does
not directly observe the program counter. It does reject the weak hypothesis
that the behaviour is uniquely a Windows Setup or WinPE user-mode problem.

## Cleanup

The app was stopped, and launcher rollback reported `RESULT=PASS`. The Android
external baseline was immediately rehashed and exactly restored to
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

Artifacts: `build-logs/linux-acpi-runtime-20260911-160500/`.

## One next experiment

Do not alter Windows Setup. A future diagnostic must independently observe the
early OS handoff (or obtain a privileged vCPU PC/exception observer); random
WIM, BCD, ACPI, GIC, or timer changes are not supported by this result.
