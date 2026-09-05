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

## Repository support

`android-app/src/com/example/winavf/MainActivity.java` has an opt-in read-only `display_host_audit` intent/UI action. It creates no VM, waits for no service, and submits no Surface. It records the calling UID, permission grants, service lookup result, and internal class visibility.

## Sources and local evidence

- AOSP Terminal `DisplayProvider.kt`, commit `aa6989ebf936cc865a156de2fb0591500ed6d242`.
- AOSP Virtualization change introducing `DisplayConfig` and `--android-display-service`, commit `ef450795e2acb4e89369680f68f75415bf437427`.
- AOSP Android 16 QPR2 `service_contexts`, `service.te`, and `te_macros` (`virtualizationservice_use`).
- Non-redistributed local Terminal APK: `%LOCALAPPDATA%\Temp\winavf-display-audit\VmTerminalApp.apk`, SHA-256 `CD101C3545CE936ACD01EF36BBA8E0CFFD3D40203E8ADB6E1BD12BD3BA25623E`.
- Read-only custom-app report: `%LOCALAPPDATA%\Temp\winavf-display-audit\native-avf-display-access-audit.txt`.

No APK, Windows image, ISO, WIM, or other proprietary binary is tracked here.

## Next cheapest experiment

Do not build the framebuffer/vsock fallback yet. If an OEM/platform-signed bridge or documented public AVF Surface API becomes available, rerun `display_host_audit` from that permitted identity. A non-null internal service Binder is the gate before a minimal `SurfaceView -> setSurface()` graphical-UEFI PoC.
