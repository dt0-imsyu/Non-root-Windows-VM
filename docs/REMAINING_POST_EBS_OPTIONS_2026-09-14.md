# Remaining paths after the post-EBS audit

## Verdict

```text
LOCAL_NO_ROOT_WINDOWS_POST_EBS_ROOT_CAUSE_PATH = EXHAUSTED
PRODUCT_DEVELOPMENT_PATH                       = ACTIVE
```

This is not a claim that Windows cannot run on the device. It means that the
remaining unknown is inside a layer that the stock public AVF contract does
not expose to an app: product crosvm, GenieZone EL2, or a Windows execution
state for which there is no accepted guest observer.

## Closed local branches

| Branch | Why it is closed |
|---|---|
| Another BCD/KDCOM/KD timing variation | Product COM1 is byte-exact, but the controlled serial-KD runs and BCD phase audit produced no handshake. No new supported transport exists. |
| Product crosvm GDB | RawConfig has no `gdbPort` field/setter; Samsung VirtMgr rejects shell GDB use before VM creation. |
| KVM/GenieZone Perfetto/ftrace | Relevant events are protected or emitted zero packets despite active vCPU time; repeated captures cannot add guest PC/exit state. |
| Public `/dev/gzvm` UAPI | SELinux blocks app/shell access before ioctl; VM/vCPU/RAM/exits/IRQ handles remain private to crosvm. |
| Windows media, startnet, BootExecute or driver probes | They execute later than the unknown handoff and their acceptance/CI/userland prerequisites make them non-diagnostic. |
| Random ACPI, PSCI, GIC, timer or CPU-mask changes | The QEMU↔AVF differential found no truthful firmware-only repair; the existing WinPE code uses CNTV, not the failed CNTP comparator. |
| QEMU as a replacement VMM over GenieZone | AVF gives the app no guest-RAM mapping, vCPU exits, MMIO emulation, or IRQ-injection interface. |

## Remaining high-value paths

### 1. Samsung firmware / GenieZone engineering escalation — highest priority

The submitted CNTP report is an independent, reproducible EL1 timer defect
with a minimal firmware-only reproducer. Ask Samsung to provide one of:

- a corrected physical-timer vCPU context implementation;
- a supported guest trace covering vCPU PC, exits, virtual IRQ/timer state and
  exceptions; or
- a debuggable custom-VM/GDB configuration path for a non-protected AVF VM.

This is the only route that can directly identify the Windows execution state
without weakening the security model. Track the Samsung Members report ID and
use [the submission kit](SAMSUNG_GENIEZONE_SUBMISSION_KIT_2026-09-14.md) for
follow-up.

### 2. Firmware/OTA regression control — high information when an update arrives

After a Samsung firmware update, repeat only the already validated small
controls before any Windows experiment:

1. verify device fingerprint and immutable baseline hash;
2. rerun the minimal P4/P5 physical-CVAL reproducer;
3. if its result changes, preserve the raw serial and notify Samsung;
4. only if the platform contract changed, run one baseline Windows control.

This is not a speculative workaround. It detects whether a vendor update
changed the known faulty EL2 timer behavior or opened a supported debug API.

### 3. A second device with public AVF — diagnostic control, not a repair

Run the same unmodified P1/P4 probe and one baseline Windows handoff on a
second recent Android device that supports custom, non-protected AVF VMs. A
pass there would isolate the issue to this Samsung/MediaTek integration; the
same failure would justify an AVF-level upstream discussion. This requires
separate hardware, so it is not an immediate local task.

### 4. Continue product work above the blocked boundary

The pre-EBS product path is independent and already valuable:

- event-driven UEFI GOP/WAVF rendering;
- Android launcher lifecycle, visible logs and safe launch/rollback UX;
- optional future AVF pointer/touch validation for UEFI;
- reproducible media/audit tooling and vendor evidence packaging.

Do not present post-EBS Windows graphics, input, vsock or Setup functionality
as available until `WINPE_USERLAND` is observed.

## Explicit non-options

Custom unsigned Windows kernel code, test-signing, patched Microsoft binaries,
root/SELinux bypasses, bootloader unlock, flashing, and private Binder or GZVM
handle extraction are outside the project constraints. They would change the
question from stock-platform compatibility to a modified-system experiment.

## Best next action

Wait for the Samsung report ID, then send the engineering escalation using the
full submission kit. In parallel, keep the product repository and pre-EBS UI
maintained. Do not schedule another product Windows runtime until Samsung
provides a trace/debug avenue or a platform update provides a new observable
fact.

## External references

- AOSP: [Write an AVF app](https://source.android.com/docs/core/virtualization/writeavfapp) documents the public app model (VM lifecycle plus approved channels such as vsock), not VMM-state ownership.
- AOSP: [Debugging guest kernels with gdb](https://android.googlesource.com/platform/packages/modules/Virtualization/+/refs/heads/main/docs/debug/gdb_kernel.md) documents the debuggable-VM GDB feature whose product configuration path is absent here.
- Microsoft: [KD transport extensibility](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/how-to-develop-kdnet-extensibility-modules) confirms that a custom early debug transport is a hardware-vendor integration project, not a safe media-only toggle.
