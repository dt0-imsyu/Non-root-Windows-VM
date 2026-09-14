# GenieZone physical-timer owner evidence — 2026-09-12

## Result

```text
P3_VALID                              = PASS
PHYSICAL_TIMER_COMPARATOR_PATH        = FAIL
VMM_PHYSICAL_TIMER_OWNER              = PROBABLE
NON_ROOT_TIMER_REPAIR_OR_TRACE        = BLOCKED
WINDOWS_BLOCKER_PHYSICAL_TIMER        = STRONG_HYPOTHESIS
```

This is an owner/evidence audit only.  It did not start a VM, change Android,
Windows media, firmware, ACPI, BCD, or the immutable image.

## What P3 proves directly

On the real product AVF/GenieZone VM, after the original `ExitBootServices()`
returned, P3 performed:

```text
CNTP_TVAL_EL0 = 10,000,000
CNTP_CTL_EL0  = ENABLE=1, IMASK=0
```

The independent known-good virtual-timer watchdog then waited 65,000,000
ticks.  The serial sequence was:

```text
BES -> PD -> P0 -> P1 -> PW -> PC -> PN
```

`PD` is the immediate readback of enabled/unmasked `CNTP_CTL_EL0`; `PC`
proves `CNTPCT_EL0` advanced; `PN` means `CNTP_CTL_EL0.ISTATUS` was still
clear after the deadline.  Therefore the failure is before GIC PPI30 routing,
interrupt polarity, the PPI handler, and `WFI` wake-up.  Full evidence and
hashes are in `SYNTHETIC_POST_EBS_P3_PHYSICAL_COUNTER_RUNTIME_2026-09-12.md`.

## P4 strengthening

P4 removed the remaining relative-deadline ambiguity. It wrote
`CNTP_CVAL_EL0 = CNTPCT_EL0 + 10,000,000` and immediately observed `CX`, then
after the PPI27 watchdog observed `RX -> CE -> PN`: CVAL readback did not
retain the expected deadline, the physical counter passed that deadline, and
ISTATUS was still clear. This raises the owner assessment from a generic
comparator suspicion to a guest-visible physical-timer register-state failure.
See `SYNTHETIC_POST_EBS_P4_PHYSICAL_CVAL_RUNTIME_2026-09-12.md`.

## Actual device boundary

The tablet is the stock Samsung `SM-X736B`, kernel
`6.6.102-android15-8-abogkiX736BXXS6BZF4-4k`, SoC `MT6991`, with
`ro.boot.hypervisor.version=GenieZone`.  Read-only inspection shows:

| Surface | Observation | Implication |
|---|---|---|
| Kernel configuration | `CONFIG_MTK_GZVM=m`, `CONFIG_ARM_ARCH_TIMER=y`, `CONFIG_KVM=y` | GZVM is an active kernel module over the ARM architectural timer model. |
| Loaded modules | `gzvm` and `timer_mediatek` are live | this is not a missing host timer-driver case. |
| `/sys/kernel/gzvm` | only demand-paging batch controls | no timer state/repair surface. |
| `/dev/gzvm` | SELinux type `gzvm_device` | protected VMM control device, not an app/shell timer API. |
| tracefs | no exposed `geniezone` or `mtk_timer` event formats; previous bounded Perfetto captures had no guest timer events | no non-root comparator or EL2-state observer. |

The public GenieZone description says the hypervisor runs at EL2 and provides
the virtual architectural timer, GIC and exception virtualization.  Its public
code series explicitly implements **virtual-timer** migration/host hrtimer
maintenance, but exposes no corresponding physical-timer maintenance path.
That is consistent with, but does not alone prove, the P3 result.

## Why the probable owner is VMM/EL2

The guest was able to read the physical counter and retain control-register
state.  The failed operation is generation of a physical-timer pending state
after a valid deadline.  The application, EDK2, GTDT, FAT image and Windows
are not on that comparator path.  On this protected AVF topology, its remaining
owner is the virtual machine timer context maintained by GenieZone EL2 and its
`gzvm` host integration.

That conclusion must remain **probable**, not certain: the Samsung shipping
EL2 implementation is proprietary and its timer state is not exposed to an
unprivileged observer.  P3 also does not establish which generic timer Windows
ARM64 selects during early HAL initialization.

## Minimal vendor reproducer

The smallest useful vendor-side test is not another Windows image:

1. Create one unprotected 1-vCPU GenieZone/AVF guest with the existing GICv3
   and architectural-timer topology.
2. At guest EL1 write `CNTP_TVAL_EL0=10000000`, then
   `CNTP_CTL_EL0=1`, with barriers.
3. After 65,000,000 CNTV ticks, inspect `CNTP_CTL_EL0.ISTATUS`, `CNTPCT_EL0`
   and the EL2/GZVM physical-timer context for that vCPU.
4. Compare with `CNTV_*`/PPI27 on the identical vCPU.

Expected failure, now independently established by P3 and P4: the counter
moves, but `CNTP_CVAL_EL0` does not retain the guest deadline and the physical
comparator never reports pending. Vendor diagnosis must cover the CNTP
system-register trap/emulation, vCPU timer-context save/restore, and EL2
comparator deadline programming. No valid local ACPI or PPI remap can repair
that path.

## References

* [MediaTek GenieZone documentation patch](https://lists.infradead.org/pipermail/linux-arm-kernel/2023-June/841203.html): EL2 implementation and virtual platform responsibilities.
* [GenieZone virtual-timer migration patch](https://lists.infradead.org/pipermail/linux-mediatek/2024-November/086069.html): explicit vtimer migration/host hrtimer handling.
* [GenieZone ARM64 register UAPI patch](https://lists.openwall.net/linux-kernel/2023/04/13/481): defines physical-timer system-register IDs, showing the timer state belongs to the VMM/hypervisor interface.

## Next action

Do not run a Windows or ACPI A/B from this evidence alone. P4 has already
classified the register write as not retained and cannot repair it. Prefer the
vendor reproducer if a vendor channel is available.
