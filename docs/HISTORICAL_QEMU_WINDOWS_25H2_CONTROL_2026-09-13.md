# Historical Termux/QEMU Windows 25H2 control — 2026-09-13

## Scope

This is a read-only reconstruction of the existing Termux/QEMU experiment in
`C:\Users\denis\MainProjects\win11ontab\tabs11-windows-research`.  It did
not launch QEMU, alter the Android tablet, or alter an AVF image.

## Evidence

The preserved reports establish the following independent control path:

```text
Termux user-space QEMU (TCG)
  -> QEMU Arm virt / EDK II
  -> Windows 11 ARM64 Setup
  -> NVMe installation
  -> installed Windows Boot Manager
  -> Windows OOBE / post-install user-mode
```

`reports/TEMPORARY_REPORT_2026-08-13.md` records completed file copy,
preparation, and component-installation stages.  It explicitly directs the
next launch to detach the ISO or boot from NVMe after the first reboot.

`reports/TEMPORARY_REPORT_2_2026-08-13.md` records that the ISO was detached,
the installed NVMe disk was booted, `EFI\\Microsoft\\Boot\\bootmgfw.efi` was
started, and Windows reached the Russian **«Идёт подготовка»** first-boot
screen.  The preserved screenshots independently show:

- `qemu-25h2-oobecheck.png`: `bootmgfw.efi` has been invoked from the NVMe
  EFI system partition.
- `qemu-25h2-currentstage.png`: Windows OOBE recovery screen, **«Почему был
  перезапущен мой ПК?»**, requesting an update/network connection.

Thus the later failure was not a pre-kernel or post-ExitBootServices loop. It
occurred after Windows graphical OOBE was executing.

## Cause of the observed recovery cycle

The historical installed-boot reports used `-nic none`.  The OOBE screenshot
explicitly states that an update is required and directs the user to connect
to Wi-Fi or wired networking.  This explains the observed recovery/restart
cycle without attributing it to the QEMU Arm platform.

The project already contains the bounded recovery launcher:

`vm/qemu/start-win11-oobe-net.sh`

It keeps the same QEMU Arm/TCG/NVMe/ramfb topology, attaches no installer ISO,
and adds only QEMU user-mode NAT with an `e1000e` device.  It requires neither
root, TAP networking, port forwarding, nor Android network modification.

## Classification

```text
QEMU_WINDOWS_SETUP_VISIBLE       = PASS (historical screenshot evidence)
QEMU_WINDOWS_INSTALLED_BOOT      = PASS (historical report and screenshot)
QEMU_WINDOWS_OOBE_USERMODE       = PASS (historical screenshot evidence)
QEMU_POST_INSTALL_RECOVERY_CAUSE = NETWORK_REQUIRED_UPDATE
QEMU_PLATFORM_BOOT_LOOP          = REFUTED
```

This is a useful control proving that Windows ARM64 itself and the installer
can run on the tablet in an unprivileged VM.  It does **not** establish an AVF
post-EBS pass: QEMU TCG's `virt` machine, firmware, NVMe, GIC implementation,
and graphics path differ materially from the product GenieZone/crosvm VM.

## Safe next action for this separate branch

If the historical Termux disk and UEFI VARS are still present, launch only the
existing `start-win11-oobe-net.sh` path and observe OOBE through localhost
VNC.  Do not reuse the installer launcher after the disk is installed; it
intentionally forces the ISO with `-boot order=d`.
