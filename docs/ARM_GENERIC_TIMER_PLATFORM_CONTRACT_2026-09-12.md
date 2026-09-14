# ARM Generic Timer platform contract — 2026-09-12

## Result

```text
ARM_GENERIC_TIMER_PLATFORM_CONTRACT = FAIL
WINDOWS_BLOCKER_PHYSICAL_TIMER      = STRONG_HYPOTHESIS
WINDOWS_EARLY_TIMER_SELECTION       = UNKNOWN
```

This is a platform-contract result, not yet a claim that Windows selected the
broken timer.  It is the first post-EBS defect localized to one architectural
interface without modifying Windows media, BCD, ACPI, or the Android app.

## What the product VM advertises

The FDT consumed by EDK2 and the GTDT delivered to Windows describe the Arm
generic-timer PPIs consistently:

| Timer interface | EL1 registers | GSIV/PPI | GTDT flags |
|---|---|---:|---:|
| Non-secure physical | `CNTP_CTL_EL0`, `CNTP_TVAL_EL0` | 30 | `0x6` |
| Virtual | `CNTV_CTL_EL0`, `CNTV_TVAL_EL0` | 27 | `0x6` |

The existing platform audit established that these values are produced from the
same FDT input consumed by pre-EBS firmware; this is not a handwritten ACPI
translation discrepancy.  `0x6` records level, active-low and always-on
capability.  The non-secure physical GSIV is a description of the `CNTP_*`
interface; it is not an optional availability flag or an instruction to route
physical-timer expiry to PPI27.

## Runtime proof

The valid P2.1 firmware-only run reached the established post-EBS point:

```text
BES -> P0 -> P1 -> PW -> PN
```

`PW` is emitted only by the already-proven virtual `CNTV`/PPI27 watchdog.
It woke the same vCPU after the physical timer had been armed.  `PN` is emitted
only when `CNTP_CTL_EL0.ISTATUS` remains clear after that five-second window.
There was no physical PPI30 handler marker (`P2`) and no expired-but-undelivered
marker (`PS`).

Therefore an EL1 non-secure physical timer armed through `CNTP_*` did **not
become pending**.  This is earlier than GIC delivery, IRQ polarity, or a
`WFI`-wake question.  It cannot be explained by the guest merely missing an
interrupt.

P3 further proved that this is not a stopped counter or a lost control write:
`CNTP_CTL_EL0` read back as enabled/unmasked and `CNTPCT_EL0` advanced during
the virtual watchdog interval, while `ISTATUS` remained clear.  The precise
failing sub-interface is the EL1 physical timer comparator/state path. See
`SYNTHETIC_POST_EBS_P3_PHYSICAL_COUNTER_RUNTIME_2026-09-12.md`.

P4 then programmed an absolute `CNTP_CVAL_EL0` deadline and proved the
register state itself is not retained: immediate and later readbacks differed
from the value just written, even though `CNTPCT_EL0` passed the intended
deadline and `ISTATUS` stayed clear. See
`SYNTHETIC_POST_EBS_P4_PHYSICAL_CVAL_RUNTIME_2026-09-12.md`.

```text
POST_EBS_VIRTUAL_TIMER_PPI27       = PASS
POST_EBS_CNTP_WATCHDOG_WAKE        = PASS
POST_EBS_CNTP_PENDING              = FAIL
POST_EBS_PHYSICAL_TIMER_PPI30      = FAIL
POST_EBS_CNTP_COUNTER_PROGRESS      = PASS
POST_EBS_CNTP_COMPARATOR_PENDING    = FAIL
POST_EBS_CNTP_CVAL_WRITE_READBACK    = FAIL
POST_EBS_CNTP_COUNTER_PAST_CVAL      = PASS
ARM_GENERIC_TIMER_PLATFORM_CONTRACT = FAIL
```

The immutable Android baseline was rehashed before the test and after its exact
rollback as
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
Full runtime evidence is in
`SYNTHETIC_POST_EBS_P2_1_RETRY_RUNTIME_2026-09-12.md`.

## Why this is a valid contract failure

Arm architectural physical and virtual timers are distinct instances.  EL2 may
permit, trap, or emulate EL1 physical-timer access, but an environment that
publishes the non-secure EL1 physical timer in its FDT and GTDT must make that
published interface usable.  The ACPI specification treats the GTDT entries as
the OS description of the architectural timer interrupt interfaces; it does
not define a timer-availability switch which lets firmware advertise a
non-functional `CNTP_*` path.

This is also consistent with the independent reference implementation: QEMU's
Arm `virt` ACPI builder emits both the non-secure EL1 physical and virtual
timer GSIV fields, treating them as separate functional timer interfaces.

## Linux differential

The working Linux control logged:

```text
arch_timer: cp15 timer(s) running at 13.00MHz (virt)
```

That Linux kernel selected `CNTV`/PPI27.  Its boot is fully compatible with a
broken `CNTP` path and therefore cannot clear PPI30.  Conversely it positively
confirms that the counter, virtual timer, GIC Group-1 delivery, and `WFI`
wakeup path work after EBS.

## Windows implication: superseded by binary audit

The original audit correctly declined to infer Windows' timer choice from
GTDT alone.  That uncertainty is now resolved for the exact baseline WinPE
kernel by the later read-only instruction audit:

```text
ntoskrnl.exe 10.0.26100.6584:
  MSR CNTV_CVAL_EL0 = 2
  MSR CNTV_CTL_EL0  = 1
  MSR CNTP_CVAL_EL0 = 0
  MSR CNTP_CTL_EL0  = 0
  MSR CNTP_TVAL_EL0 = 0
```

`winload.efi` and `hal.dll` likewise contain no physical-comparator write.
The failing `CNTP_*` comparator path is therefore not the direct timer path
of this Windows build.  The platform contract remains invalid, but the
Windows causal claim is closed:

```text
WINDOWS_PHYSICAL_TIMER_DIRECT_CAUSE = REFUTED_FOR_CURRENT_WINPE_BUILD
```

Changing PPI30 to PPI27, removing the physical timer, or changing `Always-on`
would still falsify the hardware description and would not affect the actual
Windows `CNTV_*` comparator path.  A firmware-only Windows A/B remains
invalid.  See `WINDOWS_ARM64_TIMER_INSTRUCTION_AUDIT_2026-09-13.md`.

## Ownership and next action

The fault is below guest firmware: likely EL2 timer-access/trapping/emulation
or the host-side virtual timer state for this GenieZone VM.  Stock AVF exposes
no architectural-timer configuration and the relevant GZVM tracing is
privileged.

The next best positive milestone is not another Windows or firmware run.  It
is a vendor-level reproducible report/request that establishes whether the VM
is expected to expose the EL1 non-secure physical timer and, if so, obtains a
GenieZone trace or configuration fix for `CNTP_*`.  The minimal reproducer is
P2.1: one vCPU, PPI27 watchdog, `CNTP_TVAL_EL0`, and the `PW -> PN` outcome.

## Sources

- [Microsoft: ACPI system description tables](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/acpi-system-description-tables)
- [Microsoft Hyper-V TLFS: ARM64 timers](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/tlfs/timers)
- [ACPI Specification: Generic Timer Description Table](https://uefi.org/specs/ACPI/6.6/05_ACPI_Software_Programming_Model/ACPI_Software_Programming_Model.html)
- [QEMU Arm virt ACPI GTDT builder](https://github.com/qemu/qemu/blob/master/hw/arm/virt-acpi-build.c)
