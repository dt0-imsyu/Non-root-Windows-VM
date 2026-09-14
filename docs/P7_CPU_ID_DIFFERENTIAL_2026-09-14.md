# P7 CPU-ID differential: QEMU control vs product AVF — 2026-09-14

## Scope

One already-packaged, reversible firmware probe was run once on the real
product AVF VM. It read architectural ID registers before Windows takes its
normal path, then retained the existing synthetic post-EBS control. It did
not modify Windows media, BCD, ACPI, Android, guest topology, or any signed
Windows component.

## Runtime integrity

| Field | Value |
|---|---|
| Immutable Android image before / after | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| P7 FD | `build-logs/product-cpu-contract-p8-20260913/KVMTOOL_EFI-product-cpu-contract.fd` |
| P7 FD SHA-256 | `DC39883CAEAC037B7DFC14437824AB69AFA028046AC1C04C20D336169BF16665` |
| Reversible patch | one range, offset `7250927616`, length `2097152` |
| Patch SHA-256 | `03FD22E04717580B147E5CFA8F8A68ED1317355921C3559EDE4164DC0A55A7B4` |
| Product raw serial | `build-logs/product-cpu-contract-p8-runtime-20260913-183512/raw-serial.log` |
| Product rollback | PASS; exact immutable hash restored |

The raw product record is:

```text
CP0
EL=0000000000000004
MIDR=00000000410FD851
PFR0=1201011023111111
MMFR0=2100022200101122
MMFR1=1001111010312122
ISAR0=0221111110212120
ISAR1=0111111100211002
CNTFRQ=0000000000C65D40
CP_DONE
BES T1 T2 T3 TR
```

`CurrentEL=4` is EL1. `CNTFRQ_EL0=13,000,000`. The post-EBS tail is the
existing independent virtual-timer/GIC/reset control, not Windows evidence.

The retained working QEMU 11.0.3 reference captured:

```text
QCP1
EL=0000000000000008
MIDR=00000000414FD0B1
PFR0=1100000011110112
MMFR0=0000000000101122
MMFR1=0000000010212122
ISAR0=0000100010211120
ISAR1=0000000000100001
CNTFRQ=0000000003B9ACA0
QCP_DONE
```

It runs firmware at EL2 and uses explicit QEMU `cortex-a76`; the historical
QEMU Windows control reaches Setup and installed Windows user mode. Its timer
frequency is 62.5 MHz.

## Material differences and interpretation

| Difference | Classification | Evidence-based interpretation |
|---|---|---|
| Product `MIDR_EL1=0x410FD851`; QEMU Cortex-A76 `0x414FD0B1` | BENIGN / expected | The models intentionally differ. Windows sees MIDR, but no evidence links either value to the silent boundary. |
| Product exposes richer PFR/MMFR/ISAR feature surface | POSSIBLY WINDOWS-RELEVANT | Product Linux reports ECV, E0PD, BTI, PAuth, RAS, LSE, stage-2 FWB and WFxT. Exact Windows binaries read ID registers. |
| Both profiles advertise EL2 in PFR0 | NOT A DIFFERENCE | Product runs at EL1, QEMU capture ran at EL2; the capability field itself is present on both. |
| Product advertises EL3 while QEMU capture does not | UNKNOWN | Real field difference, but no evidence that current WinPE uses it before its silent boundary. |
| `CNTFRQ_EL0`: 13 MHz vs 62.5 MHz | BENIGN / expected | Linux reaches userland at real 13 MHz and post-EBS virtual timer/WFI passes at that frequency. |

Static disassembly of exact `winload.efi` and `ntoskrnl.exe` confirms reads of
PFR0, MMFR and ISAR. A kernel path tests the PFR0 EL2 field, but that field is
satisfied in both profiles. This proves Windows consumes the contract, not
that any product-only bit selects a failing branch.

## Verdict

```text
P7_RESULT                         = PASS
PRODUCT_CPU_ID_PROFILE_CAPTURE    = PASS
CPU_PROFILE_DIFFERENCE            = CONFIRMED
CPU_FEATURE_CONTRACT              = INCONCLUSIVE
ACTIONABLE_CPU_MASK_OR_FIRMWARE_A_B = NOT_IDENTIFIED
```

The correct conclusion is not “mask CPU features.” A valid test would require
the hypervisor owner to offer a coherent CPU feature mask and preserve the
dependent virtualization semantics. AVF exposes no such control.

## Reproducibility

* Build log: `build-logs/edk2-product-cpu-contract-20260913-r2-20260913-182307.log`.
* Product runtime: `build-logs/product-cpu-contract-p8-runtime-20260913-183512`.
* QEMU raw capture: `build-logs/qemu-contract-20260913/qemu-v4-raw-serial.log`.
* Windows instruction context: `docs/WINDOWS_ARM64_TIMER_INSTRUCTION_AUDIT_2026-09-13.md`.
