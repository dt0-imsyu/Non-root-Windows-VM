# August 2026 OTA — AVF surface audit

## Scope

Read-only inspection after the device moved from the prior `BZF4` build to the
Samsung August 2026 security build. No VM, Windows media, firmware, BCD,
hidden-API setting, or Android system state was changed.

## Observed build

```text
model:                  SM-X736B
fingerprint:            samsung/gts11xx/gts11:16/BP4A.251205.006/X736BXXS8BZH4_OXM8BZH4:user/release-keys
incremental:            X736BXXS8BZH4
security patch:         2026-08-05
verified boot:          green
ro.debuggable:          0
hypervisor:             GenieZone
```

## AVF delta verdict

```text
AVF_FRAMEWORK_JAR_DELTA             = NONE
TERMINAL_PRIVILEGED_API_DELTA        = NOT_OBSERVED
PUBLIC_PRODUCT_GDB_CONFIGURATION    = NOT_EXPOSED
OTA_NEW_POST_EBS_OBSERVER            = NOT_OBSERVED
```

The installed framework jar remains exactly:

```text
8635B9E08B233EC977CDAB9A80707AFB4BEC361C86CAF6A7FA3E928B6F6DD322
```

This is the same SHA-256 captured before the security updates. The Terminal
package remains version 16 at the same APEX path. `vm run --help` still lists
`--gdb`, but the public product `VirtualMachineConfig` conversion still has no
`gdbPort` field and the feature gates still report custom VM, console input and
paravirtualized devices disabled to shell. This does not remove app-level
evidence for the existing product VM; it means the OTA did not expose a new
supported VMM observer.

## UEFI mouse/touch decision

The Android-side mouse/touch API remains a potential host transport, but it is
not yet a valid UEFI input runtime test. The current ArmVirtKvmTool FDF/DSC has
no VirtioInput driver binding that produces `EFI_SIMPLE_POINTER_PROTOCOL` or
`EFI_ABSOLUTE_POINTER_PROTOCOL` for the crosvm virtio-input device. A host
event without a guest driver would yield an ambiguous absence of movement.

Do not run a Windows baseline merely to test mouse/touch. A future UEFI input
experiment needs a small, independently built pointer-driver/probe path or a
Linux guest input witness; that is separate product work and does not help the
current Windows post-EBS boundary.

## Reusable OTA audit

Run this read-only tool after any future Samsung update before considering a
runtime test:

```powershell
cd C:\path\to\Non-root-Windows-VM
.\tools\ota-regression\audit-avf-after-ota.ps1
```

Compare its report against this document. Only a changed AVF/Terminal hash,
new public configuration field, or new debug/trace feature justifies a fresh
post-EBS investigation.
