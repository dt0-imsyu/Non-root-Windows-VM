# Windows ARM64 early-platform contract audit — 2026-09-07

## Scope and result

This was a read-only four-way audit. No VM was launched, and no firmware,
Windows media/WIM/BCD, Android application, or driver was changed.

```text
WINDOWS_ARM_EARLY_PLATFORM_CONTRACT = INCONCLUSIVE
```

No concrete FDT-to-ACPI contract violation was found. The static part of the
contract is internally consistent and also matches the live r9 crosvm topology.
The result is not `PASS`, because the retained evidence does not contain the
guest's runtime `CNTFRQ_EL0` value, a delivery trace for a generic-timer PPI,
or a Windows-side record of which timer interface the kernel selected. Those
are runtime/VMM facts, not values FADT, GTDT, or MADT can establish alone.

## Sources compared

| Source | Evidence used | Role |
|---|---|---|
| Actual r9 machine/FDT consumed by firmware | `build-logs/runtime-va-r9-20260906/runtime-r9-raw-serial.log`, lines 81-91 | Firmware logged PSCI, GIC and timer values immediately after reading its FDT. |
| Current ACPI delivered to Windows | Same log, `ACPI_AUDIT` records at lines 665 and 738-741 | Tables emitted by r9 before Windows Boot Manager. |
| Current crosvm topology | `build-logs/20260907-perfetto-r9-post-ebs/processes-plus-40s.txt:4158` | Exact launch command specifies `--cpus num-cores=1`. |
| Upstream ArmVirtKvmTool design | `firmware-work/edk2/ArmVirtPkg/KvmtoolCfgMgrDxe/ConfigurationManager.c`; `DynamicTablesPkg/Library/FdtHwInfoParserLib/Arm/*` | Dynamic ACPI generation from the FDT HOB, not hard-coded GIC/timer/PSCI constants. |
| Historical GUI/Windows-loader firmware family | `build-logs/serial-loader-placement-r1.log:80-88,134,209-219`; `build-logs/serial-mem-audit-r5.log:80-88,134-155` | Eight-vCPU historical topology, used only as comparison—not as hardware authority. |

`ConfigurationManager.c:565-596` obtains the FDT HOB, initializes the
hardware-information parser on that exact blob, parses it, and finalises the
dynamic repository which supplies FADT, GTDT and MADT. Thus the runtime
FDT-audit records and ACPI-audit records are two views of one source, not
separately maintained platform descriptions.

## Contract matrix

| Field | Current r9 FDT / actual machine | ACPI seen by Windows | Upstream conversion | Historical GUI/loader value | Assessment |
|---|---|---|---|---|---|
| CPU count | crosvm command: one core | one GICC | `ArmGicCParser.c` creates one GICC per FDT CPU | eight GICCs | **PASS** — topology changed, correctly described. |
| CPU UID ↔ MPIDR | boot CPU is MPIDR 0 | `uid=0 mpidr=0 flags=1` | parser derives UID from MPIDR and sets enabled | UID/MPIDR 0…7, all enabled | **PASS** — current one-core mapping is exact. |
| GIC version / distributor | GICv3, `0x3FFF0000` | GICD `0x3FFF0000`, version 3 | `ArmVirtGicArchLib` reads FDT GICD; dynamic parser emits GICD | same | **PASS**. |
| GIC redistributor | `0x3FFD0000` | base `0x3FFD0000`, range `0x20000` | FDT `reg[1]` is copied to GICR CM object | `0x3FEF0000`, `0x100000` | **PASS** — current range is one 128-KiB GICv3 redistributor; it ends at `0x3FFF0000`, immediately before GICD. Historical eight-core range likewise ends there. |
| GICR alignment / overlap | `0x3FFD0000`, 128 KiB | same | ArmGicV3Dxe uses two 64-KiB frames per GICv3 redistributor | 1 MiB for eight cores | **PASS** — `0x20000` alignment and no GICR/GICD overlap. |
| GICv3 CPU interface | GICv3 FDT node | GICC has `gicr=0`, discovery-range form | system-register interface; GICR is described separately | same representation | **PASS** — no erroneous per-GICC MMIO base supplied. |
| Secure / non-secure / virtual / hyp timers | `29, 30, 27, 26` | GTDT `29/6, 30/6, 27/6, 26/6` | generic-timer parser converts all four FDT interrupt cells | same GSIVs and flags | **PASS**. |
| GTDT trigger / polarity / always-on | FDT flags are parsed directly | `0x6` for each timer | bit 0=edge, bit 1=active-low, bit 2=always-on; `0x6` is level, active-low, always-on | same `0x6` | **PASS** — unchanged and derived, not handwritten. |
| Timer PPI use before EBS | Timer FDT client sets the same PCD PPIs | Windows receives same PPIs in GTDT | `ArmVirtTimerFdtClientLib` and GTDT parser each consume FDT `interrupts` | same values | **PASS** — no pre-EBS versus post-EBS PPI divergence found. |
| Counter frequency / timer injection | no retained `CNTFRQ_EL0` or delivery evidence | GTDT carries interrupts, not counter frequency | firmware reads `CNTFRQ_EL0` when needed | not recorded | **UNRESOLVED**. |
| PSCI conduit | FDT says `method=hvc` | FADT `armboot=0x0003` | parser maps HVC to `PSCI_COMPLIANT | PSCI_USE_HVC` | same `0x0003` | **PASS**. |
| FADT reduced-hardware contract | platform is HW-reduced ARM | FADT flags `0x00300000`; bit 20 is HW_REDUCED_ACPI | standard FADT generation | same | **PASS**. |

The FADT's additional bit 21 is `LOW_POWER_S0_IDLE_CAPABLE`; it is unchanged
from historical firmware and does not contradict the HVC PSCI contract.

## Important comparison

The potentially suspicious address difference is not a mismatch:

```text
historical 8-vCPU:  GICR 0x3FEF0000 + 0x00100000 = 0x3FFF0000 (GICD)
current r9 1-vCPU: GICR 0x3FFD0000 + 0x00020000 = 0x3FFF0000 (GICD)
```

This is the expected shrink from eight to one GICv3 redistributor, not address
truncation, overlap, or an ACPI/firmware disagreement.

The current code has one source of truth in both directions:

* Before EBS, `ArmVirtGicArchLib` reads GIC FDT `reg` pairs and programs the
  GIC PCDs; `ArmVirtTimerFdtClientLib` writes timer PCDs from FDT `interrupts`.
* For Windows, `KvmtoolCfgMgrDxe` gives the same FDT HOB to
  `FdtHwInfoParserLib`, whose GICR, GICC, timer and PSCI parsers create the
  dynamic ACPI objects.

Therefore this audit found no evidence that UEFI uses one GIC/timer description
while ACPI tells Windows a different one.

## What this audit cannot establish

1. `CNTFRQ_EL0` is a virtual architectural register. It is not a GTDT field,
   and the retained serial capture does not print it.
2. Existence and delivery of the generic-timer interrupt after handoff cannot
   be proved by tables. It requires Windows KD or privileged KVM/GZVM
   interrupt/vCPU tracing.
3. The raw r9 DTB is not retained separately. Recorded FDT values plus the
   dynamic parser establish emitted fields, but do not independently archive
   every FDT `reg` size cell.

These are reasons for `INCONCLUSIVE`, not evidence of a malformed ACPI table.
The post-EBS Perfetto result remains compatible with either a guest spin loop
or frequent VM-exit/re-entry; it cannot discriminate between them.

## Decision

No firmware-only ACPI/GIC/timer A/B is justified: no concrete contract
violation exists to change. Randomly changing timer PPIs, GICR bases/ranges,
CPU entries, or PSCI flags would destroy the controlled comparison and would
not increase observability.

The next single informative capability is either a genuinely bidirectional KD
serial endpoint or privileged VMM/GZVM tracing that exposes guest
PC/exception/interrupt state and `CNTFRQ_EL0`. Until one becomes available:

```text
EXIT_BOOT_SERVICES / ER               = PASS
POST_EBS_VCPU_EXECUTION               = PASS
WINDOWS_ARM_EARLY_PLATFORM_CONTRACT   = INCONCLUSIVE
WINDOWS_KERNEL_ENTRY                  = UNKNOWN
```
