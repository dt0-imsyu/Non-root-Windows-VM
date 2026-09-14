# Windows kernel-entry forensic design — 2026-09-07

## Scope and fixed boundary

This is a read-only design pass.  It did not build firmware, stage a patch,
change Windows media/BCD, change Android code, or start a VM.

The current independently observed boundary is:

```text
ExitBootServices original return = PASS
POST_EBS_SERIAL_CAPTURE          = PASS
SetVirtualAddressMap             = NOT_OBSERVED
VirtualAddressChange             = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY             = UNKNOWN
```

`SetVirtualAddressMap = NOT_OBSERVED` is not evidence against kernel entry. It
only excludes that particular UEFI Runtime Service call in the r9 observation
window.

## Static facts

The retained `diagnostics/winload-inspect/winload.efi` is SHA-256
`F7747F4AC18CCD66EBF6A043D979CF30C7731114C27C33FF2FC3C0610F491D31`.
It is a `coff-arm64` Boot Application (PE subsystem `0x10`), has image base
`0x180000000`, entry RVA `0x5fa0`, and imports `winload.sys`.

Its retained metadata includes `winload_prod.pdb`, `BlArchKernelSetup`, boot
debug setup/transition exports, and boot-status logging exports. These facts
confirm that the Microsoft loader owns the loader-to-kernel transfer and its
native debug machinery; they do not expose a firmware callback at that point.

The existing EDK2 `AuditStartImage()` wrapper logs immediately before and after
the original `StartImage()` call. For `winload.efi`, the pre-call marker proves
only loader entry. A normal Windows loader does not return to that wrapper at
kernel handoff, so firmware cannot distinguish `winload running` from
`ntoskrnl entered` through that hook.

## Candidate observers

| Candidate | What it could prove | Constraint/result |
|---|---|---|
| Microsoft boot-debug / KD | Kernel debugger initialization and a breakpoint/stack after transfer; this is the only stock signed path capable of direct kernel observation. | Requires a minimal reversible BCD debug setting and genuinely bidirectional COM1 transport. Current public AVF supplies raw output only, so this is **BLOCKED**. |
| VMM PC tracing / hardware breakpoint | A crosvm/KVM-side trap at the resolved `ntoskrnl` entry would prove transfer without changing Windows or CI. | An untrusted APK has no vCPU-register, KVM debug, or crosvm tracing interface. It requires a platform/crosvm change and is not a firmware-only test: **BLOCKED**. |
| Existing EDK2 `StartImage` audit | `winload.efi` was invoked. | Already available, but cannot prove its transfer to the kernel: **REJECTED** as a kernel-entry observer. |
| Boot status data / bootlog / EMS | Later loader or kernel bookkeeping. | Not an exact entry marker; depends on BCD and/or later persistent storage/serial behavior: **REJECTED**. |
| Patching `winload.efi`/`ntoskrnl.exe`, or a custom driver | An arbitrary exact marker. | Violates Microsoft binary integrity or current CI constraints: **REJECTED**. |

## Decision

```text
WINDOWS_KERNEL_ENTRY_OBSERVER = BLOCKED
```

There is no valid one-runtime firmware-only A/B under the present constraints.
Repeating r9, extending RuntimeDxe, changing WIM, or adding a custom driver
would not answer the kernel-entry question.

## One next experiment if authority changes

The smallest informative experiment is a one-run, reversible Microsoft KD
test, but only after a documented binary-transparent inbound COM1 endpoint is
made available. It would use the existing Microsoft-signed boot/debug
components, apply the minimal BCD debugger setting to the Windows loader
object, capture the KD handshake, then roll the BCD/media back exactly. It
does not require test-signing, modifying Microsoft binaries, a custom driver,
or a firmware rewrite.
