# Earliest signed post-EBS milestone — read-only research

Date: 2026-09-07  
Scope: static source, INF, package and public-AVF API audit only. No firmware,
WIM, BCD, Android application, driver, media or VM change was made.

## Question

Find the earliest Windows component after the proven `ExitBootServices` return
which is already production-signed and can emit an unambiguous, host-visible
effect without custom kernel code, CI/test-signing changes, bidirectional KD,
or WinPE user mode.

## Fixed boundary

```text
winload.efi invoked                     = PASS
original ExitBootServices() returned OK = PASS (raw BES)
SetVirtualAddressMap                    = NOT_OBSERVED
Windows kernel entry                    = UNKNOWN
WinPE user mode                         = NOT_CONFIRMED
```

The r9 raw UART result does not prove or disprove kernel entry. The separate
direct-kernel-entry observer design is blocked because public AVF has no
bidirectional COM1 endpoint and an untrusted APK has no crosvm/KVM PC trace.
See `WINDOWS_KERNEL_ENTRY_FORENSIC_DESIGN_2026-09-07.md`.

## Host observation actually available

The application has only these relevant public paths:

* raw, receive-only console output (`VirtualMachine.getConsoleOutput()`);
* a later `connectVsock()` client API, which is useful only when a guest
  listener exists;
* an ordinary writable disk-image file, for which the app can inspect file
  length/allocation after the VM has stopped.

It has no public guest block-I/O completion stream, virtio device lifecycle
event, virtio-GPU scanout/DMA-buf access, guest-RAM/VCPU trace, or writable
console stream. The configured `ttyS0` input setting is not an API returning a
guest-writable `OutputStream`.

Consequently, a signed driver's normal load, `DriverEntry`, PnP binding, or
ordinary block read has no automatic host-visible effect through this API.

## Ranked candidates

| Rank | Candidate and static evidence | Earliest possible phase | Available independent signal | Result |
| --- | --- | --- | --- | --- |
| 1 | `viostor.sys`: ARM64 INF matches `PCI\VEN_1AF4&DEV_1042`; `ServiceType=1`, `StartType=0` (boot start). | Boot-driver loading. | None. Its routine virtio-blk reads are not exposed as host I/O events; image allocation/mtime is not a per-request trace. | Rejected: earliest signed candidate but not observable. |
| 2 | Inbox boot stack (`acpi`, `pci`, `disk`, class stack) required before boot-volume access. | At or before boot-driver loading. | None through public AVF. | Rejected: no observable side effect. |
| 3 | `viosock.sys`: ARM64 INF matches `PCI\VEN_1AF4&DEV_1053`; kernel service is demand-start (`StartType=3`). | PnP, later than boot drivers. | A host connection requires a guest listener. The prior port-4050 attempt returned `No such device`, but this cannot distinguish no user mode, no PnP bind, or no listener. | Rejected: not early and user-mode dependent. |
| 4 | `viogpudo.sys`: ARM64 INF matches `PCI\VEN_1AF4&DEV_1050`; display/PnP demand-start. | PnP/display stack. | No public scanout or device-state callback. UART is unrelated to GPU binding. | Rejected: later and not observable. |
| 5 | `pvpanic.sys`: signed, but demand-start. | PnP, later than boot drivers. | A panic is deliberately destructive and would not establish normal load/start; no intended device is present for this test. | Rejected: unsafe fault injection, not a normal milestone. |
| 6 | Bootlog, Boot Status Data, EMS, crashdump/recovery bookkeeping. | Varies, generally later or error-only. | Requires BCD/debug transport, persistence later in boot, or gives ambiguous error state. | Rejected: violates constraints or cannot answer the stage question. |

The exact `viostor` static facts are present in
`windows-headless-media/stage/drivers/viostor/viostor.inf`: the `1042` hardware
ID is at line 53 and the kernel/boot-start service declaration is at lines
70--76. These facts prove eligibility, not an observable runtime event.

## Result

```text
EARLIEST_SIGNED_POST_EBS_MILESTONE = BLOCKED
```

No candidate satisfies all five required properties simultaneously:
production-signed, pre-user-mode, no signed-binary modification or CI bypass,
host-visible through the existing public interface, and diagnostic value in a
single run.

This is an observability limitation, not evidence that `viostor`, kernel entry,
or the Windows boot-driver stack failed.

## One next experiment if authority changes

Do not create a media candidate under the current constraints. The lowest-risk
new capability would be a documented read-only crosvm/AVF device-event or
block-I/O trace exposed to the app. It would make normal signed `viostor`
activity observable without changing Windows. If that cannot be exposed, the
next useful authority is a genuinely bidirectional COM1 endpoint for standard
KD; neither path is firmware-only.
