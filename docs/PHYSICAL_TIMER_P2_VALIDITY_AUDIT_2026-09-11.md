# Physical-timer P2 validity audit — 2026-09-11

## Corrected verdict

```text
P2_VALID                           = INCOMPLETE
POST_EBS_PHYSICAL_TIMER_PPI30      = NOT_CONFIRMED
WINDOWS_BLOCKER_PHYSICAL_TIMER     = UNPROVEN
```

P2 was a sound source-selection change (`CNTP_*` plus FDT-derived PPI30), but
its completion condition was too weak. After arming a 10,000,000-tick physical
deadline it executes exactly one `WFI`; on return it emits `TX` whenever its
PPI30 handler did not set `mFired`. `WFI` is allowed to return after *any*
unmasked interrupt. Thus `P1 -> TX` says only that PPI30 had not been handled
when that first wake occurred; it does not prove that the physical deadline
could never have been delivered later.

## Architecture and platform facts

The AArch64 EL1 physical and virtual timers are distinct timer instances:

| Timer | Registers tested | Counter | SBSA PPI |
|---|---|---|---:|
| Non-secure EL1 physical | `CNTP_CTL_EL0`, `CNTP_TVAL_EL0`, `CNTP_CVAL_EL0` | `CNTPCT_EL0` | 30 |
| EL1 virtual | `CNTV_CTL_EL0`, `CNTV_TVAL_EL0`, `CNTV_CVAL_EL0` | `CNTVCT_EL0` | 27 |

`TVAL` creates `CVAL = current count + TVAL`; with `ENABLE=1` and
`IMASK=0`, expiry asserts a level-sensitive PPI. EL2 can trap/emulate the
physical timer; the virtual timer uses `CNTVOFF_EL2`. These details, including
the PPI assignments, are specified by Arm's generic-timer guide.

The firmware maps its FDT timer tuple in order secure, non-secure physical,
virtual, hypervisor into EDK2 PCDs, then copies those fields unchanged into
GTDT. The active values are PPI `29, 30, 27, 26`. GTDT's non-secure EL1
physical GSIV is a hardware description, not a switch that redirects CNTP to
CNTV. `Always-on` concerns wake capability and is not a selection override.

## Linux differential

The successful Linux v3 raw log contains:

```text
arch_timer: cp15 timer(s) running at 13.00MHz (virt)
```

This proves that this Linux kernel selected the virtual clock-event timer. Its
upstream selection logic chooses virtual PPI when the kernel is not itself in
HYP mode and a virtual PPI exists; otherwise arm64 chooses the non-secure
physical PPI. Linux therefore neither exercises nor validates PPI30 in this
successful boot.

## Windows evidence limit

Microsoft documents that Windows uses GTDT for its built-in ARM Generic Timer
support, and the installed WDK enumerates both `CNTP_*` and `CNTV_*` system
registers. Neither Microsoft documentation nor public symbols disclose the
early Windows ARM64 HAL selection algorithm. Consequently it is not valid to
infer the Windows choice from GTDT merely containing PPI30, and no
specification-valid GTDT property is known that forces Windows onto CNTV/PPI27.

```text
WINDOWS_EARLY_TIMER_SELECTION = UNKNOWN
VALID_WINDOWS_TIMER_SELECTION_A_B = NOT_IDENTIFIED
```

## Required P2.1 before any escalation

P2.1 must remain firmware-only and use the same reversible one-range patch
path. It should:

1. Arm CNTP/PPI30 as P2 did.
2. Also arm the already-proven CNTV/PPI27 as a several-second watchdog.
3. Loop on `WFI` until either PPI30 fires or the PPI27 watchdog fires.
4. On watchdog, sample `CNTP_CTL_EL0.ISTATUS` and emit a fixed marker.

Interpretation:

| Result | Meaning |
|---|---|
| PPI30 handler before watchdog | physical timer delivery PASS |
| watchdog plus `CNTP_CTL.ISTATUS=1`, no PPI30 | CNTP expired but its PPI was not delivered: strong VMM/GIC evidence |
| watchdog plus `ISTATUS=0` | physical timer did not become pending: timer access/emulation evidence, not a GIC claim |

Only the second outcome, followed by a separate proof of Windows timer choice,
can elevate the physical-timer theory above `STRONG_HYPOTHESIS`.

## P2.1 attempt — blocked before probe entry

P2.1 built successfully in the recorded r4-replay environment. Its FD SHA-256
is `65C3A5673240CC31D0DCCF019722A7DAC110C198FA3F3843D57DB8669E80448D`,
and its application PE SHA-256 is
`F63E4923A8DA45F92299A88B30B403084512034C6A30DA4E0F2104A9C221BF7D`.
The build log records both intended defines, and the PE contains the `PW`,
`PS`, and `PN` watchdog markers.

The one bounded product run was invalid before probe entry: immediately in
DXE, `ConSplitterDxe.dll` took an instruction-permission abort. There is no
`Q0`, `BES`, or P2.1 marker. The transactional runner nevertheless completed
exact rollback to the immutable baseline.

```text
P2_1_BUILD                  = PASS
P2_1_RUNTIME_PROBE_ENTRY    = FAIL (ConSplitterDxe instruction abort)
P2_1_TIMER_RESULT           = NOT_OBSERVED
BASELINE_ROLLBACK            = PASS
```

This is a firmware-build/runtime reproducibility blocker, not timer evidence.
Do not turn it into a ConSplitterDxe/toolchain investigation within this
timer-audit scope. Recover a known-working firmware build state, then rerun
the unchanged P2.1 probe.

## P2 replay and P2.1 FD forensic comparison — scope stop

The archived working P2 FD (`A6873FEF6C3B9F206692EA64DBC88069B5F6856D7C0F437BF0425F39811EFFAC`)
was first replayed using the recorded command, tool paths, wrappers and its
single `AVF_POST_EBS_USE_PHYS_TIMER` define.  The replay finished with
`- Done -` and the same FVMAIN occupancy (`5,410,048` total bytes,
`5,410,024` used, `24` free), but it was not byte-identical:
`724,006` differing bytes in `2,884` ranges, first at offset `77,550`.

P2 versus P2.1 differs similarly (`724,136` bytes in `2,791` ranges, first at
offset `156,501`).  Therefore that latter difference cannot be attributed to
the P2.1 watchdog code: a fresh full rebuild already fails the P2 control.
The exact P2 workspace/generated Build tree was not archived, so this does not
identify whether source state or packaging output causes the drift.

```text
R4_BUILD_ENV_COMMAND_REPLAY      = PASS
P2_BITWISE_FIRMWARE_REPRODUCTION = FAIL
P2_1_RUNTIME_INTERPRETABILITY    = BLOCKED
P2_1_RERUN                       = NOT_AUTHORIZED
```

Do not patch ConSplitterDxe, hand-edit the FD, or begin a general EDK2/MSYS
reconstruction from this result.  The bounded timer task stops here. See
`docs/P2_FIRMWARE_BUILD_REPLAY_FORENSIC_2026-09-11.md` for exact artifacts.
A later firmware-build recovery task must first reproduce the archived P2 FD
before the unchanged P2.1 test can be meaningful.

## Sources

- [Arm Generic Timer programmer's guide](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/Generic%20Timer.pdf?revision=c710e7a7-9f52-4901-8c9d-91b19f44f9c7)
- [Linux arm_arch_timer selection implementation](https://codebrowser.dev/linux/linux/drivers/clocksource/arm_arch_timer.c.html)
- [Microsoft: Windows Arm GTDT support](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/acpi-system-description-tables)
