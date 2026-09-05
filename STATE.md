# WinAVF state — 2026-09-05

## Preserved boot milestones

- `EXIT_BOOT_SERVICES_RETURN = PASS`
- `MODIFIED_WIM_EBS = PASS`
- `MODIFIED_WIM_TRANSPORT = PASS`
- Immutable runtime baseline SHA-256: `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

The graphics audit made no firmware, BCD, FAT, WIM, Windows-media, or runtime-image change.

## Native AVF scanout audit

**Result: `NATIVE_AVF_SCANOUT = BLOCKED_BY_SPECIFIC_PERMISSION`.**

Android 16 Terminal implements an actual native path:

```text
Terminal DisplayActivity / SurfaceView
  -> IVirtualizationServiceInternal.waitDisplayService()
  -> ICrosvmAndroidDisplayService.setSurface(surface, isCursor)
  -> crosvm Android display backend -> SurfaceFlinger
```

The cursor uses a second `SurfaceView`, `setCursorStream()`, and a `SurfaceControl.Transaction` overlay. This is not VNC or RDP. AOSP passes crosvm `--android-display-service=<config.name>` when `DisplayConfig` is present.

### Device evidence

Fingerprint:

```text
samsung/gts11xx/gts11:16/BP4A.251205.006/X736BXXS6BZF4_OXM6BZF4:user/release-keys
```

- The privileged APEX Terminal is installed at `/apex/com.android.virt/priv-app/VmTerminalApp@BP4A.251205.006/VmTerminalApp.apk` (version 16).
- Its APK contains `ICrosvmAndroidDisplayService`, `IVirtualizationServiceInternal.waitDisplayService`, `setSurface`, `removeSurface`, and `setCursorStream`.
- Terminal is platform-signed/privileged, has hidden-API policy `0`, and declares `usesNonSdkApi=true`.
- The device registers `android.system.virtualizationservice`; its daemon label is `u:r:virtualizationservice:s0`.
- `crosvm` is present in `/apex/com.android.virt/bin/crosvm`, but an enforcing-SELinux shell cannot read its metadata or strings. Feature strings are therefore not claimed from this binary.
- Terminal's `VmLauncherService` configures `gfxstream`, `gfxstream-vulkan`, and `gfxstream-composer` for its graphical path. This proves Terminal expects the platform graphics backend, not every crosvm compile flag.

### Exact custom-app blocker

`com.example.winavf` has both AVF permissions granted:

```text
MANAGE_VIRTUAL_MACHINE = granted
USE_CUSTOM_VIRTUAL_MACHINE = granted
```

It nevertheless runs as `u:r:untrusted_app:s0:...`. Its opt-in read-only audit produced:

```text
BINDER android.system.virtualizationservice=NULL
CLASS ...IVirtualizationServiceInternal=UNAVAILABLE:ClassNotFoundException
CLASS ...ICrosvmAndroidDisplayService=UNAVAILABLE:ClassNotFoundException
```

The service is listed, but `service check android.system.virtualizationservice` from the shell returns `not found`. This is service-manager access control, not an absent daemon. In AOSP, the service has type `virtualization_service`; `virtualizationservice_use(domain)` grants its `service_manager find` and Binder calls. `untrusted_app` receives no such rule, and the service is not `app_api_service`.

Thus the ordinary AVF permissions allow the existing custom VM through the public manager path, but not the private Binder which hands a `Surface` to crosvm. Shipping generated AIDL stubs cannot fix blocked service discovery. The required change is an OEM/platform-signed bridge or a new public, permission-protected per-VM surface API; either is outside the no-root/no-system-change scope.

## Graphics architecture decision

**Selected research result: `EARLY_WINDOWS_DISPLAY_RELAY = VIABLE`.** This
means viable as an architecture for a separately signed, automatically
serviced user-supplied WinPE image; it is not yet a runtime pass.

### Current GOP framebuffer

The active `ArmVirtKvmTool` source explicitly includes `VirtioGpuDxe`. Its
existing local GOP adaptation creates a virtio-gpu 2D resource, allocates its
BGRA backing pages as `EfiReservedMemoryType`, exposes those pages through
`GopMode.FrameBufferBase`, uses
`PixelBlueGreenRedReserved8BitPerColor`, and leaves the virtio device running
from its ExitBootServices callback. The pages are guest RAM; crosvm consumes
them through `RESOURCE_ATTACH_BACKING`, `TRANSFER_TO_HOST_2D`, and `FLUSH`.

This is a valid *guest-side* physical-LFB handoff candidate for Windows Basic
Display. It is not a handle exported to WinAVF. Blob/dma-buf/AHardwareBuffer
exports stay inside crosvm/gfxstream and its Android display backend; the
ordinary app receives neither an FD nor a resource ID. Therefore:

- `HOST_VISIBLE_PERSISTENT_FRAMEBUFFER = BLOCKED_BY_SPECIFIC_PERMISSION`
- `CONTINUOUS_FIRMWARE_TO_WINDOWS_DISPLAY = NOT_YET_PROVEN`

### Rejected short paths

- `SERVICE_VCPU_DISPLAY_RELAY = NOT_A_SHORT_PATH`: AVF exposes only one CPU or
  match-host topology, and Arm crosvm powers off non-boot vCPUs initially. A
  resident CPU would require PSCI bring-up, memory/device exclusion from
  Windows ACPI, independent vsock transport, and cache/device ownership rules.
  It would also not cause Windows to keep using the GOP buffer.
- `POST_EBS_RESIDENT_FIRMWARE_RELAY = NOT_VIABLE`: UEFI runtime code has no
  autonomous scheduler after EBS. Boot-service events/timers are terminated;
  runtime code runs only when Windows invokes a Runtime Service. Baseline also
  established `SetVirtualAddressMap = NOT_CALLED`.

### Product path

The ordinary app can create its own Android `Surface` and has public VM-vsock
APIs, while the Windows virtio driver project ships ARM64 `viogpudo` (a WDDM
display-only driver) and `viosock` packages. WinPE accepts offline driver
packages and runs PnP during its boot. The feasible product shape is therefore
an automatically serviced boot.wim containing a production-signed ARM64
display-only relay plus a vsock producer; WinAVF renders the received dirty
BGRA tiles to its own Surface. It does not depend on the privileged Android
display broker and can become visible during Setup.

Before altering any WIM, the next PoC is an **offline-only** driver-package
preflight: verify a production-signed ARM64 `viogpudo`/`viosock` package and
that its INF matches the already observed `PCI\\VEN_1AF4&DEV_1050` GPU. If it
passes, make one cloned-media PnP acceptance test. No firmware, BCD, FAT, or
baseline image change is authorized by this research result.

## Repository support

`android-app/src/com/example/winavf/MainActivity.java` has an opt-in read-only `display_host_audit` intent/UI action. It creates no VM, waits for no service, and submits no Surface. It records the calling UID, permission grants, service lookup result, and internal class visibility.

## Sources and local evidence

- AOSP Terminal `DisplayProvider.kt`, commit `aa6989ebf936cc865a156de2fb0591500ed6d242`.
- AOSP Virtualization change introducing `DisplayConfig` and `--android-display-service`, commit `ef450795e2acb4e89369680f68f75415bf437427`.
- AOSP Android 16 QPR2 `service_contexts`, `service.te`, and `te_macros` (`virtualizationservice_use`).
- Non-redistributed local Terminal APK: `%LOCALAPPDATA%\Temp\winavf-display-audit\VmTerminalApp.apk`, SHA-256 `CD101C3545CE936ACD01EF36BBA8E0CFFD3D40203E8ADB6E1BD12BD3BA25623E`.
- Read-only custom-app report: `%LOCALAPPDATA%\Temp\winavf-display-audit\native-avf-display-access-audit.txt`.

No APK, Windows image, ISO, WIM, or other proprietary binary is tracked here.

## Pre-OTA snapshot

Read-only device evidence was captured before the pending Samsung reboot. See
`docs/DEVICE_PRE_OTA_SNAPSHOT_2026-09-05.md`. No OTA, system, APEX, firmware,
Windows-media, or VM state was modified.
