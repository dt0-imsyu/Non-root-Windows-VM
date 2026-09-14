# Synthetic post-EBS P2 physical-timer runtime — 2026-09-11

## Scope

P2 is a single firmware-only diagnostic run.  It replaced the normal Windows
handoff with the existing post-EBS probe, changed no Windows media, WIM, BCD,
drivers, Android app, ACPI table, or virtual-machine topology.

It is intentionally the same mechanism as P1 except for the timer source:

| Test | Timer register | ACPI/GTDT PPI | Result |
|---|---|---:|---|
| P1 | `CNTV_TVAL_EL0` / `CNTV_CTL_EL0` | 27 (virtual) | wakeup PASS |
| P2 | `CNTP_TVAL_EL0` / `CNTP_CTL_EL0` | 30 (non-secure physical) | PPI30 not observed on the first `WFI` wake |

Before `ExitBootServices()` the application obtains the final memory map,
caches all PCD values, and replaces only the physical-timer interrupt handler.
After a successful EBS return it uses no Boot Services or PCD services.  It
rearms the same minimal GICv3 Group-1 path used by P1, enables PPI 30, programs
a fresh 10,000,000-tick physical deadline, enables IRQs, and executes one
`WFI`.

## Build and static audit

The literal r4 replay environment completed full top-level packaging:

```text
Build target: DEBUG / AARCH64 / GCC5
Build end: 2026-09-11 20:51:34 local
Result: - Done -
R4_BUILD_ENV_REPLAY = PASS
```

The P2 compile command explicitly contains
`-DAVF_POST_EBS_USE_PHYS_TIMER`.  The module's ARM64 PE contains the distinct
`P0/P1/P2/P3/PR` marker set; its default virtual marker `T0` is absent.

| Item | Value |
|---|---|
| P2 FD | `firmware-work/edk2/artifacts/KVMTOOL_EFI-post-ebs-p2-physical-timer.fd` |
| P2 FD size | 2,097,152 bytes |
| P2 FD SHA-256 | `A6873FEF6C3B9F206692EA64DBC88069B5F6856D7C0F437BF0425F39811EFFAC` |
| P2 probe ARM64 PE SHA-256 | `B831F5F7A704CC3817D45C7530FA48C80886790F849CF37DADABBC62C13EA9CF` |
| full build log | `build-logs/edk2-post-ebs-p2-phys-timer-pwsh-20260911-204717.log` |

After archiving the tested FD, the temporary DSC build option was removed.
The source tree therefore again defaults to the P1 virtual-timer configuration;
no rebuild was performed after that source-only restoration.

## Transaction and rollback audit

| Item | Value |
|---|---|
| immutable Android baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| patch | `build-logs/synthetic-post-ebs-p2-physical-timer-20260911/post-ebs-p2-physical-timer-firmware.patch` |
| patch SHA-256 | `0AD2F239BBDADF9FA585A4A3EFAE9F356A33C8F3A3951B4FD5389F13F31FAD7C` |
| patch size | 4,194,436 bytes |
| changed range | offset `7,250,927,616`, length `2,097,152` |
| original range SHA-256 | `3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995` |
| replacement range SHA-256 | `A6873FEF6C3B9F206692EA64DBC88069B5F6856D7C0F437BF0425F39811EFFAC` |
| bundle audit | PASS: one WAVFPAT1 range, exact immutable baseline hash, old/new hashes, embedded old bytes |

Exactly one app-owned VM run began at `2026-09-11T17:55:47.7191197Z`, was
bounded to 50 seconds, then force-stopped before rollback.  The launcher
reported `RESULT=PASS`; it and an independent remote hash re-established the
exact immutable baseline.

## Runtime evidence

The decisive final serial suffix is:

```text
AVF_POST_EBS_P1_START
Q0
BESP0
P1
TX
```

`BES` is the established successful original `ExitBootServices()` return
marker, so the adjacent bytes are unambiguously `BES -> P0`.  `P0` proves the
post-EBS physical-timer/GIC re-arm completed; `P1` is immediately before the
one `WFI`.

`P2` is emitted only from the probe-owned PPI 30 handler. It was absent from
the complete 1,285,755-byte raw capture. `TX` is emitted after `WFI` when the
handler completion flag is clear. Crucially, this version makes only one
`WFI`: any other enabled interrupt may wake it before the 10,000,000-tick
physical deadline. Therefore this run establishes only that PPI30 was not
observed on its first wake, not that the physical timer can never be delivered.
P2.1 is required to wait to a virtual-timer watchdog and inspect
`CNTP_CTL.ISTATUS`.

Raw evidence:

| Item | Value |
|---|---|
| artifact directory | `build-logs/synthetic-post-ebs-p2-physical-timer-runtime-20260911-205526` |
| raw serial SHA-256 | `F9DFADFA8372D14DF5A554E3BFF6B6278D8DA1C7D62E2D13D9C00D20A6534CAA` |
| serial bytes | 1,285,755 |
| `P2` occurrences | 0 |
| rollback report | PASS |
| post-rollback baseline | exact `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |

## Result and interpretation

```text
POST_EBS_GICV3_REARM              = PASS
POST_EBS_VIRTUAL_TIMER_PPI27      = PASS       (P1)
POST_EBS_PHYSICAL_TIMER_PPI30     = NOT_CONFIRMED
POST_EBS_PHYSICAL_TIMER_DELIVERY  = NOT_CONFIRMED
WINDOWS_PHYSICAL_TIMER_CONTRACT   = UNPROVEN
```

This is a valid reason to retest the physical timer rigorously, not yet a
platform-contract discrepancy or a claim about Windows. Linux booted because
its observed kernel path selected the virtual timer. Public Windows material
confirms GTDT support but does not disclose the early ARM64 HAL selection
algorithm; PPI30 appearing in GTDT is not proof that Windows selected it.

## Follow-up GTDT semantics audit

The P2 result does **not** justify an arbitrary firmware-table workaround.
The live table is generated by the unmodified chain

```text
FDT timer node -> CM_ARM_GENERIC_TIMER_INFO -> GTDT generator
```

and copies the FDT non-secure EL1 PPI 30 and its flags verbatim.  The relevant
ACPI fields are not an availability bitmap: non-secure EL1 has a required GSIV;
only the *secure* EL1 timer fields are optional for a non-secure OS.  Further,
the only relevant flag bit which can safely vary here is `Always-on` (bit 2).
It describes wake capability; it does not disable the physical timer or route
`CNTP_*` to the virtual PPI.

Consequently, setting the non-secure GSIV to zero or mapping it to PPI 27
would create an invalid hardware description and cannot make a PPI30 generated
by `CNTP_*` arrive on PPI27.  Clearing `Always-on` would be spec-valid but
would not repair the active post-EBS delivery failure established by P2.

```text
GTDT_NONSECURE_TIMER_ONE_FIELD_FIRMWARE_FIX = NOT_VALID
P2_ACTIONABLE_OWNER = VMM/GZVM architectural physical-timer delivery
```

No Windows runtime follows from P2 until a VMM-side physical-timer capability
or a documented Windows timer-selection override is identified.  The next
read-only task is to audit the available crosvm/GZVM architectural-timer
implementation and its host-exposed configuration; it must establish whether
PPI30 can be delivered at all to this AVF VM.  This avoids an invalid ACPI
experiment that would not be diagnostic.
