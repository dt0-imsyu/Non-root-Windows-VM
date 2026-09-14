# Public GenieZone timer-interface audit — 2026-09-13

## Result

```text
PUBLIC_GZVM_TIMER_OWNER_PATH          = PASS
GUEST_CNTP_CVAL_EL2_WRITE_PATH        = IDENTIFIED
UNPRIVILEGED_CNTP_CVAL_READBACK       = BLOCKED_BY_PUBLIC_GZVM_UAPI
LOCAL_GZVM_CNTP_CVAL_REPAIR           = NOT_EXPOSED
```

This was a source-only audit.  It started no VM and did not alter Android,
firmware, Windows media, BCD, ACPI, or the immutable baseline.

## Exact public path

The reviewed upstream-compatible MediaTek/Android GenieZone tree is
`android-kvm.googlesource.com/linux`, branch
`dmitriyf/pkvm-android15-6.6`, commit
`578879d02fa3aa4dfee12ead9ac6c93bd0b445d4`.

`drivers/virt/geniezone/gzvm_vcpu.c` accepts `GZVM_SET_ONE_REG` and calls
`gzvm_arch_vcpu_update_one_reg(..., true)`.  The ARM64 implementation in
`arch/arm64/geniezone/vcpu.c` turns that into:

```text
MT_HVC_GZVM_SET_ONE_REG(vm_id, vcpu_id, reg_id, value)
```

The UAPI declares both `GZVM_GET_ONE_REG` and `GZVM_SET_ONE_REG`, and the
architecture header reserves Hypervisor calls `GZVM_FUNC_GET_ONE_REG = 8` and
`GZVM_FUNC_SET_ONE_REG = 9`.  But the shipping public vCPU driver explicitly
returns `-EOPNOTSUPP` for `GZVM_GET_ONE_REG`.  Thus a normal crosvm client can
submit a guest register write, but has no public host-side readback API for
the resulting EL2 timer context.

For a running guest, `gzvm_arch_vcpu_run()` invokes `MT_HVC_GZVM_RUN`; the
public host driver receives an exit reason only after EL2 returns control.
It does not emulate `CNTP_CVAL_EL0` itself.  Therefore the post-P4 condition

```text
guest MSR CNTP_CVAL_EL0 -> different guest MRS value
```

is neither generated nor repairable in crosvm userspace or by the public
Linux GZVM driver.  Its remaining owner is the GenieZone EL2 guest-register
implementation (including any EL2 save/restore or timer-state programming).

## Why virtual timer success does not exonerate the physical path

The same source tree contains an explicit virtual-timer path:

- `gzvm_vcpu.c` has a host `hrtimer` wake mechanism for virtual-timer work;
- `arch/arm64/geniezone/hvc.c` tracks a `vtimer_offset` and exposes a virtual
  counter calculation separately from a physical counter calculation;
- the public migration series documents virtual-timer migration state.

There is no corresponding public implementation of guest `CNTP_CVAL_EL0`
retention or physical-comparator programming.  That is consistent with P1's
working `CNTV`/PPI27 and P4's failed `CNTP_CVAL` state, but it does not expose
the Samsung EL2 source needed to name the faulty instruction or data field.

## Connection to the product evidence

P5 on the actual Samsung `SM-X736B` product VM now adds a direct phase
control: the same EL1 CVAL write/readback succeeds before EBS, then the P4
post-EBS sequence fails.  Thus the public owner analysis applies to the
firmware-to-guest / EL2 vCPU-context transition rather than generic CVAL
instruction availability.

P4/P5 together proved all of the following:

```text
CNTPCT_EL0 progresses                          PASS
CNTP_CTL_EL0 enable/unmask readback            PASS
CNTP_CVAL_EL0 write/readback                   FAIL
counter passes requested CVAL                  PASS
CNTP_CTL_EL0.ISTATUS after deadline            FAIL
CNTV/PPI27 watchdog                            PASS
same CNTP_CVAL write/readback before EBS       PASS
same CNTP_CVAL write/readback after EBS        FAIL
```

The public interface audit explains why the missing CVAL state cannot be
repaired or observed through an unprivileged app, crosvm option, GZVM sysfs
attribute, or GZVM ioctl: none publishes that EL2 context.

## Vendor request

The next technically valid action is a vendor diagnosis of the unprotected
GenieZone vCPU physical timer context on this exact firmware build:

```text
Samsung SM-X736B / MT6991
X736BXXS6BZF4_OXM6BZF4
Android 16, kernel 6.6.102-android15-8-abogkiX736BXXS6BZF4-4k
crosvm backend: /dev/gzvm
```

Ask the owner to inspect the EL2 handling of `CNTP_CVAL_EL0`, its vCPU
save/restore path, and physical comparator arming/injection for an
unprotected one-vCPU VM.  The reproduction is firmware-only and is specified
in `GENIEZONE_PPI30_VENDOR_REPRO_2026-09-11.md`; its strongest runtime record
is `SYNTHETIC_POST_EBS_P5_PRE_EBS_CVAL_RUNTIME_2026-09-13.md`.

No local ACPI remap, BCD setting, WIM change, or Android application change is
a valid repair, because none changes the architectural meaning of `CNTP_*`.

## Sources

- [Public GenieZone ARM64 vCPU implementation](https://android.googlesource.com/kernel/common/%2B/5727772a3852ca071768d686c334d96bfdc2cc72/drivers/virt/geniezone/gzvm_vcpu.c)
- [Public GenieZone virtual-timer migration series](https://lists.infradead.org/pipermail/linux-mediatek/2024-November/086069.html)
- [Public GenieZone register/UAPI definitions](https://android.googlesource.com/kernel/common/%2B/5727772a3852ca071768d686c334d96bfdc2cc72/include/uapi/linux/gzvm.h)
