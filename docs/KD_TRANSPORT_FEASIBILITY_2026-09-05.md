# AVF console / Windows KD transport feasibility — 2026-09-05

## Result

```text
AVF_SERIAL_BIDIRECTIONAL_BINARY = BLOCKED
KD_HOST_BRIDGE                   = NOT_CREATED
BCD_BOOTDEBUG                    = NOT_APPLIED
WINDOWS_KD_HANDSHAKE             = NOT_TESTED
KERNEL_ENTRY_OBSERVED            = NOT_OBSERVED
EARLIEST_WINDOWS_LOCATION        = ExitBootServices post-return (`ER`)
```

No BCD, WIM, FAT, firmware, Windows binary, Android system, or tablet runtime
image was changed by this audit.  No VM was run.

## Device and application actually audited

```text
Device serial:       R52Y9072A2R
Model:               SM-X736B (gts11)
Android API level:   36
Build fingerprint:   samsung/gts11xx/gts11:16/BP4A.251205.006/
                     X736BXXS6BZF4_OXM6BZF4:user/release-keys
Package:             com.example.winavf
Package version:     versionCode=0, targetSdk=36
```

The runtime capability audit was invoked without starting the VM:

```powershell
adb shell am start -n com.example.winavf/.MainActivity --ez audit true
adb exec-out cat /sdcard/Android/data/com.example.winavf/files/avf-capability-audit.txt
```

Raw captured evidence is preserved under:

```text
build-logs/kd-feasibility-20260905/
  avf-capability-audit-device.txt
  package-dumpsys.txt
  device-fingerprint.txt
  console-input-api-failure-ui.xml
  console-input-api-failure-serial.log
  audit-summary.txt
  SHA256SUMS.txt
```

`SHA256SUMS.txt` was generated after capture and covers every retained raw
audit file.

## Exact console API result

The actual Android 16 runtime exposes:

```text
VirtualMachine.getConsoleOutput(): java.io.InputStream  PRESENT
VirtualMachine.getLogOutput():     java.io.InputStream  PRESENT
VirtualMachine.getConsoleInput():  OutputStream          ABSENT
```

The installed application has the permitted configuration setters:

```text
VirtualMachineConfig.Builder.setConsoleInputDevice(String)
VirtualMachineConfig.Builder.setVmConsoleInputSupported(boolean)
VirtualMachineConfig.Builder.setConnectVmConsole(boolean)
```

but these are **configuration flags**, not a caller-visible write handle.  The
runtime `VirtualMachine` object has no `getConsoleInput`, writable
`ParcelFileDescriptor`, `OutputStream`, socket, or Binder method that can send
bytes into that configured console.

The source configures:

```java
setConsoleInputDevice("ttyS0");
setVmOutputCaptured(true);
setVmConsoleInputSupported(true);
```

in `android-app/src/com/example/winavf/MainActivity.java` lines 286–288.  It
obtains output only with `getConsoleOutput()` at line 202 and copies those raw
bytes directly to app-private/external `serial.log` before separately decoding
a UI-only UTF-8 preview (lines 302–321).  Thus the **outbound** file capture
does not itself apply UTF-8, CR/LF, or line-framing conversion.  There is no
corresponding inbound byte path to characterize for zero bytes, framing,
coalescing, or loss.

An older direct input probe attempted exactly the missing method:

```java
(OutputStream) vm.getClass().getMethod("getConsoleInput").invoke(vm)
```

It failed at runtime with:

```text
NoSuchMethodException:
android.system.virtualmachine.VirtualMachine.getConsoleInput []
```

The retained UI/serial evidence is in the audit directory above.  This is an
API-surface failure, not a text-encoding failure; no host byte can be accepted
by the application, so raw binary transparency cannot be tested or claimed.

## Guest endpoint correlation

The application requests `ttyS0`.  The existing U-Boot/EDK2 serial trace for
the same VM configuration reports:

```text
In:    serial,usbkbd
Out:   serial,vidconsole
Err:   serial,vidconsole
serial addr = 0x00000000000003f8
width      = 0x1
shift      = 0x0
```

This identifies the captured guest console as the 16550-style serial endpoint
at `0x3f8` (the expected COM1-style UART mapping), so it is a plausible
Windows serial KD target **only if** input can be supplied.  It does not prove
that the host can write to it.  The host-to-guest half is absent.

`VirtualMachine.connectVsock()` does return a `ParcelFileDescriptor`, but it
is a vsock connection, not a UART/COM endpoint.  It cannot replace the early
serial KD path without a Windows vsock stack/driver, which is outside this
pre-kernel diagnostic branch.

## Why a userspace bridge cannot be built now

A raw host bridge needs both directions:

```text
WinDbg/KD endpoint <-> raw bridge <-> app write handle <-> guest UART
```

The first two links can be ordinary userspace networking or a named pipe, but
the required `app write handle -> guest UART` link is unavailable in the
public/runtime-resolved `VirtualMachine` API.  The app already holds
`MANAGE_VIRTUAL_MACHINE` and `USE_CUSTOM_VIRTUAL_MACHINE` (both granted), so
this is not an Android runtime-permission prompt that an app update can fix.

A bridge would require one of the following new platform capabilities:

1. a public `VirtualMachine` writable console stream/FD; or
2. a privileged/system Binder API that exposes the console input FD; or
3. a system crosvm/virtualization-service change.

All three exceed the allowed untrusted-app/userspace scope.  Root is not the
right workaround and was not attempted.

## Explicitly not done

- No BCD setting was edited: therefore no wrong-object `{bootmgr}` / Windows
  loader experiment can have occurred.
- No KD bridge, named pipe, TCP proxy, or WinDbg session was created.
- No testsigning or custom boot-start driver was used.
- No VM run was made.

## Decision

Do not run a BCD bootdebug A/B: without an inbound UART endpoint an absent KD
handshake would be non-diagnostic.  The correct next step is to obtain a
documented writable AVF console endpoint (or explicit authority for a
platform-side bridge), then repeat this audit before touching BCD.
