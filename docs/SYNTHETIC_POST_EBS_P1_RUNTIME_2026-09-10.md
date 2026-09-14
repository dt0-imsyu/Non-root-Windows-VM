# Synthetic post-EBS P1 runtime — 2026-09-10

## Scope

P1 is a firmware-only continuation of the successful P0 platform probe. It
replaced the Windows handoff with a small embedded ARM64 UEFI application and
changed no Windows media, WIM, BCD, drivers, Android code, or ACPI tables.

Before `ExitBootServices()` the application takes the final memory map,
caches all required PCD values, replaces only TimerDxe's virtual-timer PPI
handler, and records the existing GIC interrupt protocol. After a successful
original EBS return it uses no Boot Services or PCD services. It restores the
minimal GICv3 Group-1 path, enables virtual timer PPI 27, arms `CNTV_TVAL_EL0`
for a fresh bounded deadline, enables IRQs, executes one `WFI`, and emits raw
16550 markers from both normal and IRQ context.

## Build and static audit

The literal r4 replay environment completed packaging:

```text
Build target: DEBUG / AARCH64 / GCC5
Build end: 2026-09-10 16:56:04 local
Result: - Done -
```

| Item | Value |
|---|---|
| build log | `build-logs/edk2-post-ebs-p1-rearm-20260910.log` |
| P1 FD SHA-256 | `B7CBF2F80F55612E4E19C0262AB29BC3AD2C1299084A3C2E186658429B3A3797` |
| FD size | 2,097,152 bytes |
| P1 ARM64 PE SHA-256 | `DAE445F3F46171B4D21D0C3FDC238B823DD24F245003D02579967FA646A2D1F8` |
| FV GUID proof | `9A7B310C-17DD-4792-8941-6E7F551D8C82 AvfPostEbsP1Probe` in `Guid.xref` |
| post-EBS PCD access | none; GICD base and timer PPI are cached before EBS |

## First attempt: probe integration defect

The first P1 build invoked `PcdGet64(PcdGicDistributorBase)` after `BES`. It
reached `Q0 → BES`, then faulted in `PcdDxe` before timer re-arm. This was a
probe-integration error, not a platform conclusion. The range was rolled back
and the immutable baseline hash was exact. The only corrective change cached
the PCD value before EBS; it did not alter the GIC/timer algorithm.

## Corrected transaction and rollback audit

| Item | Value |
|---|---|
| immutable baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| patch | `build-logs/synthetic-post-ebs-p1-20260910/post-ebs-p1-pcdsafe-firmware.patch` |
| patch SHA-256 | `2D34B92347066C9E76126CCE9FED23959DCD53E1560EC83D73CC95ADB63E15EF` |
| patch size | 4,194,436 bytes |
| changed range | offset `7,250,927,616`, length `2,097,152` |
| original range SHA-256 | `3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995` |
| replacement range SHA-256 | `B7CBF2F80F55612E4E19C0262AB29BC3AD2C1299084A3C2E186658429B3A3797` |
| bundle self-audit | PASS: WAVFPAT1/version, geometry, both hashes, embedded rollback bytes, no trailing data |
| baseline before and after | exact match |
| rollback report | PASS |

## One corrected runtime

Exactly one corrected app-owned P1 VM launch started at
`2026-09-10T13:57:46.1888944Z` and was bounded to 50 seconds. It was
force-stopped before transaction rollback. No Windows workload was started:
the probe takes the BDS diagnostic branch instead.

Raw serial evidence:

```text
AVF_POST_EBS_P1_START
Q0
BEST0
T1
T2
T3
TR
```

`BES` is the pre-existing wrapper's post-return success record; it is adjacent
to P1's `T0`, hence the raw byte stream contains `BEST0`. The unambiguous
sequence is therefore `BES → T0 → T1 → T2 → T3 → TR`:

| Marker | Proven operation |
|---|---|
| `T0` | post-EBS GICv3 and virtual timer re-arm completed |
| `T1` | execution immediately before the single `WFI` |
| `T2` | probe-owned virtual-timer PPI 27 handler executed and EOI'd the interrupt |
| `T3` | `WFI` returned with the handler-set completion flag |
| `TR` | reset request was reached after the successful wakeup |

Raw serial is
`build-logs/synthetic-post-ebs-p1-pcdsafe-runtime-20260910/raw-serial.log`,
SHA-256 `9FEEA1A21EEFC1B9C3F875660C38B3B22308ACC16075A2FCBB90594D1E455399`.
The run-status and rollback report are stored beside it.

## Result

```text
SYNTHETIC_POST_EBS_P1        = PASS
POST_EBS_GICV3_REARM         = PASS
POST_EBS_VIRTUAL_TIMER_PPI27 = PASS
POST_EBS_WFI_WAKEUP          = PASS
POST_EBS_PLATFORM_CONTRACT   = PASS (for the tested UART/RAM/CNTVCT/GICv3/timer/WFI path)
```

This does not prove Windows itself is correct. It does rule out the tested
post-EBS platform path as the explanation for the Windows stall: firmware code
continues after EBS, raw UART works, RAM works, the virtual counter advances,
GICv3 delivers virtual timer PPI 27, and an IRQ wakes `WFI`.

The next single informative experiment is an **ARM64 Linux ACPI-only boot on
the same app-owned VM topology**, with no changes to the validated Windows
baseline. It should independently exercise the ACPI-described platform after
EBS before returning to Windows-specific hypotheses.
