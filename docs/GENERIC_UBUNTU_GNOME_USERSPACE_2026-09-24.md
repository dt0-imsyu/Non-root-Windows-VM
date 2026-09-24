# Generic Ubuntu GNOME userspace runtime — 2026-09-24

## Verdict

```text
GENERIC_UBUNTU_KERNEL       = PASS
GENERIC_UBUNTU_INIT         = PASS
GENERIC_UBUNTU_SYSTEMD      = PASS
GENERIC_UBUNTU_VIRTIO_GPU   = PASS (DRM framebuffer; capset 0 timeout remains)
GENERIC_UBUNTU_GDM          = PASS
GENERIC_UBUNTU_GNOME_SHELL  = PASS
GNOME_USERSPACE             = PASS
GNOME_VISIBLE_IN_APP        = NOT_TESTED / NOT_CONFIRMED
```

The final serial contains `Started gdm.service`, `GNOME Shell started`, and
`Registering session with GDM`. The VM remained alive after these events.
No `SQUASHFS error`, `I/O error, dev loop`, or `Failed to start gdm.service`
record appeared in the captured final log. The log does not explicitly print
`Reached target graphical.target`; GNOME Shell startup is the stronger direct
userland witness. This is not yet proof of a visible, interactive desktop in
the U-AVF SurfaceView.

## Controlled runtime findings

1. Kernel-first U-Boot loads the proven EDK2 FD from the GPT/FAT ESP, then
   the EFI launcher starts the untouched Ubuntu kernel and initrd.
2. With **two virtio-blk disks** (128 MiB ESP + stock ISO, or two identical
   128 MiB ESP disks), the guest reproducibly stopped after
   `Freeing initrd memory`; `crosvm` remained alive but its vCPU CPU-time
   stopped advancing. With only one ESP disk, the same kernel reached `/init`
   and `casper-premount`. Therefore the two-disk topology, not ISO content,
   explains this early boundary.
3. A **single combined disk** with the same 128 MiB platform region and a
   second GPT partition containing byte-exact ISO data reached systemd and
   GDM. Both GPT headers and ISO9660 PVD passed offline audit. The ISO
   partition SHA-256 matched the stock ISO exactly.
4. Under the original `useAutoMemoryBalloon(true)` configuration, repeated
   SquashFS/loop read failures occurred. Journald-to-console showed
   `gdm-session-worker` failing with `Input/output error`. Switching the disk
   from RW to RO did not fix this and sometimes stopped progress earlier.
5. With the same combined disk, same GPU and same Ubuntu bytes, changing
   **only** `useAutoMemoryBalloon(false)` eliminated observed SquashFS/loop
   errors in the bounded final run and let GNOME Shell start. This is a
   controlled runtime correlation, not yet proof of the internal GenieZone
   memory-corruption mechanism. No firmware, ISO, kernel, initrd or rootfs
   bytes changed between the failing and passing runs.
6. An `idle=poll` attempt was rejected by the Ubuntu ARM64 kernel as an
   unknown parameter and did not alter the stall. The diagnostic UART wake
   attempt could not send a byte: Android reflection returned
   `NoSuchMethodException` for `VirtualMachine.getConsoleInput()` on the
   current device build. Do not count it as a guest UART-input test.

## Exact artifacts

| Artifact | SHA-256 / bytes |
|---|---|
| Stock Ubuntu 24.04.5 ARM64 ISO (unchanged) | `2BE09CA883921BFF6D8E6B0BFBAFD13E32436553B7086F33BCE3A4C5BAD8BD14` / 3,967,463,424 |
| Original 128 MiB platform ESP disk | `413B28882832DDC73CA3B425D9676542595590B53B91739FC4A45CDF41046AA2` / 134,217,728 |
| Combined disk with diagnostics launcher | `FFABA39B31EA1E95B40F4DD3F67BF5C274C336C6CFF427E7075AC0BD82143714` / 4,102,029,312 |
| ISO GPT partition within combined disk | `2BE09CA883921BFF6D8E6B0BFBAFD13E32436553B7086F33BCE3A4C5BAD8BD14` / 3,967,463,424 |
| Diagnostic EFI launcher (`journald.forward_to_console`) | `91533804361FA38946C63FF15819FA3DA16D4175CD16243990B65DC13562F597` / 20,480 |
| Ubuntu kernel copied unchanged from ISO | `3F18B4B8D4DA3ED5EFD9B3AD0ED4AB3286178DED979BFDCBD759CC30EB805CE4` |
| Ubuntu initrd copied unchanged from ISO | `DAF02234098BF537B324895D1C7354633E16DB16E14D978108219E3C94BCB3F2` |
| Installed final U-AVF APK | `299D80A36025FEF81015B15A648DF15717BC4688CAD38B2999DBF7A1A0058374` |
| Final APK re-run serial snapshot (09:49 MSK) | `DEB480C3408DC2186E5629FBEE1440D37185E0CED52C49C867D0BE35E16C96E4` / 1,560,396 |

Host paths are rooted at `C:\Users\denis\MainProjects\win11ontab`:

- `artifacts\generic-ubuntu\ubuntu-24.04.5-desktop-arm64.iso`
- `artifacts\generic-ubuntu\generic-ubuntu-platform-gpt.img`
- `artifacts\generic-ubuntu\generic-ubuntu-one-disk-journal-rplus.img`
- `build-logs\generic-ubuntu-20260924\generic-runtime-no-balloon-gpu-final.log`
- `build-logs\generic-ubuntu-20260924\generic-runtime-final-app-serial.log`
- `build-logs\generic-ubuntu-20260924\generic-runtime-no-balloon-report.txt`

The final runtime was launched through:

```powershell
& 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe' shell am start -n com.example.winavf/.MainActivity --ez generic_ubuntu_combined true
```

The combined disk was staged at
`/sdcard/Android/data/com.example.winavf/files/generic-ubuntu-one-disk-journal-rplus.img`.
The app checks its exact size and SHA, copies it to app-private storage, and
creates the one-disk VM. The stock ISO source is checked independently and
never mutated. The final GPU config is 1280×800; Ubuntu enumerated
`PCI 1AF4:1050`, bound `virtio_gpu`, and created a DRM framebuffer. A capset-0
timeout remains in the GPU log and must not be confused with proof of a
working host display service.

The final APK also routes the user-facing **Linux** Launch/Stop buttons to
this generic combined-disk profile, rather than the retired Vxx carrier
profile. After that UI change, the APK was rebuilt, installed and run again:
`Started gdm.service`, `GNOME Shell started`, and `Registering session with
GDM` were all observed again; zero SquashFS/loop I/O errors were found in
the captured snapshot. The successful VM was left running for inspection.

The local file `artifacts\generic-ubuntu\generic-ubuntu-one-disk-journal.img`
is an **invalid, untested intermediate** from a failed FAT write attempt.
Do not stage or launch it. The audited and used file has the distinct
`-journal-rplus.img` suffix and SHA listed above.

## Next boundary

`GNOME_VISIBLE_IN_APP` remains unproven. Samsung's native AVF display broker
is not available to an ordinary APK, so the next graphics task is a guest
frame producer and app-owned transport/renderer. Keep the passing one-disk,
no-auto-balloon platform as the control. Do not resume Vxx carrier images or
modify the stock ISO to pursue visibility.
