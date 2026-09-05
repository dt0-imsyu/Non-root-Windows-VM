# Native AVF display audit

## Scope

This audit was read-only on Samsung SM-X736B Android 16 / One UI. It did not start Terminal, create a VM, touch Windows media, write a block device, or alter firmware, SELinux, APEX, or crosvm.

## Observed protocol

The installed Terminal APK follows this chain:

1. `DisplayProvider` waits for `android.system.virtualizationservice`.
2. It obtains `IVirtualizationServiceInternal.waitDisplayService()`.
3. It casts the returned Binder to `ICrosvmAndroidDisplayService`.
4. A `SurfaceHolder.Callback` invokes `setSurface(holder.getSurface(), isForCursor)` and later `removeSurface(isForCursor)`.
5. Its cursor uses a socket pair, `setCursorStream()`, and a second SurfaceView overlay.

`VmLauncherService` feeds `DisplayConfig` and `GpuConfig` to AVF. The display configuration causes host crosvm to receive `--android-display-service=<config.name>`.

## Permission conclusion

The custom WinAVF app is in the `untrusted_app` SELinux domain. It has the two ordinary AVF permissions but cannot discover the internal virtualization Binder, and the two Terminal-only AIDL interfaces are absent from its classpath. AOSP labels this Binder `virtualization_service`; only domains granted `virtualizationservice_use(domain)` receive the service-manager `find` permission and Binder call rights.

Therefore the platform's native scanout path exists but is not reachable from the current custom-app identity. A platform/OEM-signed bridge or public per-VM surface API is required before direct graphical UEFI can be implemented under the project's safety rules.
