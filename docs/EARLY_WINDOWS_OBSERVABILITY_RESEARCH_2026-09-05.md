# Early Windows observability research — 2026-09-05

## Result

```text
EARLY_WINDOWS_OBSERVABILITY = BLOCKED
```

This is a static-only conclusion.  No WIM, FAT image, BCD store, firmware,
Android runtime image, or tablet state was changed.  No runtime candidate was
built or staged.

The already confirmed boundary remains:

```text
ExitBootServices / ER = PASS
Windows kernel/HAL early initialization = UNKNOWN
BOOT_START_LOAD = INCONCLUSIVE_DUE_TO_CI
SMSS_BOOTEXECUTE = NOT_CONFIRMED
STARTNET_CMD_EXECUTION = NOT_CONFIRMED
WINPE_USERLAND = NOT_CONFIRMED
```

## Static target audit

The exact baseline WinPE source was inspected read-only:

```text
build-logs/boot-gop-ebs-r1-a3-extracted-source.wim, index 2
```

It contains ARM64 Microsoft-signed `winload.efi`, `ntoskrnl.exe`, `kdcom.dll`,
and `kdnet_uart16550.dll`.  `signtool verify /kp` passed for all four extracted
binaries.  The presence of the KD modules establishes only that Windows has
the signed components; it does not create a usable debugger transport.

`winload.efi` static strings include `BOOTLOG`, `BOOTDEBUG`, `DEBUGPORT`, and
`RecoveryEnabled`.  This is consistent with the documented BCD-controlled
boot-debug and boot-log facilities, but does not make any of them observable
on the present AVF configuration.

## Paths evaluated

| Path | Earliest possible boundary | Why it cannot provide this test's signal |
|---|---|---|
| KD / boot debugger | `winload` through kernel startup | Requires BCD debug settings and a bidirectional debugger transport.  AVF presently exposes serial output only; prior COM1/KD tests had no usable input/pipe endpoint.  BCD changes are prohibited for this pass. |
| EMS | Boot manager / loader | Also BCD-controlled and needs a usable serial interaction path.  The prior EMS A/B produced no independent serial evidence. |
| `bootlog` / `Ntbtlog.txt` | After kernel driver loading begins | BCD-controlled.  Its output file is written below `%WINDIR%`, which is the volatile WinPE RAM disk until a later persistent-volume path exists.  It cannot distinguish a failure before filesystem/log initialization from inability to persist the result. |
| Boot Status Data / `BOOTSTAT.DAT` | Boot/recovery bookkeeping | It records boot/recovery state, not a unique loader/kernel phase marker.  It can be stale or reflect a later recovery decision, and no existing export path turns it into a per-stage signal. |
| Crash/minidump | After a deliberate bugcheck and dump-stack initialization | Needs a controlled failure plus a functioning dump/storage path.  It is neither harmless nor a direct marker for normal phase-0/phase-1 progress. |
| Configuration-only use of existing Microsoft boot-start drivers | Boot driver loading | Locally available signed drivers (`acpi.sys`, `pci.sys`, `disk.sys`, `Classpnp.sys`) expose no standalone observable event.  A service/order/device-state failure has an ambiguous absence of signal and cannot prove driver acceptance or `DriverEntry`. |

Microsoft documentation confirms that `bootlog` and debug settings are BCD
settings, and that kernel debugging over serial/VM transport requires a
configured debugger connection.  See [BCDEdit settings for Windows drivers](https://learn.microsoft.com/windows-hardware/drivers/devtest/bcdedit--set), [KDNET extensibility and boot debugging](https://learn.microsoft.com/windows-hardware/drivers/debugger/how-to-develop-kdnet-extensibility-modules), and [kernel debugging of a virtual machine](https://learn.microsoft.com/windows-hardware/drivers/debugger/attaching-to-a-virtual-machine--kernel-mode-).

## Exact blocker

No remaining stock early-boot mechanism simultaneously has all of the
following properties:

1. a real external signal in the current AVF environment;
2. no BCD/test-signing change;
3. no custom kernel code;
4. no modification of a Microsoft/WHCP-signed binary or its catalog; and
5. unambiguous attribution to one of the requested loader/kernel phases.

The limiting interfaces are therefore **transport plus policy**, not a new
FAT/WIM problem:

```text
AVF serial is output-only for this VM
  + BCD debugging/EMS/bootlog is disallowed
  + unsigned driver acceptance is unproven under CI
  + signed release drivers do not emit an independent marker
  = no conforming early Windows-side observable boundary
```

## Decision

Do not create or run another media candidate under the current constraints.
In particular, do not infer anything new from the absent BootExecute or
`startnet.cmd` effects, and do not use the unsigned boot-start probe.

## One minimally invasive next experiment, if new authority is granted

The most informative next runtime A/B is a **temporary BCD boot-debug/KD
configuration over a genuinely bidirectional AVF console bridge**, using only
the already Microsoft-signed `winload`, `ntoskrnl`, and KD transport modules.
It would require two explicit policy changes that are currently forbidden:

1. expose a real bidirectional host endpoint for the VM serial channel; and
2. apply then roll back the minimal BCD debugger settings.

It would not require testsigning, custom kernel drivers, modified signed
binaries, firmware work, or filesystem transport changes.  Until that
authority and transport exist, there is no valid one-run runtime test in this
branch.
