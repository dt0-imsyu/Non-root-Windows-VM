# VMM physical-timer ownership audit — 2026-09-11

## Question

After P2 established that an armed `CNTP_*` deadline did not reach guest PPI
30 post-EBS, this read-only audit asked whether stock AVF, crosvm, or GZVM
exposes a permitted configuration or diagnostic interface that can restore or
inspect physical-timer delivery.

No VM was started and no Android, firmware, Windows-media, or trace
configuration was changed.

## Findings

| Surface | Evidence | Result |
|---|---|---|
| AVF `virtmgr` command/config vocabulary | static strings expose CPU count, memory, firmware, disks, display/input, GDB port, and GenieZone selection, but no architectural-timer, `CNTP`, `CNTV`, PPI, or GIC timer-routing setting | no app/AVF timer override |
| GZVM sysfs | `/sys/kernel/gzvm` contains only `demand_paging_batch_pages` and `destroy_batch_pages` | no timer state or configuration endpoint |
| Kernel timer tracepoints | KVM has `kvm_timer_update_irq`, `kvm_timer_hrtimer_expire`, `kvm_timer_emulate`, and related ARM event names | present but inaccessible to `adb shell` |
| Tracefs access | reading event `format` and `enable` is denied to shell; earlier bounded Perfetto controls collected no usable packets | no non-root guest-timer observer |
| GZVM device | `/dev/gzvm` is the hypervisor device used by crosvm; raw ioctls are not a documented untrusted-app or shell timer-control API | not a permitted configuration route |

The crosvm log identifies the active backend as GenieZone using `/dev/gzvm`.
There is no stock AVF field that changes its architectural-timer model.  The
FDT still provides `29, 30, 27, 26`, from which EDK2's dynamic table pipeline
copies PPI30 into GTDT.

## Result

```text
AVF_ARCH_TIMER_CONFIGURATION      = NOT_EXPOSED
GZVM_PHYSICAL_TIMER_OBSERVABILITY = PRIVILEGED
GZVM_PHYSICAL_TIMER_REPAIR        = VMM_OWNER_ONLY
```

This does not prove why GenieZone does not deliver PPI30; P2 is the runtime
evidence for the missing delivery.  It proves that an ordinary WinAVF APK,
ADB shell, and EDK2 table configuration do not expose a supported route to
repair it.

The next technically valid action is vendor/VMM-side investigation of the
GenieZone architectural physical timer, or a documented Windows-side method
to require the already-proven virtual timer.  Neither a BCD variation nor an
invalid GTDT remapping is justified.
