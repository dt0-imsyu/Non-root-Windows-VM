# Terminal / VmLauncher reverse engineering — 2026-09-05

## Result

`TERMINAL_DISPLAY_PATH = HARD_BLOCKED_BY_EXACT_PLATFORM_PRIVILEGE` for a
normal external application. The result is based on the installed Samsung
Terminal APK, its manifest/DEX, local AVF framework source, local crosvm source,
and the existing SELinux/service-manager audit.

`TERMINAL_DISPLAY_BRIDGE = NOT_REUSABLE_FOR_EXTERNAL_VM`: the bridge is a
private Binder path tied to the Terminal process and the current crosvm VM.

`TERMINAL_VM_HOST = NOT_REUSABLE_WITH_OUR_DISK_ISO_KERNEL`: the only launcher
entry point is a non-exported started service; it is not a bindable host API
and its implementation selects Terminal's private `InstalledImage` and config.

## Exact APK boundary

The installed artifact is `VmTerminalApp.apk`, package
`com.android.virtualization.terminal`, version `16`, platform/privileged
Terminal. The manifest declares `MANAGE_VIRTUAL_MACHINE` and
`USE_CUSTOM_VIRTUAL_MACHINE`, but these permissions do not grant the hidden
display Binder to an ordinary app.

Manifest facts from `aapt2 dump xmltree`:

- `MainActivity` is the only exported Terminal activity (`exported=true`) and
  has the launcher plus `android.virtualization.VM_TERMINAL` filter.
- `DisplayActivity` has no `exported` attribute and no intent filter, therefore
  it is not externally launchable under Android component defaults.
- `VmLauncherService` has `exported=false`.
- `InstallerActivity`/`InstallerService` are also `exported=false`.
- `VmLauncherService.onBind()` returns `null`; commands are private explicit
  intents (`ACTION_START_VM`, shutdown, unplug, serial query) carrying private
  `ResultReceiver`, notification, display-info, and disk-size extras.

Launching exported `MainActivity` does not change the caller identity of the
custom app and does not export the service or display Binder.

## Exact display wiring

The APK DEX contains the complete chain:

1. `DisplayProvider` calls `ServiceManager.waitForService("android.system.virtualizationservice")`.
2. It converts the result to hidden
   `IVirtualizationServiceInternal` and calls `waitDisplayService()`.
3. The returned Binder is converted to hidden
   `ICrosvmAndroidDisplayService`.
4. `DisplaySurfaceView` calls `setSurface(Surface, isCursor)` and
   `setCursorStream(ParcelFileDescriptor)`; teardown calls `removeSurface()`.

The crosvm source confirms that a VM with `DisplayConfig` receives
`--android-display-service=<config.name>`. Thus the Surface is delivered to
the display service selected by the privileged VM launch path; it is not a
guest framebuffer FD, dma-buf, or public `VirtualMachine` callback.

The custom app audit already established the decisive platform boundary:
`com.example.winavf` runs as `untrusted_app`, cannot discover the
`android.system.virtualizationservice` Binder, and lacks the Terminal-only
hidden AIDL classes. AOSP SELinux labels this service as
`virtualization_service`; only domains granted `virtualizationservice_use()`
receive service-manager `find` and Binder call permission. The ordinary app
domain has neither.

## What crosvm/AVF exports to a normal app

The local framework and crosvm source show these app-visible channels:

| Channel | Stage proved | Useful for display | Constraint |
|---|---|---:|---|
| `VirtualMachine.getConsoleOutput()` | crosvm serial/virtio-console output | only encoded text/binary protocol | `vmOutputCaptured`; no framebuffer |
| `VirtualMachine.connectVsock(port)` | running guest vsock endpoint | yes, if guest relay exists | requires guest-side encoder/driver/userland |
| AVF input socket pairs | touch/key/mouse injection | input only | no scanout |
| Terminal `ICrosvmAndroidDisplayService` | Surface scanout | yes | hidden Binder + privileged SELinux domain |
| guest RAM / dma-buf / resource export | not present in public framework | no | no API or FD export found |

No public AVF framework method returns a Surface, native window, dma-buf, host
GPU resource, or crosvm display FD. `DisplayConfig` and `GpuConfig` configure
the VM, but do not expose its scanout to the caller.

## Product options after this result

1. **Near-term UEFI visibility:** encode bounded GOP frames in firmware and
   send them over the existing captured console pipe; decode into the app's
   `SurfaceView`. This avoids privileged Binder and is reversible, but is a
   pre-EBS frame transport, not continuous scanout.
2. **Full Windows/WinPE graphics:** use a production-signed guest relay
   (`viogpudo`/`viosock`) that sends framebuffer updates over public vsock to
   an app-owned Surface. The remaining unknown is guest userland/driver
   execution, not the Android display bridge.
3. **Native scanout:** available only by becoming the platform-privileged
   Terminal/system component or by an OEM-provided exported bridge. Both are
   outside the current no-system-modification product constraints.

The first two options preserve the locked bootloader, no-root, no-flash, and
byte-identical Microsoft driver constraints.

## Ranked next action

The highest-information safe implementation is a small GOP-frame transport
PoC over `console_out`: fixed header, dimensions, pixel format, payload length,
CRC, and one frame before EBS. It should run in a throwaway VM name and leave
the immutable Windows baseline untouched. A later vsock relay can reuse the
same Android decoder and SurfaceView once WinPE execution is independently
observed.

No tablet runtime experiment was run in this pass because `adb` is unavailable
in the current host environment; all conclusions above are read-only/offline.

## Closed branches

Keep closed: Terminal activity/service hijacking, direct hidden Binder lookup
from `untrusted_app`, direct guest RAM mmap, dma-buf guessing without an export
FD, and post-EBS diagnostics as the current graphics blocker.

