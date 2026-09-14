# Hidden API RX and native-display probe — 2026-09-09

## Scope and safety

This was one bounded app-owned Android probe on the installed Samsung Galaxy
Tab S11 5G (`SM-X736B`, `gts11`, Android 16 / SDK 36, One UI release build).
It did not start Windows, alter the Windows media, BCD, EDK2, Android system
images, APEXes, SELinux policy, physical block devices, or a shell-created VM.
No Binder transaction number or Parcel layout was guessed.

The Android product runtime image remained:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

after the probe.

## Baseline

| Field | Observed value |
|---|---|
| Device fingerprint | `samsung/gts11xx/gts11:16/BP4A.251205.006/X736BXXS6BZF4_OXM6BZF4:user/release-keys` |
| `ro.debuggable` / build type | `0` / `user` |
| Hypervisor | GenieZone (`/dev/kvm` absent) |
| WinAVF UID / context | `10441` / `u:r:untrusted_app:s0:c185,c257,c512,c768` |
| Requested AVF permissions | `MANAGE_VIRTUAL_MACHINE=granted`, `USE_CUSTOM_VIRTUAL_MACHINE=granted` |
| Original `hidden_api_policy` | absent (`settings get` returned `null`) |
| AVF framework location | `/apex/com.android.virt/javalib/framework-virtualization.jar` |
| Terminal AIDL location | `/apex/com.android.virt/priv-app/VmTerminalApp@BP4A.251205.006/VmTerminalApp.apk` |

The exact pulled artifact SHA-256 values are recorded in the accompanying
build-log directory:

```text
framework-virtualization.jar  8635B9E08B233EC977CDAB9A80707AFB4BEC361C86CAF6A7FA3E928B6F6DD322
service-virtualization.jar    B492F4891A0CF2E1784252EFCEC68102D40B059F51E729C6040B1B31ED9F09F8
VmTerminalApp.apk             CD101C3545CE936ACD01EF36BBA8E0CFFD3D40203E8ADB6E1BD12BD3BA25623E
```

## Reflection before and during the temporary policy

The probe saved the original value, ran `settings put global hidden_api_policy
1`, force-stopped and restarted WinAVF, repeated the inventory, then
force-stopped WinAVF and restored the absent value with `settings delete
global hidden_api_policy`.  The transaction log records:

```text
ORIGINAL_HIDDEN_API_POLICY=null
TEMPORARY_HIDDEN_API_POLICY=1
RESTORED_HIDDEN_API_POLICY=null
```

Before the policy change, the actual runtime exposed:

```text
VirtualMachineConfig.Builder.setVmConsoleInputSupported(boolean)
VirtualMachineConfig.isVmConsoleInputSupported()
VirtualMachine.getConsoleOutput()
```

but did **not** return `VirtualMachine.getConsoleInput()` in reflection.
During policy `1`, the same installed runtime additionally exposed:

```text
VirtualMachine.getConsoleInput() : OutputStream
VirtualMachine.createVmInputPipes()
VirtualMachine.mConsoleInReader / mConsoleInWriter
```

It also exposed hidden touch/mouse helpers, confirming that the difference is
the hidden-API filter rather than a Samsung API absence.  `DisplayConfig` and
`GpuConfig` configuration types are present in both inventories; they do not
offer a Surface or scanout-return API.

## Direct app console-input result

To distinguish method visibility from an actual returned stream, an updated
WinAVF APK (same signing-certificate SHA-256 as the installed package) ran one
new, app-owned capability probe.  Its distinct VM name was
`winavf-console-input-probe-20260909`; it used the existing U-Boot wrapper,
had **no disk**, never called `run()`, wrote zero guest bytes, and was deleted
in `finally`.

The saved report was:

```text
scope=NO_GUEST_RUN_NO_DISK_NO_PRODUCT_MEDIA
config.isVmConsoleInputSupported=true
getConsoleInput=OUTPUT_STREAM_USABLE
result=PASS
```

`vm list` was empty after the probe.  This proves a real app-owned
`OutputStream` can be obtained while hidden API enforcement is temporarily
relaxed.  A subsequent bounded no-disk echo guest proved the full 4,096-byte
binary route byte-for-byte; see
`docs/APP_OWNED_BINARY_CONSOLE_LOOPBACK_RUNTIME_2026-09-09.md`.

## Native display / Surface result

The direct access audit was run before and during policy `1` and was identical
in both cases:

```text
ServiceManager.getService("android.system.virtualizationservice") = NULL
IVirtualizationServiceInternal = ClassNotFoundException
ICrosvmAndroidDisplayService = ClassNotFoundException
```

The exact installed Terminal APK contains the private generated AIDL stubs and
the real methods:

```text
IVirtualizationServiceInternal.waitDisplayService()
ICrosvmAndroidDisplayService.setSurface(Surface, boolean)
ICrosvmAndroidDisplayService.removeSurface(boolean)
```

Those stubs are not in WinAVF's runtime classpath.  Since the service Binder
was unavailable even after the hidden-API relaxation, no Binder call was made,
no transaction code was guessed, and no `Surface` was submitted.  Filtered
logcat did not contain an AVC associated with this lookup; that is consistent
with rejection at service discovery before any Binder transaction.  The
direct evidence is therefore `SERVICE_NOT_EXPOSED`, while the established
platform boundary is the untrusted-app SELinux/service-manager visibility gate
rather than Java hidden-API filtering or an AVF permission grant.

The granted AVF configuration permissions do not grant discovery of this
private display Binder.  The app-owned VM handle also cannot be transferred to
shell through a public AVF API, so a shell/Shizuku caller cannot simply attach
the private display path to an app-owned VM.

## Cleanup

```text
hidden_api_policy = null (restored)
Running VMs: []
product image SHA-256 = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

Raw reports, command output, static artifacts, and filtered logcat are under:
`Non-root-Windows-VM/build-logs/hidden-api-rx-native-display-20260909/`.

## Commands used

The bounded device-facing sequence was limited to these command forms (with
the recorded package and artifact paths in the raw logs):

```text
adb shell settings get global hidden_api_policy
adb shell settings put global hidden_api_policy 1
adb shell am force-stop com.example.winavf
adb shell am start -n com.example.winavf/.MainActivity --ez audit true --ez display_host_audit true
adb shell am start -n com.example.winavf/.MainActivity --ez console_input_api_probe true
adb shell settings delete global hidden_api_policy
adb shell vm list
adb shell sha256sum /sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img
```

The only APK operation was `adb install -r` of a same-certificate WinAVF build
containing the no-run console-stream probe.  No `vm run`, shell Windows VM,
raw Binder call, or device-storage write command was used.

## Result

```text
HIDDEN_API_POLICY_BOOTSTRAP = PASS
APP_CONSOLE_INPUT_TESTAPI_VISIBLE = PASS
PRODUCT_APP_CONSOLE_INPUT_API = PASS
APP_OWNED_BINARY_CONSOLE_RX = PASS (subsequent bounded echo run)
DISPLAY_HIDDEN_API_VISIBLE = FAIL
DISPLAY_SERVICE_DIRECT_APP_ACCESS = FAIL
DISPLAY_SET_SURFACE_DIRECT_APP = SERVICE_NOT_EXPOSED
DIRECT_APP_NATIVE_CROSVM_DISPLAY = NOT_CONFIRMED
DISPLAY_ACCESS_GATE = SELINUX
SHIZUKU_DISPLAY_BROKER = REQUIRES_VM_HANDLE_TRANSFER
PRODUCT_BASELINE_RESTORED = PASS
```

The one evidence-based next branch is **A: direct app console-input path**.
It can be used in a separately authorized product-equivalent diagnostic with
the temporary hidden-API policy.  It must not be conflated with native display:
the private Surface path remains unavailable to the app and Shizuku has not
been justified or implemented.
