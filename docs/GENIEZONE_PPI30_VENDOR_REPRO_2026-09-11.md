# GenieZone PPI30 vendor reproducer — 2026-09-11

> Historical P2-only report. The current vendor-ready evidence is P2.1 + P3 +
> P4; use `GENIEZONE_P3_PHYSICAL_TIMER_OWNER_EVIDENCE_2026-09-12.md` and
> `SYNTHETIC_POST_EBS_P4_PHYSICAL_CVAL_RUNTIME_2026-09-12.md` instead.

## Current P4 verdict

The old one-WFI ambiguity is closed.  P2.1 used a working virtual PPI27
watchdog; P3 proved `CNTPCT_EL0` advances and `CNTP_CTL_EL0` retains
enable/unmask; P4 wrote an absolute `CNTP_CVAL_EL0` deadline and received:

```text
CX -> PW -> PC -> RX -> CE -> PN
```

`CX`/`RX` mean the CVAL register does not retain the guest-written deadline;
`CE` proves the counter passed it; `PN` proves ISTATUS remained clear. This is
a concrete guest physical-timer register-state failure before PPI30/GIC
routing. It is a vendor/EL2 investigation request, not an ACPI-remapping
request.

## Historical P2 evidence

The fastest technically sound route toward a Windows installer is **not** a
new WIM, BCD, or ACPI-table experiment.  It is a focused GenieZone / crosvm
architectural-timer defect report or source-level fix, using the contained
firmware-only reproducer below.

P1 already proves the same app-owned AVF VM executes post-EBS code, re-arms
GICv3, accepts IRQs, wakes from `WFI`, and delivers the virtual timer PPI27.
P2 differs only by using the non-secure physical timer registers and PPI30.
It reaches the same post-EBS point but PPI30 did not reach its handler before
the first `WFI` return.

```text
same VM / same vCPU / same GICv3 / same WFI / same 10,000,000 tick deadline

CNTV_* -> PPI27 -> handler -> PASS
CNTP_* -> PPI30 -> not observed before first WFI return
```

This is not yet a conclusive virtual-versus-physical delivery reproducer. A
P2.1 watchdog run is required before assigning an owner.

## Device and runtime facts

| Item | Value |
|---|---|
| device | Samsung `gts11` / Android 16 / API 36 |
| firmware | `X736BXXS6BZF4_OXM6BZF4` |
| backend | crosvm with GenieZone `/dev/gzvm` |
| virtual timer PPI | 27 — proven post-EBS delivery |
| physical timer PPI | 30 — delivery absent in P2 |
| FDT/GTDT timer PPIs | `29, 30, 27, 26` |
| immutable runtime baseline | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |

## Exact P2 payload and evidence

| Item | Value |
|---|---|
| tested FD | `firmware-work/edk2/artifacts/KVMTOOL_EFI-post-ebs-p2-physical-timer.fd` |
| FD SHA-256 | `A6873FEF6C3B9F206692EA64DBC88069B5F6856D7C0F437BF0425F39811EFFAC` |
| source | `firmware-work/edk2/ArmPkg/Application/AvfPostEbsP1Probe/AvfPostEbsP1Probe.c` with `AVF_POST_EBS_USE_PHYS_TIMER` |
| patch SHA-256 | `0AD2F239BBDADF9FA585A4A3EFAE9F356A33C8F3A3951B4FD5389F13F31FAD7C` |
| raw serial | `build-logs/synthetic-post-ebs-p2-physical-timer-runtime-20260911-205526/raw-serial.log` |
| raw serial SHA-256 | `F9DFADFA8372D14DF5A554E3BFF6B6278D8DA1C7D62E2D13D9C00D20A6534CAA` |

Expected P2 success sequence:

```text
BES -> P0 -> P1 -> P2 -> P3 -> PR
```

Observed complete suffix:

```text
BES -> P0 -> P1 -> TX
```

`P2` is emitted solely by the registered PPI30 handler. `TX` is emitted only
after `WFI` with the handler completion flag still clear.

## Why this is VMM work

The AVF platform hands a generated guest DT to GenieZone through
`GZVM_SET_DTB_CONFIG`; the user-visible crosvm configuration has no
architectural-timer parameter.  Stock GZVM sysfs exposes only demand-paging
controls, and timer tracepoints are privileged.  An untrusted app cannot
repair timer injection by issuing GZVM ioctls.

The upstream Android/Mediatek GenieZone history includes explicit support for
**virtual** timer migration, including continuing the guest virtual timer while
the guest is idle.  This matches P1's success but does not establish physical
timer delivery.  The VMM/kernel owner should verify:

1. whether `CNTP_CTL_EL0` / `CNTP_TVAL_EL0` are virtualized for this VM type;
2. whether expiration injects level PPI30 to the in-kernel GICv3;
3. whether physical timer context is maintained across guest-to-host switches
   and `WFI`;
4. whether the generated FDT must omit or alter PPI30 when the VMM implements
   only virtual-timer delivery.

## Non-actions

Do not set PPI30 to zero, remap it to PPI27, or remove GTDT as a firmware
workaround.  Those changes do not redirect `CNTP_*` hardware and would create
an invalid or misleading ACPI platform contract.  Do not retry Windows setup
until the PPI30 contract is corrected or a documented Windows virtual-timer
selection mechanism is found.

Replacing the bundled AVF APEX/crosvm or the GenieZone kernel driver is not a
non-root workaround: Android's own AVF build/update guidance requires root and
system partition modification for that workflow.  It is therefore explicitly
outside this project's current no-root/no-unlock scope.  The deployable fixes
are a Samsung OTA or a vendor-provided diagnostic build.

## References

- [ACPI GTDT fields and timer flags](https://uefi.org/htmlspecs/ACPI_Spec_6_4_html/05_ACPI_Software_Programming_Model/ACPI_Software_Programming_Model.html)
- [Mediatek GenieZone virtual-timer migration commit](https://android.googlesource.com/kernel/common/%2B/edcc7ecc0b224266d2543c7f682e744c2e4b48bb)
- [Android crosvm GenieZone backend](https://android.googlesource.com/platform/external/crosvm/%2B/853aaa9bdb28774fd82e7cfa4c910c95b0acaa5d/hypervisor/src/geniezone/mod.rs)
