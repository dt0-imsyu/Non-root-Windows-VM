# Shell `-T` Base64 → COM1 loopback — 2026-09-07

## Scope

One disposable, non-Windows shell VM was run.  No Windows image, BCD,
firmware, APK, driver, or product baseline was changed.  This test follows the
foreground `adb shell -T` stdin path established by the FD audit, but carries
the host-to-device payload as Base64 ASCII so that ADB's terminal-like input
translation cannot alter the bytes that crosvm receives.

```text
host 4096-byte payload
  -> Base64 ASCII over adb shell -T
  -> base64 -di on Android
  -> foreground raw pipe (vm run has no --console-in)
  -> crosvm ttyS0
  -> bare-metal serial loopback guest
  -> --console file on Android
```

## Evidence

| Field | Value |
|---|---|
| Disposable VM CID | `2102` |
| Input length | `4096` bytes (`00..FF` repeated) |
| Input SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| Device raw console length | `4127` bytes |
| Device raw console SHA-256 | `0C1B9F626639576BCF9BF31BAE0F595C9DE7C0DF0B2C6D4ECFE6CA48947F5597` |
| Returned payload length | `4096` bytes |
| Returned payload SHA-256 | `C8F5D0341D54D951A71B136E6E2AFCB14D11ED8489A7AE126A8FEE0DF6ECF193` |
| Byte comparison | exact, all 4,096 bytes |
| crosvm termination | `Shutdown`, exit `0` |

The leading 31 bytes are the expected `SHELL_SERIAL_LOOPBACK_READY` marker.
The final 4,096 bytes in the Android-side raw console file match the source
payload byte-for-byte, including zeroes, CR/LF, DEL, and high-bit values.
No crosvm wait-context error occurred.

The host's direct `adb shell -T` stdout only carried the early marker and did
not yield a raw live return stream before the bounded client timeout.  This is
consistent with the earlier finding that ADB's shell transport is text-like
for binary data.  It does **not** invalidate the raw Android console-file
evidence, but it means a real WinDbg bridge still needs text framing or a
shell-side raw-to-text output relay.

## Result

```text
SHELL_T_FOREGROUND_STDIN_TO_CROSVM = PASS
HOST_TO_GUEST_RAW_COM1             = PASS (Base64 text relay, raw device pipe)
GUEST_TO_DEVICE_RAW_COM1           = PASS
SHELL_BINARY_TRANSPARENT_COM1      = PASS at the crosvm/device boundary
HOST_RAW_KD_RETURN_STREAM           = NOT_YET_AVAILABLE
WINDOWS_KD_HANDSHAKE                = INCONCLUSIVE (unchanged)
```

The exact device staging directories for this and the prior direct shell-T
loopback were removed after evidence pull (`CLEANUP_PASS`).  The only running
VM after cleanup is the pre-existing unrelated `debian` VM (CID `2097`).

## Next action

Do not launch another Windows diagnostic VM yet.  Implement and statically
audit a small text-framed **outbound** shell relay (raw `--console` file to
Base64 records on ADB stdout), then verify its byte-exact decode with a
disposable loopback.  That will provide the missing real-time host return
direction required by WinDbg/KD.

