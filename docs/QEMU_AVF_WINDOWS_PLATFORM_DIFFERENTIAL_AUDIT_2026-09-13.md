# QEMU ↔ WinAVF/GenieZone Windows platform differential audit — 2026-09-13

## Scope

This began as a read-only comparison of the preserved working Termux/QEMU
Windows control and the current WinAVF/GenieZone product platform.  The
previously missing QEMU ACPI/EFI snapshot was subsequently captured by the
single diskless QEMU v5 control on 2026-09-14.  It touched no product byte.

The QEMU control is valuable evidence that Windows 11 ARM64 can reach Setup,
installed boot, and graphical OOBE on this tablet. It is **not** a byte-for-byte
machine-model clone of the product VM, and the retained August evidence does
not preserve an ACPI-table dump or CPU-ID-register dump from that exact run.
Therefore this audit distinguishes configuration-proven differences from
runtime values that still require a later QEMU capture.

## Established controls

| Control | Result | Evidence |
|---|---|---|
| QEMU Windows Setup | PASS (historical) | `tabs11-windows-research/reports/TEMPORARY_REPORT_2026-08-13.md` |
| QEMU installed Windows / OOBE user-mode | PASS (historical) | `tabs11-windows-research/reports/TEMPORARY_REPORT_2_2026-08-13.md`, `docs/HISTORICAL_QEMU_WINDOWS_25H2_CONTROL_2026-09-13.md` |
| Product Windows Boot Manager / real EBS return | PASS | `STATE.md` and r9/r11 evidence |
| Product Windows post-EBS / WinPE | NOT CONFIRMED | existing product runtime evidence |
| Product Linux ACPI kernel to installer userland | PASS | `docs/LINUX_EFI_STUB_V3_MMIO8_RUNTIME_2026-09-11.md` |

## Contract comparison

| Field | Working QEMU control | Product AVF / GenieZone | Assessment before WinPE |
|---|---|---|---|
| CPU profile | Explicit `-cpu cortex-a76` | Public AVF configuration selects only vCPU topology; crosvm receives a host-derived ARM profile | **Windows-relevant difference.** The product Linux kernel detects ECV, E0PD, WFxT, stage-2 force write-back, hardware dirty-bit management, BTI, PAuth, RAS, LSE and other extensions. This is a materially newer feature surface than a fixed Cortex-A76 model. |
| Arm Virtualization Extensions | Explicit `-machine virt,...,virtualization=on` | Product firmware and Linux execute at EL1 under GenieZone; P7 records `ID_AA64PFR0_EL1=0x1201011023111111` | **Windows-relevant but not causal.** Both P7 and QEMU advertise EL2 in PFR0. Public AVF still exposes no EL2/CPU-model selection. |
| vCPUs | Explicit four | One and eight both tested; both reach EBS and neither gives a post-EBS Windows witness | Simple CPU-count explanation **refuted**. |
| GIC | GICv3 explicitly requested; QEMU `its=on` | GICv3; no ITS entry and no IORT delivered to Windows | Different but **not a valid local repair A/B**. ITS is optional; advertising one without actual virtual ITS hardware would violate the contract. PCI/MSI is also later than the observed boundary. |
| Generic timer | QEMU implementation; exact frequency/register values not retained | 13 MHz virtual counter; virtual PPI27 and WFI wake pass post-EBS | Product virtual timer is **proven live**. The physical comparator PPI30 defect is real but the exact WinPE uses `CNTV_*`, not `CNTP_*`. |
| PSCI conduit | QEMU virt normally supplies its own PSCI environment; exact captured conduit absent | FADT and FDT agree on PSCI/HVC; Linux reaches userland | Product HVC contract **passes**; changing it to imitate QEMU is not justified. |
| UART | QEMU virt has PL011; serial is a QEMU file backend | Product is FDT 16550 MMIO at `0x3f8`; installed SPCR/DBG2 alignment was verified | Different but serial itself works through EBS. No direct Windows-causal mismatch identified. |
| Display | `ramfb` | GOP pre-EBS → WAVF; virtio-GPU later | Later than the early silent boundary. |
| System disk | NVMe | UEFI-exposed FAT32/virtio boot medium | Windows has already loaded `boot.wim` and returned from EBS. May matter later, but is not an evidence-backed explanation for the first silent boundary. |
| ACPI / EFI memory map / SMBIOS | v5 checksum-valid FADT/MADT/GTDT/SPCR/DBG2/PPTT/IORT/MCFG plus 37-descriptor EFI map captured | Product tables and FDT-derived MADT/GTDT/FADT internally consistent | **No actionable product delta.** The detailed result is `QEMU_ACCEPTED_PLATFORM_CONTRACT_V5_2026-09-14.md`. |

## Concrete outcome

```text
QEMU_AVF_DIFFERENTIAL_AUDIT                = PARTIAL
QEMU_AVF_CPU_FEATURE_PROFILE_DIFFERENCE    = CONFIRMED
QEMU_AVF_EL2_EXPOSURE_DIFFERENCE            = NOT_A_RAW_CAPABILITY_DIFFERENCE
QEMU_AVF_CPU_COUNT_AS_SIMPLE_CAUSE          = REFUTED
QEMU_AVF_ITS_AS_VALID_PRODUCT_A_B           = NOT_JUSTIFIED
QEMU_AVF_TIMER_AS_DIRECT_CURRENT_WINPE_CAUSE = REFUTED
QEMU_AVF_ACPI_MEMORYMAP_SMBIOS_DIFF         = CAPTURED_NO_ACTIONABLE_DELTA
```

The CPU-profile difference is the only newly ranked *early* mismatch. P7 now
confirms the product values rather than inferring them from Linux. It is still
not a causal conclusion: Windows may never consume a product-only feature
before the stall. Crucially, `VirtualMachineConfig` exposes only
`CPU_TOPOLOGY_ONE_CPU` and `CPU_TOPOLOGY_MATCH_HOST`; it contains no public
CPU-model or feature-mask control. A product-side attempt to imitate
`cortex-a76` would require the GenieZone/crosvm owner, not a safe firmware or
media patch.

## Best next experiment

The diskless QEMU capture is complete.  Do not run another product Windows
image on the strength of cosmetic QEMU-table differences.  The next causal
information requires an observer or control below the public AVF contract:
vendor GZVM/crosvm tracing, vendor CPU-feature profile control, or a vendor
fix/audit of the known physical-timer virtualization defect.

## Sources

* [QEMU Arm `virt` board documentation](https://qemu.readthedocs.io/en/v7.2.19/system/arm/virt.html): CPU selection, GIC, ITS and `virtualization` semantics.
* [Arm Cortex-A76 technical reference](https://documentation-service.arm.com/static/5f562083235b3560a01e03bc): the fixed Cortex-A76 model implements Armv8.2-A, while the retained product Linux log reports later architectural features such as ECV and E0PD.
* [Microsoft ACPI system-description guidance](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/acpi-system-description-tables): Windows consumes MADT/GTDT and other UEFI-provided tables during platform bring-up.
* [Microsoft UEFI requirements for Windows on SoC platforms](https://learn.microsoft.com/windows-hardware/drivers/bringup/uefi-requirements-that-apply-to-all-windows-platforms): firmware must leave core resources initialized for OS handoff.
