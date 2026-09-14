# AVF / GenieZone handle-ownership audit — 2026-09-14

## Result

```text
GZVM_VM_HANDLE_ACCESS   = AVAILABLE_ONLY_INSIDE_CROSVM
GZVM_VCPU_HANDLE_ACCESS = AVAILABLE_ONLY_INSIDE_CROSVM
GUEST_RAM_ACCESS        = DISK_FDS_ONLY / NO_GUEST_RAM_MAPPING
MMIO_EXIT_ACCESS        = NOT_EXPOSED
IRQ_INJECTION_ACCESS    = NOT_EXPOSED
```

## Ownership model

```text
WinAVF app
  | Binder: IVirtualMachine + approved disk / console / vsock FDs
  v
VirtualizationService / virtmgr (system domain)
  | builds crosvm command and retains control/configuration FDs
  v
crosvm (private VMM process; GenieZone backend owner)
  | VM/vCPU lifecycle, guest RAM, exits and IRQ state
  v
GenieZone EL2
```

The app VM Binder represents lifecycle and approved data channels, not a
transferable VMM handle. `VirtualMachineDescriptor` persists configuration,
instance and encrypted-store files for stopped VMs, not vCPU state, guest RAM,
MMIO exits, or IRQ interfaces.

## Evidence and limits

* Runtime: `/dev/gzvm` exists but is labelled `gzvm_device`; shell opens are
  denied by SELinux before any ioctl. `/dev/kvm` is absent.
* Runtime: the app is non-debuggable, so direct app-domain `/dev/gzvm` probing
  is intentionally not performed; no public Android API returns this FD.
* Matching virtmgr source: `run_vm()` starts crosvm with preserved FDs and a
  private seqpacket control listener. The listener is not an IVirtualMachine
  result.
* Upstream-compatible GZVM UAPI describes create/run and some one-register
  operations, but GET_ONE_REG returns `-EOPNOTSUPP` in the reviewed driver.
  Public UAPI availability is not app availability.

## Minimum accelerator contract versus current access

| Needed by a QEMU accelerator | Current result | Reason |
|---|---|---|
| `gzvm_init/open` | VENDOR_PRIVILEGED | app gets no `/dev/gzvm` FD and no owner-service API |
| create VM / map memory | AVAILABLE_ONLY_INSIDE_CROSVM | AVF lifecycle API has no raw VM abstraction |
| create / initialise vCPU | AVAILABLE_ONLY_INSIDE_CROSVM | no vCPU FD/API transfer |
| get/set architectural registers | VENDOR_PRIVILEGED / incomplete UAPI | no app access; public GET is unsupported |
| run vCPU and obtain exits | AVAILABLE_ONLY_INSIDE_CROSVM | no exit stream or product GDB endpoint |
| MMIO emulation | NOT EXPOSED | no delegated userspace-MMIO channel |
| inject IRQ | NOT EXPOSED | no GIC/vCPU interrupt API |
| inspect guest RAM | NOT EXPOSED | image files are not guest-RAM mappings |
| pass device-backend FD | LIMITED | console and possibly RawConfig input/fs only |

The exact Samsung crosvm implementation cannot be dumped from shell due to
SELinux. This does not alter the conclusion: whether crosvm opens GZVM itself
or receives a prepared resource, the owner is a system-launched private process
and no handle reaches the app.

## Implication

An application cannot legally attach QEMU to the already-running AVF VM, nor
replace crosvm CPU execution while retaining it through a public handle. A
vendor/system-service API or modified VMM would be required and is outside the
stock no-root constraints.
