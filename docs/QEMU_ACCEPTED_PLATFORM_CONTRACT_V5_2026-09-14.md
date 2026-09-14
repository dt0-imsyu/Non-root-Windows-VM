# QEMU accepted-platform contract capture v5 — 2026-09-14

## Result

```text
QEMU_ACCEPTED_PLATFORM_CONTRACT_CAPTURE = PASS
QEMU_AVF_WINDOWS_CONTRACT_DIFFERENTIAL  = NO_ACTIONABLE_FIRMWARE_DELTA
WINDOWS_EARLY_PLATFORM_ROOT_CAUSE        = NOT_LOCALIZED
```

This was one diskless, QEMU-only capture.  It did not boot Windows, change the
Android product VM, touch the immutable product image, or create a product
firmware patch.  Its role was to capture the accepted machine contract of the
historical QEMU platform on which the same Windows ARM64 release reached
Setup, installed boot, and OOBE.

The capture is a strong negative result: the remaining QEMU↔AVF differences
are either faithful descriptions of two different backing machines, optional
late-platform facilities, or a feature which the product firmware is required
to advertise.  No field is simultaneously (1) a product contract violation,
(2) used plausibly before the silent Windows boundary, and (3) safely mutable
from product firmware without lying about the backing machine.

## One bounded control run

The disposable Termux/QEMU v5 command retained the established control:

```text
machine=virt,highmem=on,gic-version=3,its=on,virtualization=on
accel=tcg,thread=multi
cpu=cortex-a76, vcpus=4, RAM=4 GiB
```

Only the QEMU ESP's `\\EFI\\BOOT\\BOOTAA64.EFI` was replaced with the
20,480-byte `QemuContractProbe.efi`; the ESP was then attached read-only to
QEMU and a fresh variable-store copy was used.  The process returned `0` and
the raw serial stream ends in `QCP_DONE`.

| Artifact | SHA-256 |
|---|---|
| Raw serial | `F2FBDB01A08DF27BBE0B715B8544F8DC67810D5310FC0DC2F1C9C6FA93C5B69B` |
| Disposable QEMU ESP | `FB36E662C3D788AE8BE22BE6F85C2942282591FA25087E03AF5D8D9465F9B3FA` |
| Collector EFI | `1FA3A2BED35E7467EAB442EE24F239184C3C9BE58642DE415DBD6768A30F20AC` |

Evidence directory: `build-logs/qemu-contract-v5-20260914/`.

All captured `FACP`, `APIC`, `PPTT`, `GTDT`, `MCFG`, `SPCR`, `DBG2`, and
`IORT` tables have a zero ACPI checksum.  The collector also emitted all 37
EFI memory descriptors, including ten runtime descriptors, and its map ends
at `0x140000000`.

## Early contract comparison

| Contract item | QEMU accepted control | Product AVF / GenieZone | Assessment |
|---|---|---|---|
| CPU and counter | Cortex-A76, `CNTFRQ=62.5 MHz`, collector at EL2 | Host-derived CPU, `CNTFRQ=13 MHz`, P7 collector at EL1 | Real profile difference, but P7 found no product-only Windows-causal feature bit and AVF exposes no CPU-mask control. |
| FADT flags | `0x00100000` (hardware-reduced) | `0x00300000` (hardware-reduced plus low-power S0 idle) | **Not a product defect.** `ArmFadtGenerator.c` deliberately sets both bits. Microsoft states that hardware-reduced platforms must expose low-power S0 idle. Clearing it solely to imitate QEMU would be a false platform description. |
| PSCI | `ArmBootArch=0x0001` (SMC) | `ArmBootArch=0x0003` (HVC) | Different physical virtualization conduit. The product FDT, FADT, Linux ACPI boot, and synthetic post-EBS tests agree on HVC. An SMC substitution would be invalid. |
| GTDT PPIs | `29/30/27/26`; flags `0/4/0/0` | `29/30/27/26`; flags `6/6/6/6` from the live FDT plus Always-On | Different timer wiring/polarity metadata, not a translation mismatch. Product virtual `CNTV`/PPI27 is directly proven after EBS. The physical `CNTP` comparator is a real GenieZone defect, but the exact current WinPE writes only `CNTV_*`, so it is not the current direct cause. |
| GIC / topology | GICv3, four GICCs, redistributors, ITS, IORT | GICv3, one GICC, matching FDT redistributor range, no ITS/IORT | ITS and IORT are optional and PCI/MSI is later than the observed boundary. Advertising QEMU's ITS without a backed virtual ITS would be invalid. One-vCPU and eight-vCPU product controls already reject CPU count as the simple cause. |
| Serial description | PL011 at QEMU MMIO `0x09000000` | 16550 MMIO, SPCR/DBG2 aligned to the proved product console | Different UART implementation. Product raw UART survives the real Windows EBS return, so this does not explain the first silent boundary. |
| EFI memory placement | 4 GiB RAM starts at `0x40000000`; map ends at `0x140000000` | 4 GiB FDT RAM starts at `0x80000000`; map ends at `0x180000000` | Different but conventional Arm layouts. Product memory descriptors, runtime attributes, and Windows final EBS MapKey handoff were separately audited as valid. |

## Why the tempting FADT and GTDT changes are rejected

`LOW_POWER_S0_IDLE_CAPABLE` is Windows-visible, but it is not a free tuning
bit.  Microsoft documents it as the declaration of the low-power S0 model and
requires it when the ACPI Fixed Hardware Programming Model is absent.  The
product is a hardware-reduced Arm platform; its upstream Arm EDK2 generator
therefore intentionally emits it.  QEMU omitting the capability in this
specific control does not prove that the truthful product declaration is a
bug.

Likewise, replacing product GTDT flags with QEMU's values would claim a
different interrupt electrical model.  The product table is generated directly
from the same FDT timer interrupt flags used by EDK2, with the Always-On bit
added by the parser.  More importantly, P1 already proves the product's
actual Windows-relevant virtual timer PPI27, GIC re-arm, WFI wake, and reset
path after EBS.  There is no valid reason to replace that description merely
because QEMU's virtual interrupt has different flags.

## Architectural conclusion

The working QEMU machine demonstrates that the Windows release is viable on a
standards-conformant Arm virtual platform.  The product capture demonstrates
that its exposed firmware contract is internally coherent and that no single
QEMU field yields a safe, evidence-backed product firmware A/B.  This does
not prove the closed crosvm/GZVM/GenieZone layer is correct; it proves that
the remaining suspected defect is not repairable by blindly copying QEMU
ACPI, PSCI, timer, GIC, UART, or memory-map values into the product firmware.

```text
COPY_QEMU_ACPI_TO_AVF                 = REJECTED
RANDOM_PRODUCT_ACPI_GIC_TIMER_A_B     = REJECTED
STOCK_LOCAL_FIRMWARE_REPAIR_CANDIDATE = NONE
```

The next information source capable of producing a causal repair is a direct
observer or control owned below the public AVF contract: vendor GZVM/crosvm
execution tracing, a vendor CPU-feature profile control, or a vendor fix for
the known physical-timer virtualization defect.  Repeating Windows media,
BCD, KD, or arbitrary firmware table experiments cannot turn this capture into
a precise diagnosis.

## Sources

- Microsoft, [ACPI system description tables](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/acpi-system-description-tables)
- Microsoft, [hardware requirements for SoC platforms](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/hardware-requirements-for-soc-based-platforms)
- QEMU, [Arm virt machine documentation](https://www.qemu.org/docs/master/system/arm/virt.html)
- Project timer proof: `docs/ARM_GENERIC_TIMER_PLATFORM_CONTRACT_2026-09-12.md`
