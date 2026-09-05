# Graphics architecture research: firmware through Windows Setup

## Decision

`EARLY_WINDOWS_DISPLAY_RELAY = VIABLE` is the only viable product route under
the no-root/no-OEM-bridge constraints. It is **not** yet a runtime milestone.
The immediate next PoC is deliberately offline-only: validate a
production-signed ARM64 `viogpudo` and `viosock` package against the observed
virtio-GPU PCI ID. No Windows image has been changed by this research.

| Architecture | Result | Exact reason |
| --- | --- | --- |
| A. Host-visible persistent GOP resource | Blocked | The resource can persist in guest/crosvm, but Android exposes no ordinary-app resource FD/handle; Android display-service access is privileged-only. |
| B. Hidden service vCPU | Not a short viable path | Requires a non-public CPU arrangement plus PSCI, ACPI, memory/device ownership, vsock, and cache-coherency work; it cannot make Windows continue to render to GOP. |
| C. Runtime-resident firmware relay | Not viable | EBS ends Boot Services/timers; UEFI Runtime Services provide calls, not a scheduler or post-EBS worker context. |
| D. WinPE-side relay | Viable | Windows supports offline driver injection/PnP in WinPE; public AVF vsock reaches the app; ARM64 virtio display-only and vsock driver sources/packages exist. |

## What the current GOP actually is

This is based on the present full, untracked ArmVirtKvmTool source tree used
for the local firmware builds, not an assumption about generic QEMU.

`ArmVirtKvmTool.dsc` and `.fdf` both include `OvmfPkg/VirtioGpuDxe`. Local
adaptations in `OvmfPkg/VirtioGpuDxe` do the following:

1. Create an XRGB/BGRA virtio-GPU 2D resource.
2. Allocate the backing pixels in guest RAM as `EfiReservedMemoryType`.
3. DMA-map those pages for virtio and attach them to the resource.
4. Set `EFI_GRAPHICS_OUTPUT_PROTOCOL.Mode.FrameBufferBase` and size, using
   `PixelBlueGreenRedReserved8BitPerColor`.
5. Copy GOP writes into that backing store, then issue
   `TRANSFER_TO_HOST_2D` and `RESOURCE_FLUSH`.
6. Deliberately do **not** reset the virtio-GPU in the EBS callback.

Thus the pixels initially live in guest RAM, not in an Android-owned surface.
The host resource is an internal crosvm/gfxstream representation of those
pages. `EfiReservedMemoryType` means Windows should not reallocate the range,
and `FrameBufferBase` makes it eligible for BasicDisplay's GOP handoff. This
is a much stronger Windows handoff than stock `PixelBltOnly` GOP.

It does **not** prove continuity at runtime yet: Windows must still accept the
exact GOP mode and later chooses whether a PnP graphics driver supersedes it.
The existing serial evidence proves GPU enumeration (`1AF4:1050`) and EBS, not
that Windows drew a frame from the reported LFB.

## Why virtio blobs do not solve host visibility

The virtio-GPU protocol supports guest-issued `RESOURCE_CREATE_BLOB` and
`RESOURCE_MAP`; crosvm/gfxstream can internally export resources as dma-buf or
shared-memory descriptors. That is a **guest-to-crosvm backend** mechanism.
It is not an Android framework API that returns a descriptor to the VM owner.

The Android crosvm display backend accepts an opaque service name, creates an
Android display context, and imports `AHardwareBuffer` FDs into that context.
It obtains its target Surface from the private Terminal/VirtualizationService
path. WinAVF has neither that Binder service nor a framework method returning
the corresponding FD. Resource blobs therefore cannot bypass
`NATIVE_AVF_SCANOUT = BLOCKED_BY_SPECIFIC_PERMISSION`.

## EBS, vCPU and runtime feasibility

The current GOP's EBS callback preserving the device is useful: it preserves
the physical LFB candidate for Windows. It is not an execution loop. UEFI
states that after successful EBS, the OS owns continued platform operation;
only Runtime Services remain. A normal Boot Services timer/event is not a
post-EBS worker. The known baseline additionally never invokes
`SetVirtualAddressMap`.

AVF's exposed topology options are only `ONE_CPU` and `MATCH_HOST`. AArch64
crosvm configures non-boot vCPUs powered off. Building an invisible relay CPU
would therefore require firmware-controlled PSCI startup and deliberately
inconsistent host/firmware/Windows CPU inventory. It would also need a private
RAM reservation, an unenumerated transport device, locking and cache policy.
That is a new platform subsystem, not a bounded display PoC. It is excluded.

## Windows Setup path

Windows BasicDisplay can inherit a linear GOP framebuffer; Microsoft describes
it as the early-Setup fallback. That makes the current GOP change worthwhile,
but host visibility still needs a producer that WinAVF may receive.

The smallest Windows path is a *display-only* rather than full 3D WDDM
implementation:

```text
WinPE PnP
  -> signed ARM64 virtio-GPU display-only driver (or compatible derivative)
  -> primary BGRA surface / dirty rectangles
  -> signed ARM64 vsock relay
  -> VirtualMachine.connectVsock() in WinAVF
  -> app-owned double-buffered Surface renderer
```

The upstream virtio-win project lists ARM64 `viogpudo` and `viosock` artifacts
for Windows 10 and Windows 11. Microsoft documents that WinPE supports offline
INF driver injection and PnP association at boot. This means graphics can
appear before Windows installation completes. A test-signed kernel component
would require explicit test-signing changes and is not a product path;
production media requires a production-signed package.

## Transport target

At 1280x720 BGRA8888, a full frame is 3,686,400 bytes (3.52 MiB): 30 FPS raw
would be about 105.5 MiB/s, 60 FPS about 210.9 MiB/s. The first protocol should
use 64x64 tiles (20 x 12 = 240 tiles), a sequence number, dirty tile bitmap,
LZ4, two app-side buffers, bounded queue depth, and permission to drop old
frames. Setup is mostly static, so changed tiles are expected to be far below
the raw ceiling. This protocol is reusable by a later Windows agent, but that
later agent is explicitly out of scope for the first Setup PoC.

## Minimal next PoC

1. Obtain a **production-signed**, redistributable ARM64 package; do not build
or inject a test-signed driver.
2. Offline verify its catalog/signature and that the GPU INF binds
   `PCI\\VEN_1AF4&DEV_1050`; separately verify the vsock package.
3. Only if that preflight passes, make a new clone of the user-provided
   installer and inject the two packages into boot.wim index 2 using the
   existing reversible WIM pipeline.
4. First runtime assertion is PnP acceptance / driver start, not performance.
   Keep firmware, BCD, FAT layout and the known-good media baseline unchanged.

No proprietary Windows media, WIM, ISO, or driver binary belongs in this
repository. Product automation may service a user-provided ISO locally.

## Primary sources

- [Current crosvm Android display backend](https://chromium.googlesource.com/crosvm/crosvm/+/927fd7d5631d1c0cdbadfb54c9a8f2bc17d994f2/gpu_display/src/gpu_display_android.rs)
- [crosvm GPU backend selection and external blobs](https://chromium.googlesource.com/crosvm/crosvm/+/c6e1e1a885cbce5c25e2bbaba3e8cdcdc992952c/src/crosvm/sys/linux/gpu.rs)
- [virtio-GPU blob and map definitions](https://android.googlesource.com/kernel/common/+/3b3807ea9f42a0e99c2a27eb555a2648915b6aa0/include/uapi/linux/virtio_gpu.h)
- [Windows Basic Display and GOP handoff](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/microsoft-basic-display-driver)
- [Windows Arm GOP framebuffer requirements](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/uefi-requirements-that-apply-to-all-windows-platforms)
- [WinPE offline driver injection](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-and-remove-drivers-to-an-offline-windows-image)
- [ARM64 virtio GPU and vsock package contents](https://github.com/virtio-win/kvm-guest-drivers-windows/blob/master/win10_arm64.ddf)
