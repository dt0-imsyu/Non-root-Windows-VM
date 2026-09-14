# P3 physical-counter / comparator diagnostic — 2026-09-12

## Result

```text
POST_EBS_CNTP_CONTROL_READBACK    = PASS
POST_EBS_CNTP_COUNTER_PROGRESS    = PASS
POST_EBS_CNTP_COMPARATOR_PENDING  = FAIL
POST_EBS_PHYSICAL_TIMER_PPI30     = FAIL
PHYSICAL_TIMER_COMPARATOR_PATH    = FAIL
```

P3 is the direct follow-up to P2.1. It made no change to Windows media, BCD,
ACPI tables, Android code, drivers, VM topology, or the immutable product
image. It adds only two raw-UART observations around the pre-existing P2.1
five-second virtual-timer watchdog.

## Probe semantics

The probe arms the non-secure EL1 physical timer exactly as P2.1 did:

```text
CNTP_TVAL_EL0 = 10,000,000
CNTP_CTL_EL0  = ENABLE=1, IMASK=0
```

It independently arms the established `CNTV`/PPI27 watchdog for 65,000,000
ticks. Additional markers:

| Marker | Sole condition |
|---|---|
| `PD` | `CNTP_CTL_EL0` immediately reads enabled and unmasked |
| `PC` | `CNTPCT_EL0` differs after the PPI27 watchdog interval |
| `PN` | `CNTP_CTL_EL0.ISTATUS` is clear after that interval |

This distinguishes timer-control persistence, physical-counter progress and
comparator expiry. It does not rely on the PPI30 handler alone.

## Controlled build and patch

| Item | Value |
|---|---|
| build | r4 replay environment; `- Done -` in 5m42s |
| compile delta | physical, robust-watchdog and counter-diagnostic defines only |
| firmware FD SHA-256 | `BF9FFF63EACE753AACFAF026E4AA23459CC633CE8C65AAB5E4E93321FD5F7DFE` |
| probe PE SHA-256 | `5C65E5A6765098D6A499E895B6ABBFD58CF488675846D57B3E7521011249C4C6` |
| patch SHA-256 | `8335B20F4F93E5B2E07577F3E9497BB72FC900778CBAD768A6C1381252595378` |
| patch scope | one 2,097,152-byte firmware range at offset `7,250,927,616`; exact rollback bytes embedded |
| raw serial SHA-256 | `7959A2E4FF31044EA3787E7B14B56C8E989E79FF3D6AD8BBE021252E1071E188` |

The generated FD and patch are in
`build-logs/synthetic-post-ebs-p3-counter-diagnostic-20260912/`; runtime
evidence is in
`build-logs/synthetic-post-ebs-p3-counter-diagnostic-runtime-20260912/`.

## One runtime and rollback

The launcher checked the immutable Android image before applying the patch,
ran exactly one 60-second VM capture, stopped the app, rolled the firmware
range back, and rehashed the baseline before and after as:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

The final raw sequence is:

```text
AVF_POST_EBS_P1_START
Q0
BES
PD
P0
P1
PW
PC
PN
```

## Interpretation

`PD` rules out a lost `CNTP_CTL_EL0` write. `PC` proves the physical
architectural counter advances during the same interval in which the virtual
timer wakes the vCPU. `PN` proves the physical comparator does not assert its
pending state. Pending state precedes GIC delivery, IRQ polarity, and `WFI`,
so no PPI30-routing or missed-interrupt explanation remains.

The failing interface is the non-secure EL1 physical-timer comparator/state
path, most plausibly its EL2 trapping/emulation or VM timer context. This still
does not prove that Windows early ARM64 HAL programs `CNTP_*`:

```text
WINDOWS_BLOCKER_PHYSICAL_TIMER = STRONG_HYPOTHESIS
WINDOWS_EARLY_TIMER_SELECTION  = UNKNOWN
```

Do not remap PPI30 or change GTDT: that cannot redirect `CNTP_*` and would
make the platform description false. The next informative owner path is a
vendor-level GenieZone physical-timer reproducer using this P3 evidence.
