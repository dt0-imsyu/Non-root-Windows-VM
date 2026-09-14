# AVF UEFI input host probe — 2026-09-06

## Scope

One isolated AVF keyboard-injection probe was run.  It did not modify
firmware, the external Windows image, WIM, BCD, or any tablet partition.
The existing immutable external image was used without a staged patch.

## Preconditions

- External baseline image SHA-256 before launch:
  `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
- Staged image patch: absent.
- Test APK SHA-256:
  `E4A1741C469DC57C0B4B0B9BF28DB60CBC10599CED0EE14BDADCAFBA3AA8A7C6`.
- The test enabled only `VirtualMachineCustomImageConfig.Builder.useKeyboard(true)`.
  It then reflectively tried the locally discovered AOSP hidden method
  `VirtualMachine.sendKeyEvent(short, boolean)` with `KEY_ESC` (`1`) down/up.

## Result

The actual device framework does not expose that method:

```text
transport=AVF_VIRTIO_KEYBOARD
result=HOST_INPUT_ERROR
error=NoSuchMethodException: android.system.virtualmachine.VirtualMachine.sendKeyEvent [short, boolean]
```

The report is preserved at
`build-logs/gop-poc-20260906/uefi-input-host-probe-r1.txt`, SHA-256
`122E5FC509290C47B2E5F5DE42C6FDD5DADE00DB0BD997AC986776C7ED10E9FA`.
The corresponding serial capture is
`build-logs/gop-poc-20260906/uefi-input-host-probe-r1-serial.log`, SHA-256
`17766D6DA6117241636574C0D26750F389C68216C2A58C62EE57D4DF04B56A09`;
it reaches the established `ER` marker only.

The external baseline SHA-256 after force-stopping the VM is again
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

## Classification

```text
AVF_VIRTIO_KEYBOARD_HOST_TRANSPORT = BLOCKED_BY_RUNTIME_API_ABSENCE
AVF_SERIAL_BIDIRECTIONAL_BINARY    = BLOCKED (unchanged)
AVF_UEFI_INPUT_TRANSPORT           = BLOCKED
GRAPHICAL_UEFI_INPUT               = NOT_TESTED
```

`useKeyboard(true)` is only a configuration request.  It is not a writable
event endpoint, and this app lacks the hidden runtime method that would feed
the keyboard socket in the examined AOSP implementation.  Consequently no
claim about guest keyboard enumeration or UEFI hotkey handling is possible.

## Next bounded option

Do not alter BDS timeout or build an input firmware test.  The next useful
input investigation, if product input remains required, is a read-only audit
for a public Android/AVF API that returns an input `ParcelFileDescriptor` or
otherwise exposes a writable per-VM input stream.  If none exists, UEFI input
requires an OEM/platform API extension and is outside the untrusted-app scope.
