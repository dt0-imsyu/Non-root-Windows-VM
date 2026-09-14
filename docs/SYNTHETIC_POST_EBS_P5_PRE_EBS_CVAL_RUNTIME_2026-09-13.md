# P5: pre-EBS versus post-EBS `CNTP_CVAL_EL0` retention

## Question

P4 established that an absolute non-secure EL1 physical-timer comparator
write does not read back after `ExitBootServices`.  P5 asks the narrower
question whether CVAL is at least accessible before EBS while the timer is
masked.  It does **not** reproduce P4's later `ENABLE=1, IMASK=0` condition.

## Scope

Only the synthetic firmware application changed.  It added one compile-time
guarded pre-EBS diagnostic:

1. save `CNTP_CTL_EL0` and `CNTP_CVAL_EL0`;
2. mask the timer, write `CNTP_CVAL_EL0 = CNTPCT_EL0 + 10,000,000`;
3. read it back and emit `BC` (equal) or `BX` (not equal);
4. restore the saved CVAL and control state before ordinary EBS processing.

The same FD retained the existing P4 post-EBS diagnostic unchanged.  No
Windows media, BCD, drivers, Android app, ACPI table, or VM topology changed.

## Offline evidence

| Item | Value |
|---|---|
| Immutable Android baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| P5 firmware SHA-256 | `7D547FE7BAA909402078A3BF7F4018A9350186191C67D03919266BC786561091` |
| P5 patch SHA-256 | `AAF688B53F622322C3AC25E7A054D17292AC277632832DDACBBFE57847EA1E56` |
| Patch bytes | `4,194,436` |
| Changed range | offset `7,250,927,616`, length `2,097,152` |
| Rollback bytes embedded | `2,097,152` |

The P5 build completed with `- Done -` and its generated ARM64 probe contains
the `CNTP_CVAL_EL0`, `CNTP_CTL_EL0`, and `CNTPCT_EL0` access instructions.
The patch builder verified the expected baseline geometry and embedded the
original firmware range as rollback data.

## One runtime

The runner first rehashed the device baseline, staged the exact patch, ran one
60-second capture, force-stopped the VM, pulled raw serial, requested launcher
rollback, and rehashed the device baseline again.

Raw serial SHA-256:

```text
19F1D97C616CF1F21A586E6DD314EC00EF348F7B3C482445BD4ECF55299FF656
```

The terminal marker sequence is exact:

```text
Q0
BC
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

Interpretation:

- `BC`: the physical comparator value is retained before EBS while masked.
- `BES`: the probe's original `ExitBootServices()` returned successfully.
- `PD`, `PC`, `PW`: post-EBS CNTP control, counter progress, and independent
  virtual watchdog remain valid.
- `CX`, `RX`, `CE`, `PN`: the post-EBS CVAL write is not retained, the counter
  nevertheless passes the intended deadline, and CNTP never becomes pending.

Rollback report:

```text
RESULT=PASS
BASELINE_SHA256=2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

## Verdict

```text
PRE_EBS_CNTP_CVAL_WRITE_READBACK = PASS
PRE_EBS_CNTP_ENABLED_SEQUENCE    = NOT_TESTED
POST_EBS_CNTP_CVAL_WRITE_READBACK = FAIL
P5_RUNTIME_PROBE_VALID           = PASS
ARM_GENERIC_TIMER_PLATFORM_CONTRACT = FAIL
```

P5 rejects a universal "CVAL cannot be written before EBS" explanation.  It
does **not** yet prove that EBS itself changes CVAL state: P4 enables and
unmasks CNTP before its readback, while P5 deliberately kept it masked to
avoid changing normal firmware timing.  A pre-EBS exact-enable control would
be required to make that phase attribution.  The independently completed
Windows binary audit now shows that this WinPE uses `CNTV_*`, not this physical
comparator, so P5 should not be used to attribute the Windows stall.

## Artifacts

- Firmware/patch: `build-logs/synthetic-post-ebs-p5-pre-ebs-cval-20260913/`
- Runtime/rollback/raw serial:
  `build-logs/synthetic-post-ebs-p5-pre-ebs-cval-runtime-20260913/`
- Build log:
  `build-logs/edk2-synthetic-post-ebs-p5-pre-ebs-cval-r2-20260913-002359.log`

## Next boundary

Do not alter GTDT or PPI mappings randomly.  A pre-EBS enabled-CNTP control is
only useful for the vendor platform report, not for the current Windows
diagnosis.  No unprivileged GenieZone physical-CVAL repair path is exposed.
