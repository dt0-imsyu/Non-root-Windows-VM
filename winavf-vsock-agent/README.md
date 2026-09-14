# WinAVF vsock agent

This is the deliberately small post-EBS input endpoint. It is not part of a
runtime candidate yet: `WINPE_USERLAND` and viosock binding remain unproven.

## Contract

The agent listens inside the Windows guest on virtio-vsock port **4050**. The
Android app, as the VM owner, uses `VirtualMachine.connectVsock(4050)` and
receives a bidirectional raw `ParcelFileDescriptor`.

On accept, the agent writes this 16-byte little-endian reply:

| Bytes | Meaning |
| --- | --- |
| 0–3 | ASCII `WVH1` |
| 4–7 | zero sequence |
| 8–11 | zero status |
| 12–15 | capabilities, bit 0 = keyboard `SendInput` implemented |

A keyboard command is this 16-byte little-endian packet:

| Bytes | Meaning |
| --- | --- |
| 0–3 | ASCII `WVI1` |
| 4–7 | client sequence |
| 8–9 | Windows virtual-key value |
| 10 | type `1` (keyboard) |
| 11 | action `1` down or `2` up |
| 12–15 | reserved, zero |

The reply is `WVO1`, followed by the echoed sequence, Win32 status (`0` is
accepted), and the capability field. `user32.dll` is loaded dynamically only
when the first keyboard command arrives, so the initial HELLO has no static
USER32 dependency.

## Build and first runtime use

Run `./build.ps1`. The first runtime candidate must add only this executable
and the already verified production-signed viosock package to WinPE, then
launch it only after the existing earliest-userland boundary is independently
observed. The first app-side assertion is the `WVH1` reply, **not** a keypress.

Only after `VSOCK_HELLO = PASS` may an `A` key down/up packet be used while a
known interactive WinPE/Setup desktop is visible. A successful socket reply
does not itself prove Windows accepted the input event.
