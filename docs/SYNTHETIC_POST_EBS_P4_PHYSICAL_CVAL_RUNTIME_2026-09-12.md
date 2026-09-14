# P4 physical `CNTP_CVAL` diagnostic — 2026-09-12

## Result

```text
POST_EBS_CNTP_CVAL_WRITE_READBACK = FAIL
POST_EBS_CNTP_COUNTER_PAST_CVAL   = PASS
POST_EBS_CNTP_ISTATUS             = FAIL
PHYSICAL_TIMER_REGISTER_STATE     = FAIL
```

P4 is one bounded, firmware-only successor to P3.  It changes no Windows
media, BCD, ACPI table, Android code, guest driver, or VM topology.

## Exact test

After the original `ExitBootServices()` return and before the usual PPI27
watchdog, P4 did the following on the product guest EL1:

```text
expected = CNTPCT_EL0 + 10,000,000
CNTP_CVAL_EL0 = expected
CNTP_CTL_EL0  = ENABLE=1, IMASK=0
```

It reads `CNTP_CVAL_EL0` immediately, then waits on the previously proven
`CNTV`/PPI27 watchdog for 65,000,000 ticks.  It reads the compare value and
physical counter again before inspecting `CNTP_CTL_EL0.ISTATUS`.

| Marker | Meaning |
|---|---|
| `CX` | immediate `CNTP_CVAL_EL0` readback differs from the just-written absolute deadline |
| `PW` | virtual PPI27 watchdog fired |
| `PC` | physical counter advanced during the watchdog |
| `RX` | later `CNTP_CVAL_EL0` readback still differs from the expected deadline |
| `CE` | later `CNTPCT_EL0 >= expected`: the counter passed the intended deadline |
| `PN` | `CNTP_CTL_EL0.ISTATUS` is still clear |

The raw serial tail was:

```text
Q0
BES
PD
CX
P0
P1
PW
PC
RX
CE
PN
```

This distinguishes P4 from P3: the physical deadline register itself does not
retain the guest's `CNTP_CVAL_EL0` write.  The counter nevertheless passes the
expected deadline and ISTATUS remains clear.  The issue is therefore not GIC
routing, PPI polarity, `WFI`, an expired but unhandled interrupt, nor an
ambiguous relative-TVAL conversion.

## Static validity

The built probe contains the ArmLib accessors that select `cntp_cval_el0` at
EL1 and the correct EL2-VHE alias only when that execution level applies.  The
build log records compilation of `AvfPostEbsP1Probe.c` with exactly:

```text
-DAVF_POST_EBS_USE_PHYS_TIMER
-DAVF_POST_EBS_ROBUST_PHYS_TIMER
-DAVF_POST_EBS_COUNTER_DIAGNOSTIC
-DAVF_POST_EBS_CVAL_DIAGNOSTIC
```

The disassembly contains both `mrs cntp_cval_el0` and `msr cntp_cval_el0`.
Thus `CX` is not a wrong-system-register or omitted-code artifact.

## Build, patch and rollback

| Item | Value |
|---|---|
| r4 replay build | PASS; `- Done -`, 6m49s |
| FD SHA-256 | `AFB89B5A6F196599C6EE7C8C51404CB65B2D3B8FEB3B4372008BDE2D3EA53A37` |
| Probe DLL SHA-256 | `9EFD007357A3DDACE2DBCD25FB6792C2935BEDD8730E343542D02CDA21A91D41` |
| patch SHA-256 | `ADFF7CF9C7A531ADECE7241B11946C34550DC75F3C5B6B43B746EFD08289EC5E` |
| patch size | 4,194,436 bytes |
| changed range | firmware offset `7,250,927,616`, length `2,097,152` |
| raw serial SHA-256 | `D32D5EB49AC38EF07106DC35BC858B3FBDF227FA9F83F44336EB5DE00E25E1F8` |

The launcher verified the Android baseline before apply and after rollback as
the exact immutable value:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

## Classification and next step

```text
GENIEZONE_CNTP_CVAL_GUEST_STATE = FAIL
VMM_PHYSICAL_TIMER_OWNER        = VERY_LIKELY
WINDOWS_BLOCKER_PHYSICAL_TIMER  = STRONG_HYPOTHESIS
```

P4 proves a concrete platform contract violation independent of Windows: the
guest-visible non-secure EL1 physical timer advertised to it does not preserve
a CVAL programming operation.  It still does not prove Windows ARM64 selected
that timer in early boot, so it cannot justify a random GTDT edit or a claimed
Windows fix.

No further local firmware probe can repair this register-state defect.  The
next useful action is the vendor reproducer documented in
`GENIEZONE_P3_PHYSICAL_TIMER_OWNER_EVIDENCE_2026-09-12.md`, now with the
stronger P4 `CNTP_CVAL` readback evidence.
