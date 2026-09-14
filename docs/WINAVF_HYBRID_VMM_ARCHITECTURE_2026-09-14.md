# WinAVF hybrid-VMM architecture decision — 2026-09-14

## Decision

```text
PRIMARY_ARCHITECTURE_CANDIDATE   = A: crosvm + GenieZone + verified AVF surfaces
SECONDARY_ARCHITECTURE_CANDIDATE = B: crosvm + virtio-fs helper only
FALLBACK                         = historical QEMU TCG reference
BLOCKED                          = C/D/E on a stock Samsung device
```

The deciding fact is ownership: crosvm is the private GenieZone VM owner and
AVF exposes no VM/vCPU/RAM/exits/IRQ interface to the app. QEMU cannot become
an accelerator client, and crosvm cannot act as a generic machine-model broker.

```text
Current viable product plane

Android app -- Binder/config --> VirtualizationService --> crosvm --> GenieZone
     |                                  |                    |
     +-- console / vsock / disk FDs -----+                    +-- virtual CPU/RAM/GIC
     +-- mouse/touch candidate ----------> virtio-input (unproven runtime)
     +-- GOP WAVF decoder <--------------- ttyS0 console (proven pre-EBS)

Not available to the app: VM FD, vCPU FD, guest RAM, MMIO exits, IRQ injection,
control socket, generic vhost-user devices, native Android display service.
```

## Comparative engineering matrix

Scores are comparative 0–5, not a promise of implementation. Complexity 5
means easiest.

| Architecture | Stock/no-root | Perf. | Windows contract | Preboot input | Graphics | Ease | Reuse | Evidence-based assessment |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| A. crosvm + GenieZone + platform fixes | 5 | 5 | 2 | 2 | 2 | 4 | 5 | Only VM execution path proven on the product; no CPU masking or VMM repair control. |
| B. crosvm + external/vhost-user devices | 2 | 4 | 2 | 2 | 2 | 2 | 3 | Only virtio-fs is source-mapped; generic GPU/HID/block/net/vsock selection absent. |
| C. QEMU machine/devices + crosvm broker | 0 | 3 | 5 | 5 | 4 | 1 | 3 | crosvm exports neither RAM nor exits/MMIO/IRQ delegation. |
| D. QEMU + native GZVM accelerator | 0 | 5 | 5 | 5 | 4 | 1 | 4 | QEMU/KVM structure is useful, but app cannot open or receive GZVM VM/vCPU handles. |
| E. custom WinAVF VMM + GenieZone | 0 | 5 | 5 | 5 | 5 | 0 | 2 | Same missing handle boundary plus an ARM machine/GIC/PCI/virtio project. |

### A. Keep crosvm / GenieZone

This is the product candidate because it is the only route with hardware
execution and an authorised Android API. Near-term safe work is limited to
proven console/GOP and a disposable touch/mouse hardware-input proof. It cannot
locally repair the Windows early blocker: public AVF has no CPU-model mask and
no timer/GIC/vCPU controls.

### B. crosvm plus external service

Virtio-fs may be an app data/control helper, not a replacement device model.
It cannot establish early Windows graphics, generic HID, or a QEMU machine
contract. vhost-user GPU/HID claims remain blocked until Samsung exposes a
RawConfig selector and an app-connectable socket.

### C/D/E. Why the QEMU routes are not local projects

A QEMU device model needs guest RAM mapping, MMIO exits and IRQ injection.
AVF's control socket stays inside virtmgr/crosvm and no app-visible delegated
device protocol exists. A native QEMU accelerator would additionally need VM
creation, memory slots, vCPU run/exit decoding, register access, vGIC/IRQ
semantics and timer ownership. That is a vendor collaboration, not an
application change. A custom VMM has the same blocker and must not copy GPL
QEMU code into an incompatible project; permissive rust-vmm components and
virtio specifications are separate options if the ownership barrier disappears.

## Security and compatibility

None of A–B prevents ordinary future Secure Boot, TCG2 measured boot, or a
persistent TPM 2.0/vTPM once a permitted backend exists. No anti-cheat bypass
is proposed. Windows-on-ARM handles x86/x64 user-mode translation itself; the
VMM need execute ARM64 guest code only. x64 kernel drivers remain outside that
assumption.

## Current Windows conclusion

```text
WINDOWS_CURRENT_BLOCKER = UNRESOLVED_EARLY_WINDOWS_VS_HOST_DERIVED_CPU_PLATFORM_CONTRACT
```

P7 confirms a real CPU-profile difference, but no bit is causally tied to the
silent Windows point. The physical PPI30 defect remains a separate confirmed
GenieZone issue and is not the direct path of the exact WinPE kernel, which
uses `CNTV_*`.

## Next highest-information action

Run no further Windows debug boot. First perform a **diskless QEMU contract
capture** under the preserved successful QEMU machine line: record ID registers,
ACPI tables, EFI memory map, PSCI conduit, GIC/GTDT and UART. Compare those
records with P7/product artifacts. Only a mismatch that Windows consumes before
WinPE and that a real owner can safely alter earns a product A/B.

If product interactivity is the priority, the distinct safe test is a disposable
Linux guest with `useTouch/useMouse`; it must not be mistaken for a Windows
early-boot fix.
