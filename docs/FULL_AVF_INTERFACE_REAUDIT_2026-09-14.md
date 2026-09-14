# Full AVF / GenieZone interface re-audit — 2026-09-14

## Purpose and safety boundary

This was a fresh, read-only re-audit from the outside of the complete
application → AVF → crosvm → GenieZone stack after the July/August security
updates. It deliberately did **not** launch a VM, alter Android state, change
firmware, Windows media, BCD, or use undocumented Binder transaction codes.

The question was narrow: did the current stock device expose a missed local
interface that could observe guest execution after `ExitBootServices()`?

## Device and artefact identity

```text
device:                 SM-X736B
build:                  X736BXXS8BZH4_OXM8BZH4
security patch:         2026-08-05
hypervisor:             GenieZone
ro.debuggable:          0
SELinux:                Enforcing
framework jar SHA-256:  8635B9E08B233EC977CDAB9A80707AFB4BEC361C86CAF6A7FA3E928B6F6DD322
```

The framework jar is byte-identical to the pre-OTA capture. `VmTerminalApp`
has a different whole-APK SHA-256, but its executable/resource payloads are
identical to the retained pre-OTA copy:

```text
classes.dex:       163722F43C46738BDC1DA01486CCB3820F324F187BE9CE4D6AF96B168A38D51A
resources.arsc:    7BED6C9E07EA577373117D4431FC0AD0D273A52C38A372A36DC133CC03BB4DC6
AndroidManifest:   60BA4BBB447CE8F5FF656AAEB6BA3D3655711EC2708F9251000F444AA058706C
```

Thus the Terminal APK's changed container/signing metadata is not evidence of
a new program-level console, debugger, or VM-control path.

## Re-audited interfaces

| Surface | What is actually available | Post-EBS observer result |
|---|---|---|
| WinAVF public/app VM API | VM lifecycle, serial TX/RX; existing byte-exact COM1 transport | Transport only. There is still no public `gdbPort`/PC/register/exits API for custom raw VM config. |
| `vm run` / `vm run-app` as `adb shell` | CLI advertises `--console`, `--console-in`, `--gdb`, DT dump; `run-app` accepts payload APK/Microdroid style configuration | `custom_vm`, `console_input`, and `paravirtualized_devices` are all disabled to shell. Earlier raw-Windows `--gdb` was rejected before VM creation. `run-app` does not describe this product raw Windows topology. |
| AVF Binder services | `android.system.virtualizationservice` appears in service list | `dumpsys` does not resolve it for shell; no `cmd` schema is registered. The app cannot find the internal Binder. No transaction guessing was performed. |
| Terminal / VmLauncher | Privileged APEX app, with `MANAGE_VIRTUAL_MACHINE` and `USE_CUSTOM_VIRTUAL_MACHINE` | Its static payload is unchanged; its private service/display route is not exported to WinAVF. Privileged app permissions cannot be delegated to an ordinary APK. |
| crosvm guest GDB | `vm run --help` still advertises `--gdb` | No product `gdbPort` configuration exists; Samsung VirtMgr rejects shell raw-VM GDB. No new product GDB path appeared. |
| tracefs `kvm`, `geniezone`, `vmm` | The kernel compiles many useful event names, including `kvm_entry`, `kvm_exit`, timer/vGIC and `mtk_vcpu_exit` | Shell cannot read/enable group controls, formats or filters. Earlier bounded captures produced no usable guest packets. Names alone are not an endpoint. |
| `/dev/gzvm` | Node exists, DAC mode `0666`, SELinux type `gzvm_device` | Even a zero-byte shell open is denied by SELinux before any ioctl. No VM/vCPU/RAM/IRQ handle is available to app or shell. |
| Samsung `ISehHyPer` HAL | Read-only dump is available | It exposes QoS/request data only: no guest identity, register, PC, exit, IRQ, timer or trace control. |
| `/dev/vsock`, `/dev/vhost-vsock`, `/dev/uhid` | Host device nodes exist | They can support future guest communication/input only after guest cooperation. They do not reveal the current Windows CPU state. |

## Result

```text
POST_OTA_NEW_DEBUG_INTERFACE           = NOT_OBSERVED
TERMINAL_PRIVILEGE_ESCALATION_PATH     = NOT_EXPOSED
PRODUCT_CROSVM_GDB_CONFIGURATION       = NOT_EXPOSED
SHELL_GUEST_STATE_OBSERVER             = BLOCKED
DIRECT_POST_EBS_WINDOWS_OBSERVABILITY  = BLOCKED
```

This is a statement about the documented and safely inspectable surface of
this exact stock build, not a claim that no private vendor interface exists.
The private interfaces are precisely the interfaces that Samsung/MediaTek must
expose or use to investigate the submitted GenieZone timer report.

## What remains productive locally

1. **Product work:** use the already-working pre-EBS GOP/WAVF display path,
   lifecycle UI, media builders and diagnostics. `/dev/uhid`/the app's input
   APIs are a possible future input branch, but require a guest virtio-input
   witness/driver and do not diagnose the Windows post-EBS halt.
2. **Regression detection:** after every OTA, run
   `tools/ota-regression/audit-avf-after-ota.ps1`. A changed framework API,
   a real product GDB field, a usable trace permission, or an accessible GZVM
   debug UAPI would justify reopening diagnosis.
3. **Vendor-assisted diagnosis:** the requested diagnostic-only GZVM trace,
   register/exit trace, or non-protected custom-VM GDB setting is the shortest
   path to a concrete Windows PC/exception state.

No new Windows runtime is justified by this audit alone.
