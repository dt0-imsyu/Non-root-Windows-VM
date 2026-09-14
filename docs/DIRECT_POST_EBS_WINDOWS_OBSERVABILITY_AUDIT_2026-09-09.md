# Direct post-EBS Windows observability audit — 2026-09-09

## Scope and result

This was an exhaustive **read-only** audit of the interfaces exposed to the
ADB `shell` domain on the Samsung Galaxy Tab S11. No VM was launched; no
Windows media, BCD, firmware, Android application, driver, or device setting
was changed.

```text
DIRECT_POST_EBS_WINDOWS_OBSERVABILITY = BLOCKED   (exact app-owned product VM)
SHELL_GUEST_GDB_PC_OBSERVER            = BLOCKED
PRODUCT_APP_GDB_PC_OBSERVER             = BLOCKED
```

`BLOCKED` is deliberately limited to a direct observer for the product VM:
there is no shell-readable endpoint yielding guest PC/registers, vCPU exits,
virtual IRQ/GIC state, timer state, WFI/WFE, or guest exception state. The one
viable direct PC mechanism is crosvm's GDB server, but the installed
app-owned `VirtualMachineConfig.Builder` does not expose a `gdbPort` setter.

## Device and access facts

| Field | Observed value |
|---|---|
| Device | Samsung `SM-X736B`, Android 16 / SDK 36 |
| Host kernel | `6.6.102-android15-8-abogkiX736BXXS6BZF4-4k`, arm64 |
| ADB identity | `uid=2000(shell)`, SELinux `u:r:shell:s0`, enforcing |
| AVF implementation | `vm info`: GenieZone, non-protected VMs supported |
| Product VM mode | non-protected, debug full, one vCPU, custom-VM permissions granted |

The product package `com.example.winavf` has both
`MANAGE_VIRTUAL_MACHINE` and `USE_CUSTOM_VIRTUAL_MACHINE` granted. Its
runtime reflection inventory exposes console input/output and debug-level
controls, but has no `setGdbPort` method or GDB-port field in
`VirtualMachineConfig` or its builder.

## Audit matrix

| Candidate | Evidence | Result |
|---|---|---|
| KVM ftrace | `/sys/kernel/tracing/events/kvm` contains `kvm_entry`, `kvm_exit`, `kvm_userspace_exit`, `kvm_wfx_arm64`, guest/access-fault, IRQ/vGIC and timer events. | **Blocked**: shell receives `Permission denied` for event `enable`, `format`, `filter`, trigger and global tracer metadata. |
| GZVM/GenieZone ftrace | No `/sys/kernel/tracing/events/gzvm`; Perfetto advertises only generic `linux.ftrace`, not a GenieZone/GZVM source. | **Blocked**. |
| Prior ftrace evidence | Bounded KVM and GenieZone traces had real `crosvm_vcpu0` activity but zero relevant packets. | **Not usable**; do not repeat. |
| `/dev/gzvm` ioctl | Node exists as `u:object_r:gzvm_device:s0`, nominal mode `0666`. A zero-byte shell open returned `Permission denied`. | **Blocked by SELinux before ioctl**; no ioctl was sent. |
| `/dev/vhost-vsock` | Same controlled zero-byte open returned `Permission denied`. | Not a VMM-state observer; also **SELinux-blocked**. |
| debugfs/sysfs modules | `gzvm`, `gz_virtio_mod`, `gz_main_mod`, `pkvm_mkp` and related modules are loaded; module sections advertise tracepoint/ftrace sections. `/sys/kernel/debug` is empty to shell and protected section reads are denied. | **No usable debug endpoint**. |
| eBPF / kallsyms / kmsg | `/sys/fs/bpf` is SELinux-protected; `/proc/kallsyms` and `dmesg` are denied. | **Blocked**. |
| simpleperf / PMU | `perf_event_paranoid=-1`; host raw exception counters such as `raw-exc-irq` and `raw-exc-hvc` are listed. | **Insufficient**: host aggregate counters cannot expose guest PC, exit reason, virtual GIC/timer, or guest exception state. |
| Samsung ISehHyPer HAL | `dumpsys vendor.samsung.hardware.hyper.ISehHyPer/default` returns a HyPer QoS/request dump only. No `cmd` service, schema, guest identifier, PC, register, exit, or trace control is exposed. | **No guest observer**. |
| AVF console | Product `getConsoleInput()` / `getConsoleOutput()` are byte-exact on `ttyS0` / `0x3f8`. | Transport only; it cannot reveal CPU state without guest cooperation. |
| crosvm GDB | CLI advertises `--gdb <port>` on this Android 6.6 host. AOSP documents a GDB server for debuggable non-protected VMs. Actual Samsung VirtMgr rejected raw `vm run --gdb`, even with explicit `--debug full`, before VM creation. | **Blocked for shell raw Windows VM**; **conditional for product app** pending a supported `gdbPort` path. |

The device has no `/dev/kvm`; the running AVF implementation is GenieZone.
This does not remove the crosvm GDB feature, but it rules out direct ordinary
KVM ioctl inspection from shell.

## Why GDB is the only remaining direct PC path

The installed `vm run` CLI accepts `--gdb <port>`. AOSP specifies that crosvm
starts a GDB server and waits for a client before booting a debuggable,
non-protected VM. The service implementation takes `gdbPort` from raw config
or `AppConfig.CustomConfig`, and its documented eligibility checks are only a
non-protected VM and a debug level other than `NONE`.

On this Samsung build the documented CLI is not sufficient: the actual raw
Windows request was rejected as non-debuggable even with `--debug full`, before
the VM existed. The product-side builder also has no GDB-port setter. The
follow-up configuration audit establishes why this is decisive: custom-image
VMs are converted to RawConfig, whose converter never assigns `gdbPort`; the
AppConfig `CustomConfig.gdbPort` route is not used. Product GDB is blocked.

## Negative evidence

The following were intentionally not retried because prior bounded evidence
already excludes them as direct observers:

* `docs/KVM_FTRACE_POST_EBS_R9_RUNTIME_2026-09-07.md` — active vCPU, zero
  KVM packets.
* `docs/GENIEZONE_FTRACE_POST_EBS_R9_RUNTIME_2026-09-07.md` — active vCPU,
  zero vendor packets.
* `docs/POST_EBS_PERFETTO_R9_RUNTIME_2026-09-07.md` — scheduler activity is
  host liveness, not guest instruction state.

## Next one informative boundary

Do **not** create another BCD, Windows-KD, or raw shell-GDB variation. The
next proposed boundary is:

```text
LATER_SIGNED_OR_FIRMWARE_VISIBLE_BOUNDARY = IDENTIFY
```

Product GDB-port configurability has failed without a VM run. A next experiment
must identify a later signed Windows-visible or firmware-visible side effect,
or wait for a vendor-published GenieZone/GZVM trace interface. See
`docs/PRODUCT_GDB_PORT_CONFIGURATION_AUDIT_2026-09-09.md`.

## External source basis

* AOSP, [Debugging guest kernels with gdb](https://android.googlesource.com/platform/packages/modules/Virtualization/+/refs/heads/main/docs/debug/gdb_kernel.md).
* AOSP VirtMgr, [GDB-port extraction and authorization](https://android.googlesource.com/platform/packages/modules/Virtualization/+/5f8e75df64e6f6cb64b7e10930e98784327a20a4/android/virtmgr/src/aidl.rs#1499).
* AOSP VirtMgr, [crosvm configuration receives `gdb_port`](https://android.googlesource.com/platform/packages/modules/Virtualization/+/5f8e75df64e6f6cb64b7e10930e98784327a20a4/android/virtmgr/src/aidl.rs#643).
