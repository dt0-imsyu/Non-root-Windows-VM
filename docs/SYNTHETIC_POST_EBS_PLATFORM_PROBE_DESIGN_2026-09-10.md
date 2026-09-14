# Synthetic post-EBS platform probe — design audit

## Purpose

This is a firmware-only diagnostic.  It deliberately replaces the Windows
handoff for one disposable run and answers whether the AVF/GenieZone virtual
platform remains executable after a successful UEFI `ExitBootServices()`.
It does not change Windows media, BCD, drivers, Android code, ACPI tables, or
the production baseline.

## Static facts from the current ArmVirtKvmTool tree

* The proven raw UART path is `SerialPortWrite()` through
  `BaseSerialPortLib16550`; the current EBS wrapper uses it in
  `ArmPkg/Library/PlatformBootManagerLib/PlatformBm.c`.
* `TimerDxe` disables the virtual generic timer in its EBS event:
  `ArmPkg/Drivers/TimerDxe/TimerDxe.c:92` calls
  `ArmGenericTimerDisableTimer()`.
* `ArmGicV3Dxe` disables every interrupt source, the CPU interface, and the
  distributor in its EBS event:
  `ArmPkg/Drivers/ArmGicDxe/GicV3/ArmGicV3Dxe.c:567`.
* The active timer library is the virtual-counter implementation, using
  `CNTVCT_EL0`, `CNTV_CTL_EL0`, and `CNTV_TVAL_EL0`:
  `ArmPkg/Library/ArmGenericTimerVirtCounterLib/`.
* Timer and GIC values are populated from the actual FDT before EBS.  The
  current runtime contract is GICD `0x3fff0000`, GICR `0x3ffd0000`, virtual
  timer PPI 27, one vCPU.

Consequently, an application that simply calls `ExitBootServices()` and then
waits for the pre-existing timer interrupt would *always* report a false
failure: firmware intentionally shut that path down.

## Safe split

The proposed test should be split into two firmware-only A/Bs, not presented
as one opaque all-or-nothing application.

### P0 — post-EBS execution and counter

A small embedded ARM64 UEFI application is launched by BDS in diagnostic
mode instead of Windows Boot Manager.  It acquires a final memory map, calls
the unmodified original `ExitBootServices()`, and afterwards uses no boot
services.

Raw serial markers:

```
P0  application entry
P1  original ExitBootServices returned EFI_SUCCESS
P2  direct UART write after EBS
P3  volatile RAM write/readback passed
P4  CNTVCT_EL0 advanced across a bounded spin interval
PR  ResetSystem requested
```

`P1..P4` establish execution, firmware-resident code/data access, direct
UART, and the ARM virtual counter independently of Windows.  The app then
uses only `gRT->ResetSystem()` to leave the disposable run; if reset does not
return, no fallback work is attempted.

### P1 — explicit timer/GIC/WFI

Only if P0 is clean, add a separate diagnostic source delta which explicitly
re-arms the components EDK2 disabled:

1. Re-enable the GICv3 CPU interface and distributor and the virtual timer
   PPI 27 using the current FDT-derived GIC base values.
2. Install a probe-owned IRQ vector/handler before EBS.  The handler must
   only acknowledge/EOI the PPI, set one volatile flag, and emit one raw byte;
   it must not call `gBS`, `DEBUG()`, protocol methods, allocation, or events.
3. Program `CNTV_TVAL_EL0`, execute `WFI`, and require the probe-owned flag
   before a bounded timeout.

Raw markers:

```
T0 GIC/timer rearmed
T1 WFI entered
T2 timer IRQ acknowledged by probe handler
T3 WFI returned with probe flag
```

The existing TimerDxe handler cannot be reused: it calls `gBS->RaiseTPL()`
after servicing the timer.  Likewise the existing GIC handler dispatches the
TimerDxe handler.  Reusing either after EBS would invalidate the experiment.

## Interpretation

| Result | Meaning |
|---|---|
| P0 pass | Generic execution, RAM, UART, and virtual counter survive EBS. |
| P0 fail before P2 | Post-EBS firmware execution/UART boundary needs direct investigation. |
| P0 pass, P1 fail before T2 | Exact timer/GIC re-arm or delivery boundary; not evidence about Windows yet. |
| P0/P1 pass | The tested post-EBS platform contract is alive; the Windows hang is Windows-specific or in an untested architectural contract. |

## Build/run constraints

* Reuse the proven r4 replay environment and the existing 2 MiB reversible
  firmware patch pipeline.  Do not repair the general toolchain.
* First perform a source-level control build with only the embedded probe
  selection disabled, then P0.  P1 is a later, separate source delta.
* Before a tablet run: archive FD SHA-256, source diff, patch SHA-256/range,
  and verify the immutable raw baseline
  `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
* After the one run: capture raw serial, roll back the exact firmware range,
  and recheck the immutable baseline hash.

## Runtime closure — 2026-09-10

P0 and the corrected P1 both passed. The initial P1 integration attempt was
rolled back after it exposed an invalid post-EBS PCD lookup; P1 now caches its
PCD-derived GICD base and timer source before EBS. The corrected raw sequence
was `BES → T0 → T1 → T2 → T3 → TR`, where `T2` is the PPI 27 handler and `T3`
is the return from `WFI`.

```text
POST_EBS_PLATFORM_CONTRACT = PASS
```

The PASS is intentionally scoped: post-EBS firmware execution, UART, volatile
RAM, virtual counter, GICv3 virtual timer delivery, and WFI wakeup are now
directly demonstrated. It is not a blanket proof of Windows compatibility.
Evidence: `SYNTHETIC_POST_EBS_P1_RUNTIME_2026-09-10.md`.
