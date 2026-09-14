# Linux direct EFI-stub v3 MMIO8 runtime — 2026-09-11

## Scope

This was one bounded 100-second product-topology runtime.  It changed only a
disposable media candidate's `EFI\\BOOT\\BOOTAA64.EFI` direct Linux launcher and
the added official Debian ARM64 `Image`/initrd payloads.  Its sole difference
from the executed v2 Linux EFI-stub candidate was the Linux early-console
option:

```text
v2: earlycon=uart8250,mmio32,0x3f8
v3: earlycon=uart8250,mmio,0x3f8
```

No Windows WIM/BCD/binary, EDK2 FD, Android application, or immutable Android
baseline byte was changed.  The v3 candidate was constructed with the Windows
FAT32 driver, audited offline, staged as a reversible transaction, and rolled
back after the one run.

## Offline gates

| Item | Result |
|---|---|
| Immutable baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| v3 candidate SHA-256 | `9260406B715EACA13CCC532A2E3CF9D6317562D680CCAFE261C37F3CD2C34FE5` |
| v3 launcher SHA-256 | `F3FEE2904150D53D309D220D3BF4D0F7597B81B63964A496DAB0A51D8B5C1DEE` |
| Launcher / architecture / embedded `mmio` | ARM64 PE / PASS |
| FAT32 and CHKDSK | PASS |
| Debian Image and initrd | exact expected SHA-256 / PASS |
| Windows BCD and BOOT.WIM | unchanged / PASS |
| Transaction patch SHA-256 | `2E0D3C876D67A45BB2B42086821F6EE840645674D2B41129B9EF7A493E001182` |
| Patch bytes / ranges | `218,105,840` / `26` |
| Overlay reconstructs candidate | PASS |

## Runtime evidence

Artifacts: `build-logs/linux-efi-stub-runtime-v3-mmio8-20260911-202844/`.
The raw serial SHA-256 is
`541F7E4325701F15777C6D14CC348B87D3354C0900ED95622170B7FECE98DA9F`.

The decisive raw sequence is:

```text
L0 → L1 → L2 → L3
EFI stub: Booting Linux Kernel...
EFI stub: Exiting boot services...
ER
[    0.000000] Booting Linux on physical CPU 0x0000000000
[    0.000000] Linux version 6.1.0-50-arm64 ...
[    0.000000] earlycon: uart8250 at MMIO 0x00000000000003f8
[    0.000000] ACPI: RSDP ...
[    0.000000] ACPI: SPCR: console: uart,mmio,0x3f8,115200
...
Select a language
```

The installer reached its interactive language-selection screen.  Thus Linux
executed natively after ExitBootServices, consumed the UEFI-provided ACPI
tables, initialized its 16550 early console, and reached userspace on the same
product AVF/GenieZone VM topology.

Further native-kernel records independently confirm the previously static
platform fields:

```text
arch_timer: cp15 timer(s) running at 13.00MHz (virt)
GICv3: CPU0: found redistributor 0 region 0:0x000000003ffd0000
Root IRQ handler: gic_handle_irq
psci: probing for conduit method from ACPI
psci: PSCIv1.0 detected in firmware
smp: Brought up 1 node, 1 CPU
```

## Transaction closure

The runner recorded the exact baseline hash before staging, exact patch hash
after Android staging, stopped the VM, pulled the raw serial, invoked launcher
rollback, and rehashed the external image.  There are no running VMs and the
post-rollback baseline SHA-256 exactly matches the immutable value above.

```text
LINUX_NATIVE_KERNEL_POST_EBS      = PASS
LINUX_ACPI_EARLY_INIT             = PASS
LINUX_EARLYCON_MMIO8              = PASS
LINUX_USERSPACE_INSTALLER         = PASS
POST_EBS_PLATFORM_FOR_LINUX       = PASS
WINDOWS_POST_EBS_FAILURE          = WINDOWS_SPECIFIC_OR_WINDOWS_CONTRACT
IMMUTABLE_BASELINE_RESTORED       = PASS
```

This does not identify the Windows failure location.  It does rule out a
generic post-EBS loss of CPU execution, RAM, GIC/timer functionality, ACPI
table availability, or the physical UART transport as a necessary explanation.
The next Windows work must be a narrowly evidence-backed Windows-specific
contract comparison, not another generic platform or Linux runtime.
