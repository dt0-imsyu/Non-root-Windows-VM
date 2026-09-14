# Samsung AVF / crosvm extension-surface audit — 2026-09-14

## Result

```text
CROSVM_EXTERNAL_DEVICE_SURFACE = FS_ONLY_PUBLICLY_EVIDENCED
CROSVM_INPUT_PATH              = PARTIAL
CROSVM_GPU_PATH                = PRIVATE_BACKEND / NOT_APP_FRAME_EXPORT
CROSVM_GENERIC_DEVICE_BROKER   = NOT_EXPOSED
```

This was read-only: no VM, Windows media, BCD, firmware, Android APK, or
system state changed.

## Actual Samsung boundary

On SM-X736B (`Android 16`, `GenieZone`), `vm info` reports no `/dev/kvm`, no
`/dev/vfio/vfio`, VFIO-platform unsupported and no assignable devices. The
shell reports custom-VM, paravirtual-device and console-input features disabled.
Those flags do not negate product evidence: the app has granted AVF permissions,
the actual VM is a crosvm/GenieZone VM, and it enumerates standard virtio PCI
functions.

The APEX crosvm, virtualizationservice, vfio_handler and vmnic executables
cannot be read by shell. No SELinux bypass was attempted. The matching source
evidence below is therefore **SOURCE_SUPPORT**, never arbitrary Samsung CLI
access.

## Availability matrix

| Surface | Source support | Actual AVF / app exposure | Status |
|---|---|---|---|
| Serial ttyS0 input/output | FD mapped to crosvm `--serial` | `getConsoleInput/Output`; 4096-byte loopback | PASS, serial only |
| virtio-input keyboard | `--input keyboard[...]` | config has `useKeyboard`; installed API has no `sendKeyEvent` | BLOCKED |
| virtio-input mouse / multitouch | mouse, single-/multi-touch, trackpad mappings | actual `sendMouseEvent/sendMultiTouchEvent`; `useMouse/useTouch` | PARTIAL, no guest proof |
| USB HID | controller support only | no arbitrary USB HID backend / FD | NOT EXPOSED |
| virtio-gpu display | GPU and Android display-service arguments | `1AF4:1050` exists, private display service blocked | PRIVATE BACKEND |
| vhost-user virtio-fs | `crosvm device fs`, then `--vhost-user fs,socket=` | RawConfig shared-path path | SOURCE-SUPPORTED ONLY |
| vhost-user GPU/input/block/net/vsock/sound | no config mapping found | no selector/socket handoff | NOT EXPOSED |
| network TAP | internal `createTapInterface()` | app requests only network support | INTERNAL ONLY |
| VFIO devices | source paths exist | runtime says unsupported / empty | BLOCKED |
| control socket / PCI hotplug | virtmgr makes private `--socket` listener | not returned by IVirtualMachine | INTERNAL ONLY |

## Meaning of the matching source

`add_console_arg()` preserves service-provided console FDs as
`/proc/self/fd/N`; that mechanism is runtime-proven for the app. The same
source has `add_input_devices_arg()` and `add_gpu_arg()`, but each is behind
the paravirtual-device build capability. `run_virtiofs()` is the sole
vhost-user construction path and hard-codes **fs**. `run_vm()` creates the
control listener and preserves FDs while starting private crosvm; it does not
export the listener to the app.

Thus a string in crosvm source does not constitute a generic AVF device API.

## Input and graphics consequences

```text
Android MotionEvent
  -> actual VirtualMachine mouse/touch API
  -> system-created input FD (matching framework contract)
  -> crosvm virtio-input frontend
  -> UEFI / Windows driver
```

Keyboard breaks at its first host call: the installed framework lacks the
reflected `sendKeyEvent(short, boolean)` method. Console input is UART, not HID.
The narrow safe input milestone is one disposable Linux/UEFI guest, with
`useMouse(true)` and/or `useTouch(true)`, one Android event and a guest-side
record. It must not touch the Windows baseline.

Pre-EBS GOP/WAVF already owns an app-visible frame path. Virtio-GPU PCI
presence proves only a guest frontend; it does not export a host framebuffer or
dmabuf to an untrusted app. For post-EBS the practical fallback remains
Windows agent -> vsock -> dirty-tile or encoded frames -> app Surface. A raw
2560x1600 RGBA stream is about 0.98 GB/s at 60 Hz and is not a final design.
