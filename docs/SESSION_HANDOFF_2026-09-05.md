# WinAVF continuation handoff — 2026-09-05

This handoff preserves the verified state, artifacts, commands, and hard
boundaries for a fresh Codex session.  Treat all device/media changes as
transactional and retain the immutable baseline.

## Current verified milestones

```text
EXIT_BOOT_SERVICES_RETURN       = PASS
MODIFIED_WIM_EBS                = PASS
MODIFIED_WIM_TRANSPORT          = PASS
STARTNET_CMD_EXECUTION          = NOT_CONFIRMED
SMSS_BOOTEXECUTE                = NOT_CONFIRMED
WINPE_USERLAND                  = NOT_CONFIRMED
BOOT_DRIVER_ACCEPTED            = UNKNOWN
BOOT_START_LOAD                 = INCONCLUSIVE_DUE_TO_CI
EARLY_WINDOWS_OBSERVABILITY     = BLOCKED
AVF_SERIAL_BIDIRECTIONAL_BINARY = BLOCKED
WINDOWS_KD_HANDSHAKE            = NOT_TESTED
```

Confirmed last Windows-side observable point: raw EDK2 audit marker `ER`,
which is emitted after the original `ExitBootServices()` returns to the
Windows loader.  It is not merely the ExitBootServices event callback.

## Immutable baseline and device

```text
Baseline raw image:
handoff-compact-2026-08-23/handoff-compact-2026-08-23/
windows-headless-media/win11-gop-ebs-r1.img

Baseline SHA-256:
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7

Android device serial: R52Y9072A2R
Package: com.example.winavf
External app directory:
/sdcard/Android/data/com.example.winavf/files
```

Never overwrite the immutable source image.  The app’s small patch workflow
checks the runtime baseline hash before application and verifies the exact
rollback after a test.  Do not deploy a full 9 GB image if the verified patch
pipeline is available.

## Completed runtime experiments

| Experiment | Single external effect expected | Result |
|---|---|---|
| Harmless append-only WIM | Reach EBS post-return | PASS; proves WIM/FAT transport |
| `startnet.cmd = wpeutil reboot` | VM reset | No reset; `ER`; rollback PASS |
| Pre-`wpeinit` persistent marker | marker file / reset | None; `ER`; rollback PASS |
| Native `BootExecute` probe | `NtShutdownSystem(ShutdownReboot)` | No reset; `ER`; rollback PASS |
| Custom BOOT_START probe | UART `D/S` | Not run: only self-signed, no catalog, `/kp` fails |
| KD transport feasibility | bidirectional byte API | BLOCKED: no console input API |

Exact hashes, patch ranges, serial SHA-256 values, and offline verification
details are retained in these reports:

```text
docs/WINPE_STARTNET_REBOOT_ONLY_RUNTIME_2026-09-05.md
docs/WINPE_PRE_WPEINIT_MARKER_RUNTIME_2026-09-05.md
docs/SMSS_BOOTEXECUTE_RUNTIME_2026-09-05.md
docs/BOOT_START_ACCEPTANCE_PREFLIGHT_2026-09-05.md
docs/EARLY_WINDOWS_OBSERVABILITY_RESEARCH_2026-09-05.md
docs/KD_TRANSPORT_FEASIBILITY_2026-09-05.md
```

## Available tools and where they are used

```text
adb.exe                                  Android device queries and app launch
wimlib-imagex.exe                        WIM list/extract/update/verify
signtool.exe                             Authenticode and kernel-policy checks
llvm-objdump.exe                         PE architecture/subsystem/import metadata
PowerShell                               hashes, read-only image audits, patch tools
```

Useful read-only commands from repository root:

```powershell
# Connected device and installed app
adb devices -l
adb shell getprop ro.build.fingerprint
adb shell dumpsys package com.example.winavf

# Invoke only the non-VM AVF capability audit, then retrieve its raw result
adb shell am start -n com.example.winavf/.MainActivity --ez audit true
adb exec-out cat /sdcard/Android/data/com.example.winavf/files/avf-capability-audit.txt

# Verify immutable baseline before considering any patch
Get-FileHash .\handoff-compact-2026-08-23\handoff-compact-2026-08-23\windows-headless-media\win11-gop-ebs-r1.img -Algorithm SHA256

# Inspect current launcher source console calls
rg -n -C 4 'getConsoleOutput|getConsoleInput|setConsoleInputDevice|setVmConsoleInputSupported' .\android-app\src\com\example\winavf\MainActivity.java
```

For WIM work, use the existing scripts/reports and preserve these minimum
offline gates before any tablet stage:

```text
wimlib verify = PASS
FAT1/FAT2 chain reconstruction = PASS
directory size/start-cluster invariants = PASS
reconstructed BOOT.WIM SHA-256 = expected
rollback simulation = PASS
tablet runtime baseline SHA-256 = expected
```

## KD transport finding

The device’s real `VirtualMachine` runtime API exposes
`getConsoleOutput(): InputStream`, but no `getConsoleInput()`, writable
console FD, or UART write Binder.  The launcher’s configuration mentions
`ttyS0` and `setVmConsoleInputSupported(true)`, but those settings do not
return an input endpoint.  A previous input attempt failed with
`NoSuchMethodException`.

The guest UART output is at `0x3f8`, hence a plausible COM1-style KD target,
but only output is available.  There is no valid host KD bridge and BCD must
remain unchanged.  Full raw evidence and exact method list:

```text
../build-logs/kd-feasibility-20260905/
docs/KD_TRANSPORT_FEASIBILITY_2026-09-05.md
```

## Hard constraints still in force

- Do not infer a kernel failure from absent custom driver markers: acceptance
  under Code Integrity is unknown.
- Do not modify Microsoft/WHCP signed drivers or catalog members.
- Do not enable testsigning or alter BCD merely to make an unsigned probe run.
- Do not run BCD bootdebug until a real bidirectional binary console endpoint
  exists; otherwise a missing KD handshake is meaningless.
- Do not return to graphics/vsock/PnP/startnet/wpeinit before an earlier
  observable boundary is found.
- Do not modify firmware, EDK2, GOP, ACPI, GIC, timer, PSCI, or system crosvm
  for this diagnostic branch.

## Only useful next action

Obtain a documented writable AVF console endpoint available to the untrusted
launcher, or explicit authority for a platform-side bridge.  Re-run the
non-VM capability audit and prove byte-for-byte duplex I/O with U-Boot before
making any BCD change.  Without that capability, there is no diagnostic KD
runtime experiment to perform.
