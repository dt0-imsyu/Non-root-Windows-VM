# P2.1 robust physical-timer retry — 2026-09-12

## Scope

This was the one valid retry of the existing P2.1 firmware-only probe after a
fresh P2 source-replay control had independently reproduced `BES -> P0 -> P1`.
It changed no Windows media, BCD, drivers, Android code, ACPI table, or VM
topology.  The transactional range was rolled back immediately after a bounded
60-second capture.

## Preconditions

The P2 source-replay control used a fresh DEBUG/LTO firmware build and reached
the same physical-timer pre-watchdog point as the archived working P2.  A
read-only FV comparison then showed that P2 and P2.1 have identical inner-FV
file ordering, offsets and sizes.  `ConSplitterDxe` differs by only eight
debug-metadata bytes; the P2.1 probe is the sole material module difference.
Thus the old early `ConSplitterDxe` abort did not invalidate this retry.

## Transaction evidence

| Item | Value |
|---|---|
| baseline SHA-256 before apply | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| P2.1 patch SHA-256 | `3DD9DFEA4A5C22C32FCBAA76C79616000B5ADED3853A8FA5B35CE3263B3B7844` |
| firmware range | offset `7250927616`, length `2097152` |
| raw serial SHA-256 | `E5B960274847124EB9E0747D54E6E15B2CB35A725365CEC11876C2DD1BED29FF` |
| raw serial size | 1,285,758 bytes |
| baseline SHA-256 after rollback | exact match |

The runner confirmed the VM absent before launch, staged the exact patch hash,
captured one run, force-stopped only the WinAVF app, and received
`RESULT=PASS` from the launcher rollback report.

## Runtime result

The decisive suffix is:

```text
AVF_POST_EBS_P1_START
Q0
BES
P0
P1
PW
PN
```

`PW` is emitted only after the proven virtual `CNTV` watchdog woke the probe.
`PN` is emitted only when `CNTP_CTL_EL0.ISTATUS == 0` at that point.  There is
no `P2` (the physical PPI30 handler), no `PS` (expired CNTP with undelivered
PPI), and no early `ConSplitterDxe` abort.

```text
POST_EBS_VIRTUAL_TIMER_PPI27       = PASS
POST_EBS_CNTP_WATCHDOG_WAKE        = PASS
POST_EBS_CNTP_PENDING              = FAIL
POST_EBS_PHYSICAL_TIMER_PPI30      = FAIL
P2_1_RUNTIME_PROBE_ENTRY           = PASS
P2_1_TIMER_RESULT                  = PASS
```

This proves an EL1 non-secure physical timer programmed through `CNTP_*` did
not become pending during the five-second interval in this exact product VM.
It is stronger than the original P2 result and does not depend on an unrelated
first `WFI` wake.

It still does **not** prove that Windows selected CNTP/PPI30.  Public Windows
ARM64 material does not expose that early HAL decision, so the correct status
is:

```text
WINDOWS_BLOCKER_PHYSICAL_TIMER = STRONG_HYPOTHESIS
WINDOWS_EARLY_TIMER_SELECTION  = UNKNOWN
```

The next useful work is source/spec research for Windows ARM64 early timer
selection or a non-root, specification-valid way to observe it.  Do not apply
random GTDT/ACPI workarounds and do not rerun P2/P2.1.
