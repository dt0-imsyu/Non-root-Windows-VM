# ADB-shell AVF console / KD feasibility audit — 2026-09-07

## Result

```text
ADB_SHELL_AVF_CONSOLE_RX       = AVAILABLE_ONLY_FOR_SHELL_CREATED_VM
ADB_SHELL_BIDIRECTIONAL_COM1   = YES (shell-created VM only)
SHELL_VM_TOPOLOGY_EQUIVALENT   = PARTIAL
KD_DEBUG_ONLY_PATH             = AVAILABLE (diagnostic shell-VM path)
```

The first loopback used an unsuitable ordinary file for `--console-in`. Its
`EPERM` was crosvm adding that non-pollable file to epoll, not a Samsung
platform denial. The subsequent inherited-pipe loopback passed exact 4,096-byte
binary echo in both directions. See
`docs/SHELL_SERIAL_PIPE_LOOPBACK_RUNTIME_2026-09-07.md`.

The production APEX exposes shell CLI `/apex/com.android.virt/bin/vm`.
`vm run` documents separate `--console` and `--console-in` file descriptors
for a separate shell-created custom VM. This is not an export of the hidden
console-input descriptor of the app-owned WinAVF VM. Interactive `vm console`
is a PTY / `microcom` terminal path, not a proven binary bridge.

No VM was created, started, attached, stopped, or modified. No BCD, Windows
media, firmware, Android APK, system service, or SELinux policy was changed.

## Device and CLI evidence

| Field | Observation |
|---|---|
| caller | `uid=2000(shell)`, `u:r:shell:s0`; SELinux enforcing |
| build | `user`, `release-keys`, `ro.debuggable=0`, SDK 36 |
| backend | `vm info`: `Hypervisor version: GenieZone`; `/dev/kvm` absent |
| APEX CLI | `/apex/com.android.virt/bin/vm`, executable by shell |
| service shell API | no `cmd` or `dumpsys` interface for virtualizationservice |

Only `vm --help`, subcommand help, `vm list`, and `vm info` were run.
`vm run --help` documents:

```text
--cpu-topology <CPU_TOPOLOGY>   default one_cpu
--mem <MEM>
--console <CONSOLE>             path for VM console output
--console-in <CONSOLE_IN>       path for VM console input
--log <LOG>
--gdb <GDB>                     Linux guest-kernel gdb server only
--dump-device-tree <PATH>
<CONFIG>                        custom VM config JSON
```

The installed CLI embeds `packages/modules/Virtualization/android/vm/src/run.rs`
and error strings for opening console output/input FDs. It separately states:

```text
Stdin must be a terminal (tty). Use 'adb shell -t' to force allocate tty.
Use `microcom <path>` to connect to console
```

Thus `vm run --console` plus `--console-in` is the raw-FD candidate. In
contrast, `vm console [CID]` is terminal-facing PTY. PTY line discipline, echo,
or conversion make it unsuitable for a KD claim until byte-level proof exists.

## Existing VM boundary

`vm list` can enumerate a Samsung Terminal VM (CID `2084`, requester UID
`10315`) but reports `hostConsoleName: None`. Shell cannot read its
`/data/misc/virtualizationservice/2084` directory or crosvm `/proc/<pid>/fd`
table. This audit did not run `vm console 2084`: attaching to a live unrelated
VM is interactive, not read-only.

The retained framework source shows separate output/input
`ParcelFileDescriptor`s passed into `IVirtualizationService.createVm()`.
`setVmConsoleInputSupported(true)` supplies a pipe writer to the **VM owner**.
Host-console connection instead creates a PTY pair and is gated by
`Build.isDebuggable()`. The device has `ro.debuggable=0`; the live Terminal
VM's absent host console is consistent with that gate. Enumeration grants shell
no ownership of the app's unavailable input descriptor.

WinAVF itself uses one CPU, 4 GiB, `ttyS0`, captured output, and console-input
support. Its reflection call to `getConsoleInput()` is known to fail on this
tablet. Shell has no documented operation to export that FD from an existing
app-owned VM.

## Topology and binary status

Shell `vm run` can set a custom kernel or bootloader, initrd, parameters, disks,
memory, and CPU topology. It defaults to one CPU, matching current WinAVF, and
uses the same GenieZone AVF backend. It cannot yet reproduce or inspect exact
app-private FD wiring, crosvm serial/PCI ordering, r9 patch staging, or
generated FDT/ACPI/GIC/timer state. Therefore topology equivalence is PARTIAL.

The `--console`/`--console-in` FD descriptions show no UTF-8 conversion, and
they are better candidates than PTY for a shell-owned FIFO/pipe bridge. No VM
was launched, so 8-bit/NUL preservation, CR/LF/echo absence, live KD framing,
and mapping to guest `ttyS0`/Windows COM1 are still unproven. Hence COM1 and KD
are CONDITIONAL, not PASS.

## Binder and Samsung Terminal

`service list` contains `android.system.virtualizationservice`, but neither
`cmd android.system.virtualizationservice ...` nor `dumpsys
android.system.virtualizationservice` resolves. `service call` was not used:
unknown transaction numbers are not read-only schema queries. Samsung Terminal
is a privileged system package with `MANAGE_VIRTUAL_MACHINE`; its service and
crosvm state is not readable to shell. No signature, SELinux, or Binder bypass
was attempted.

## Proposed separate KD experiment — not authorized or run

```text
WinDbg/KD <-> adb raw stream / binary-safe local bridge
          <-> shell FIFO or inherited FD passed as vm run --console-in
          <-> shell-created AVF serial FD
          <-> crosvm serial hardware=serial,num=1
          <-> guest ttyS0 / Windows COM1
```

First prove bidirectional `0x00..0xFF` loopback in a disposable non-Windows
shell-owned VM. Only then consider an isolated BCD bootdebug patch for a
shell-owned Windows clone. Capture that clone's FDT and crosvm args and compare
them with WinAVF. It remains diagnostic-only until equivalence is demonstrated.

## Evidence

Captured help/list/info output: `build-logs/adb-shell-avf-console-audit-20260907/`.
Framework source: `handoff-compact-2026-08-23/handoff-compact-2026-08-23/framework-virtualization-source/src/android/system/virtualmachine/VirtualMachine.java`.
