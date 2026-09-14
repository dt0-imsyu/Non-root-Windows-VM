# Samsung / GenieZone submission kit — EL1 physical timer defect

## Purpose and scope

This package reports a **firmware-only architectural timer defect** observed
in an unprotected Android Virtualization Framework VM on a stock Galaxy Tab.
It deliberately does **not** claim that the defect is the proven cause of the
separate Windows post-`ExitBootServices()` stall. The two issues must be kept
separate during triage.

The report is suitable for Samsung Members first-line intake and for
escalation to the device firmware / GenieZone / MediaTek virtualization owner.
It is not a security-vulnerability report and should not be submitted to a
security-response channel.

## Where to submit

1. On the affected tablet, open **Samsung Members** → **Support** → **Error
   reports**. Choose the closest available category (normally *Other*,
   *System*, or *Performance*).
2. Paste the short report below, enable **Send system log data**, and submit.
   Record the resulting Samsung Members report ID.
3. Open Samsung Support chat/contact for the device region. Supply the report
   ID and the full technical report below, and explicitly request escalation
   to the **Galaxy Tab S11 firmware / GenieZone virtualization engineering
   owner**, with MediaTek escalation if Samsung owns the integration path.
4. Do not send full disk images, APKs, private app data, or a multi-gigabyte
   build-log directory. The serial evidence, hashes, and source-level
   reproducer description below are sufficient for initial engineering triage.

There is no verified public consumer defect tracker for the relevant
MediaTek/GenieZone implementation. Samsung is therefore the accountable first
contact for this Samsung firmware build.

## Short text for Samsung Members

**Title**

```text
[SM-X736B] AVF/GenieZone VM: advertised EL1 physical timer cannot retain CNTP_CVAL_EL0
```

**Body**

```text
On a stock SM-X736B (X736BXXS6BZF4_OXM6BZF4, Android kernel
6.6.102-android15-8-abogkiX736BXXS6BZF4-4k), an unprotected Android
Virtualization Framework VM exposes the ARM non-secure EL1 physical timer
(CNTP, PPI30), but a firmware-only guest probe cannot retain/program
CNTP_CVAL_EL0 after ExitBootServices.

The independent virtual timer CNTV/PPI27, GIC routing, WFI wake-up and guest
counter all pass. The physical timer probe gets: BES PD CX P0 P1 PW PC RX CE PN
(CVAL differs immediately and later; counter passes deadline; ISTATUS remains
clear). The same masked CVAL write/readback works before ExitBootServices.

Please escalate this as a GenieZone/AVF vCPU physical-timer issue. I can
provide the minimal firmware-only reproducer, raw serial evidence and hashes.
This is not a request for a Windows workaround and does not require root,
unlock, flashing, or modification of Samsung system software.
```

## Full technical report for support escalation

**Subject**

```text
[SM-X736B / MT6991] GenieZone unprotected VM does not retain guest CNTP_CVAL_EL0; CNTP ISTATUS never becomes pending
```

**Body**

```text
Please route this to the Galaxy Tab S11 firmware / GenieZone virtualization
engineering owner (and MediaTek as appropriate).

On a stock Samsung SM-X736B, an unprotected Android Virtualization Framework
VM executes a firmware-only ARM generic-timer test. The guest's virtual timer
(CNTV/PPI27) works, but the advertised non-secure EL1 physical timer
(CNTP/PPI30) does not retain its comparator deadline after UEFI
ExitBootServices.

Device/build:
  model: SM-X736B
  firmware: X736BXXS6BZF4_OXM6BZF4
  Android kernel: 6.6.102-android15-8-abogkiX736BXXS6BZF4-4k
  backend: Android AVF crosvm -> /dev/gzvm -> GenieZone
  guest: one vCPU, GICv3, architectural timer PPIs 29/30/27/26

After the original ExitBootServices() has returned, the probe does:
  now = CNTPCT_EL0
  expected = now + 10,000,000
  CNTP_CVAL_EL0 = expected
  CNTP_CTL_EL0 = ENABLE=1, IMASK=0
  DSB/ISB

It immediately reads CVAL, waits on an independently working CNTV/PPI27
watchdog, then rereads CVAL, counter and control. The raw serial suffix is:
  BES -> PD -> CX -> P0 -> P1 -> PW -> PC -> RX -> CE -> PN

Meaning:
  BES  original ExitBootServices returned
  PD   CNTP_CTL enable/unmask readback passed
  CX   immediate CNTP_CVAL readback differs from expected
  PW   independent CNTV/PPI27 watchdog fired
  PC   CNTPCT advanced
  RX   delayed CNTP_CVAL still differs from expected
  CE   CNTPCT passed expected deadline
  PN   CNTP_CTL.ISTATUS remains clear

This separates the failure from a counter stall, virtual timer, GIC PPI
routing, PPI30 handler, or WFI wake-up. The guest cannot retain/program its
physical comparator deadline.

An explicit phase control also exists: the same vCPU can perform a masked
CNTP_CVAL write/readback before ExitBootServices (PASS), whereas the post-EBS
test fails. This alone does not prove an ExitBootServices context-transition
bug because post-EBS additionally enables/unmasks CNTP. Please treat that
phase distinction as evidence for investigation, not as a claim that the
transition itself is already proven defective.

Requested investigation for an unprotected one-vCPU VM:
  1. EL2 trapping/emulation of CNTP_CVAL_EL0 and CNTP_CTL_EL0;
  2. vCPU physical-timer context initialization and save/restore;
  3. comparator deadline arming and PPI30 injection;
  4. whether this VM class intentionally supports only CNTV/PPI27. If so,
     guest FDT/ACPI must not advertise a functional non-secure EL1 physical
     timer.

This is a firmware-only architectural-timer report, not a Windows-support
request. No root, bootloader unlock, system modification, or signed Windows
binary modification is involved.
```

## Evidence to provide on request

| Evidence | SHA-256 / result |
|---|---|
| Immutable runtime baseline before and after each test | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| P4 firmware FD | `AFB89B5A6F196599C6EE7C8C51404CB65B2D3B8FEB3B4372008BDE2D3EA53A37` |
| P4 raw serial | `D32D5EB49AC38EF07106DC35BC858B3FBDF227FA9F83F44336EB5DE00E25E1F8` |
| P5 firmware FD | `7D547FE7BAA909402078A3BF7F4018A9350186191C67D03919266BC786561091` |
| P5 raw serial | `19F1D97C616CF1F21A586E6DD314EC00EF348F7B3C482445BD4ECF55299FF656` |
| P1 virtual CNTV/PPI27 | PASS |
| P4 physical CVAL retention | FAIL |
| P5 masked pre-EBS CVAL write/readback | PASS (`BC`) |
| P5 post-EBS CVAL write/readback | FAIL (`CX -> ... -> PN`) |
| Every firmware test rollback | PASS |

The full reproducibility chain is recorded in:

- `GENIEZONE_VENDOR_ISSUE_DRAFT_2026-09-13.md`
- `SYNTHETIC_POST_EBS_P4_PHYSICAL_CVAL_RUNTIME_2026-09-12.md`
- `SYNTHETIC_POST_EBS_P5_PRE_EBS_CVAL_RUNTIME_2026-09-13.md`
- `GENIEZONE_P3_PHYSICAL_TIMER_OWNER_EVIDENCE_2026-09-12.md`
- `GENIEZONE_PUBLIC_TIMER_INTERFACE_AUDIT_2026-09-13.md`

## Triage boundary

The project separately observes a Windows ARM64 handoff stall after successful
`ExitBootServices()`. Current static analysis shows the investigated WinPE
path uses the virtual timer, so this report must **not** be closed as a generic
"Windows is unsupported" request and must **not** state the physical-timer
defect is already the direct cause of that stall. The timer defect is
independently reproducible without Windows code.
