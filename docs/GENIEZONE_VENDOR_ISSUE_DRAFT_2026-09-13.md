# Draft: GenieZone guest EL1 physical timer state is not retained

## Suggested subject

`[SM-X736B / MT6991] GenieZone unprotected VM does not retain guest CNTP_CVAL_EL0; CNTP ISTATUS never becomes pending`

## Report body

On a stock Samsung SM-X736B (MT6991), an unprotected AVF VM can execute after
UEFI `ExitBootServices()` and its virtual ARM generic timer works.  The
advertised non-secure EL1 physical timer does not.

Device/build:

```text
model: SM-X736B
firmware: X736BXXS6BZF4_OXM6BZF4
Android kernel: 6.6.102-android15-8-abogkiX736BXXS6BZF4-4k
backend: Android AVF crosvm -> /dev/gzvm -> GenieZone
guest: one-vCPU, GICv3, architectural timer described as PPIs 29/30/27/26
```

The firmware-only reproducer proves a masked CVAL write/readback before
`ExitBootServices()` on the same vCPU (`BC`), restoring its saved register
values before continuing.  After the original `ExitBootServices()` return it
performs:

```text
now = CNTPCT_EL0
expected = now + 10,000,000
CNTP_CVAL_EL0 = expected
CNTP_CTL_EL0 = ENABLE=1, IMASK=0
DSB/ISB
```

It immediately reads back `CNTP_CVAL_EL0`, waits using the independently
working virtual timer PPI27 watchdog, then reads CVAL, counter and control
again. The observed serial suffix is:

```text
BES -> PD -> CX -> P0 -> P1 -> PW -> PC -> RX -> CE -> PN
```

Meaning:

```text
BES  original ExitBootServices returned
PD   CNTP_CTL enable/unmask readback passed
CX   immediate CNTP_CVAL readback differs from `expected`
PW   known-good CNTV/PPI27 watchdog fired
PC   CNTPCT advanced
RX   delayed CNTP_CVAL readback still differs from `expected`
CE   CNTPCT passed `expected`
PN   CNTP_CTL.ISTATUS is still clear
```

This excludes a guest counter stall, the virtual timer path, GIC PPI routing,
the PPI30 handler and `WFI` wake-up as the first failing layer. The guest
cannot retain/program its physical comparator deadline.

The masked pre-EBS success rejects a universal inability to access CVAL.  It
does not by itself prove an EBS context-transition failure, because the
post-EBS reproducer enables/unmasks CNTP before its readback.  Please treat a
pre-EBS enabled-CNTP control as an optional next vendor validation, not as a
claim already established by P5.

Please inspect, for an unprotected one-vCPU VM:

1. trapping/emulation of `CNTP_CVAL_EL0` and `CNTP_CTL_EL0` at EL2;
2. physical timer context initialization and save/restore around vCPU run;
3. comparator deadline arming and PPI30 injection;
4. whether this VM type intentionally supports only CNTV/PPI27. If so, its
   guest FDT/ACPI contract must not advertise a functional non-secure EL1
   physical timer.

This is not a request for a Windows workaround. The issue reproduces in
firmware before Windows code is executed, and a Linux/Windows guest cannot
repair `CNTP_*` via ACPI, BCD or a driver.

## Attached evidence manifest

| Artifact | SHA-256 / status |
|---|---|
| immutable Android runtime baseline before/after | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| P4 firmware FD | `AFB89B5A6F196599C6EE7C8C51404CB65B2D3B8FEB3B4372008BDE2D3EA53A37` |
| P4 transactional patch | `ADFF7CF9C7A531ADECE7241B11946C34550DC75F3C5B6B43B746EFD08289EC5E` |
| P4 raw serial | `D32D5EB49AC38EF07106DC35BC858B3FBDF227FA9F83F44336EB5DE00E25E1F8` |
| P4 rollback | PASS |
| P1 virtual CNTV/PPI27 | PASS |
| P2.1/P3 physical pending/comparator | FAIL |
| P4 physical CVAL retention | FAIL |
| P5 pre-EBS CVAL write/readback | PASS (`BC`) |
| P5 post-EBS CVAL write/readback | FAIL (`CX -> ... -> PN`) |
| P5 firmware FD | `7D547FE7BAA909402078A3BF7F4018A9350186191C67D03919266BC786561091` |
| P5 transactional patch | `AAF688B53F622322C3AC25E7A054D17292AC277632832DDACBBFE57847EA1E56` |
| P5 raw serial | `19F1D97C616CF1F21A586E6DD314EC00EF348F7B3C482445BD4ECF55299FF656` |
| P5 rollback | PASS |

The full procedure, source validation and raw serial are in:

- `SYNTHETIC_POST_EBS_P4_PHYSICAL_CVAL_RUNTIME_2026-09-12.md`
- `SYNTHETIC_POST_EBS_P5_PRE_EBS_CVAL_RUNTIME_2026-09-13.md`
- `GENIEZONE_P3_PHYSICAL_TIMER_OWNER_EVIDENCE_2026-09-12.md`
- `GENIEZONE_PUBLIC_TIMER_INTERFACE_AUDIT_2026-09-13.md`
