# Ubuntu GNOME: DXE Device-Tree handoff V11 runtime

## Scope

This is a disposable Linux-only control. It did not open, stage, patch, or
launch the immutable Windows raw image:

```text
WINDOWS_BASELINE_SHA256 = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

V11 uses the previously audited Ubuntu V10 raw medium and changes one 2 MiB
firmware range only. The change makes `KvmtoolPlatformDxe` select its normal
Device-Tree publication path during DXE rather than selecting ACPI. This is
the required condition for `FdtClientDxe` to install `gFdtTableGuid` from the
FDT HOB before Linux starts.

| Artifact | Value |
| --- | --- |
| Base Ubuntu raw | `E:\\winavf-ubuntu-gnome-24.04.5-v10-fdtclient-cpu0-candidate.img` |
| Base raw SHA-256 | `FB201BABDD0E309D5177D683387495D058ACF910BAAEF8733DCB944CA92E569A` |
| V11 firmware FD | `firmware-work\\edk2\\artifacts\\KVMTOOL_EFI-ubuntu-fdt-handoff-v11.fd` |
| FD SHA-256 | `7162202A2ED14C6BE3433915CB5786D9A41E3722647E40AA3CFEF29720D14963` |
| Patch | `build-logs\\ubuntu-gnome-v11-fdt-dxe\\ubuntu-gnome-v11-fdt-dxe-firmware.patch` |
| Patch SHA-256 | `9C109F3EB95D1B6F27929D970152725E0F2328A25FC3C847D8ED1603D86EDC55` |
| Changed range | offset `7250927616`, length `2097152` |
| Patch forward / rollback simulation | PASS / PASS |

The only source delta is the diagnostic constant in
`ArmVirtPkg/KvmtoolPlatformDxe/KvmtoolPlatformDxe.c` that forces this
disposable profile through the existing Device-Tree selection branch. The
normal Windows product path is untouched.

## Runtime result

The guest passed all formerly missing boundaries after `BES`:

```text
LINUX_KERNEL_POST_EBS          = PASS
LINUX_FDT_DXE_HANDOFF          = PASS
LINUX_GICV3                    = PASS
LINUX_VIRTUAL_TIMER            = PASS
LINUX_PCI_ENUMERATION          = PASS
LINUX_VIRTIO_BLOCK             = PASS
LINUX_SYSTEMD_PID1             = PASS
LINUX_VIRTIO_GPU_BOUND         = PASS
```

Evidence from the raw serial capture:

```text
Machine model: linux,dummy-virt
arch_timer: cp15 timer running at 13.00MHz (virt).
GICv3: CPU0: found redistributor 0 region 0:0x000000003ffd0000
virtio_blk virtio4: [vda] 17825792 512-byte logical blocks
Run /init as init process
Starting systemd-udevd version 255.4-1ubuntu8.17
[drm] Initialized virtio_gpu 0.1.0 for 0000:00:01.0 on minor 1
```

Thus the stock app-owned AVF/GenieZone topology demonstrably supports a
post-EBS Linux kernel, normal FDT discovery, a live root transition, PID 1,
virtio block, and virtio GPU binding. This is an independent positive
post-EBS platform milestone.

## GNOME live-session blocker

The live graphical session was not reached in this run. The first fatal cause
is explicit and is not a timer, FDT, or systemd-start failure:

```text
SQUASHFS error: xz decompression failed, data probably corrupt
SQUASHFS error: Failed to read block ...
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000007
```

Before runtime, Windows FAT32 auditing validated all 21 Casper payload hashes.
Afterward, independent raw-sector extraction of the three mounted live layers
with mtools produced the ISO's expected SHA-256 values:

```text
minimal.squashfs                = a041643c7f4b33bde728d452cdc08dc039b90795e72b68b29fd018f8e5a996c4
minimal.standard.live.squashfs  = 6a268bccb0d99daf828b18fcedb14c3d918828417db95156f7a8fcadb389d79b
minimal.standard.squashfs       = 96ff797ca17199a3223d1075930c37e9a451168867af513edac929c294b97567
```

Those files are each one contiguous FAT allocation run, so fragmented-chain
handling is not an explanation. The candidate was also byte-identical when
staged through ADB. The remaining unproven leg was the Android app-private
copy used as crosvm's backing file; V12 adds a full SHA-256 gate on exactly
that private copy before VM creation.

## V12 private-copy-gated repeat

V12 used identical Ubuntu V10 media and the identical V11 DXE-FDT patch. The
only executable change is a full private-copy SHA-256 check immediately before
the patch and VM creation. The APK SHA-256 was
`393DB95EE9FB2520E28F8BCE473CC305A70CDFE1BEBC682EEA20AFC455B9EF6D`.

The gate passed; Casper then completed rather than panicking at PID 1:

```text
Begin: Running /scripts/casper-bottom ... done.
Begin: Adding live session user ... done.
Started gdm.service - GNOME Display Manager.
Started Session 4 of User ubuntu.
Ubuntu 24.04.5 LTS ubuntu ttyS0
```

```text
ANDROID_PRIVATE_UBUNTU_MEDIA_SHA256 = PASS
UBUNTU_CASPER_BOTTOM                = PASS
UBUNTU_GNOME_DISPLAY_MANAGER        = PASS
UBUNTU_GNOME_USER_SESSION           = PASS
UBUNTU_GNOME_SCREEN_IN_APP          = NOT_AVAILABLE
```

This proves that the earlier PID-1 failure was not a platform handoff failure:
the same platform now reaches GNOME's display manager and a live user session.
The serial also continues to show later SquashFS XZ errors while the live
desktop reads additional packages. They are now a distinct large-runtime-data
integrity issue, not a blocker to the Linux/desktop milestone. The project
does not yet have a post-EBS framebuffer relay, so `GDM` is evidence of a
graphical session on the guest, not a claim that GNOME pixels were shown in
the Android `SurfaceView`.

## Evidence

| Evidence | SHA-256 |
| --- | --- |
| Raw serial `build-logs/ubuntu-gnome-v11-fdt-dxe-serial-20260920.log` | `ECCF8E7D20DB9DED69E2BB20DC95E095696B746902467D7A536B046FF8DA81A2` |
| V12 raw serial `build-logs/ubuntu-gnome-v12-private-hash-serial-20260920.log` | `4E3EA7B4562410D5B443289225D7AC1A5FE17A726F2915E3692FC88D676F22C7` |
| FD | `7162202A2ED14C6BE3433915CB5786D9A41E3722647E40AA3CFEF29720D14963` |
| Patch | `9C109F3EB95D1B6F27929D970152725E0F2328A25FC3C847D8ED1603D86EDC55` |

The Android Ubuntu VM and its private disk were removed after the run. Its
external staging raw and firmware-patch copy were removed as well. The Windows
payload remained untouched, confirmed by the app cleanup report.
