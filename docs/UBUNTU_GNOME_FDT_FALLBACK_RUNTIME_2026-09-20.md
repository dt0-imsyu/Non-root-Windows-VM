# Ubuntu GNOME FDT fallback runtime — 2026-09-20

## Scope

One disposable, app-owned Ubuntu 24.04.5 ARM64 desktop candidate was used to
test whether an EFI application can repair the FDT path that Linux uses after
UEFI hands off.  No Windows payload, Windows BCD, Windows WIM, Android system
component, or immutable Windows baseline was modified.

## Candidate

| Item | Value |
| --- | --- |
| Candidate raw image | `E:\winavf-ubuntu-gnome-24.04.5-v10-fdtclient-cpu0-candidate.img` |
| Raw SHA-256 | `FB201BABDD0E309D5177D683387495D058ACF910BAAEF8733DCB944CA92E569A` |
| EFI launcher SHA-256 | `9926FBE93D47384E516C9B440C0502F5CE0163EED7EF7DC956394D45414F5BE3` |
| Captured serial SHA-256 | `CCD4A383A044220BF76CDBF6759B12AECA72E7791879C3371CE4AE835B3D3C01` |

The launcher obtained EDK2's `FdtClient` protocol, found an `arm,armv8`
node, wrote its `reg` property as MPIDR 0, and removed the ACPI configuration
tables before starting the Ubuntu EFI stub. `UF0` is emitted only after that
FdtClient update succeeds; `UA0` is emitted after ACPI table removal.

Important qualification found during the subsequent source audit: in the
current KvmTool build, `FdtClientDxe` publishes `gFdtTableGuid` only after
`KvmtoolPlatformDxe` has selected the Device-Tree platform protocol during
DXE. The normal product firmware selected ACPI earlier. Therefore V10 did
**not** activate the normal FDT handoff merely by removing ACPI tables from a
late EFI launcher.

## Runtime evidence

The serial sequence was:

```text
U0 U1 U2 UF0 UA0 U3 ER
Linux version 7.0.0-31-generic
OF: reserved mem: Reserved memory: No reserved-memory node in the DT
Failed to find device node for boot cpu
missing boot CPU MPIDR, not enabling secondaries
...
Kernel panic - not syncing: Attempted to kill the idle task!
```

Linux therefore reached `start_kernel()` after the proven EBS post-return
marker `ER`. It then faults in `nr_free_zone_pages()` while building zone lists;
the preceding missing boot-CPU node is the concrete malformed-FDT condition.

Full raw serial: `build-logs/ubuntu-gnome-v10-fdtclient-serial-capture-20260920.log`.

## What this separates

The normal ACPI Ubuntu route previously reached the initramfs and Casper, but
did not expose the required PCI/virtio block path, so Casper could not find the
live medium. The FDT fallback route gets farther in the platform-description
direction, but Linux still receives an FDT with no node matching boot MPIDR 0.

This test rules out a late EFI-application-level repair. The mutation succeeds
(`UF0`), but because the firmware had already selected ACPI, the normal
`FdtClientDxe` publication path was not active. It does **not** prove that
Linux consumed a different FDT tree; it proves that deleting ACPI tables late
is insufficient to switch EDK2 from its ACPI handoff to its Device-Tree
handoff.

## Status

```text
LINUX_KERNEL_POST_EBS              = PASS
LINUX_FDT_FALLBACK_ENTERED          = PASS
LINUX_FDT_BOOT_CPU_TOPOLOGY_VALID   = FAIL (late-launcher path)
UBUNTU_GNOME_LIVE_USERSPACE         = NOT_REACHED
POST_EBS_GNOME_SURFACE_PRESENTATION = NOT_AVAILABLE
```

This does not mean Linux cannot run on the VM: the earlier Debian control
proved post-EBS Linux userspace. It means that Ubuntu Live needs either a
correct lower-level FDT (with CPU and PCI topology) or a complete ACPI PCI root
bridge description so its live filesystem becomes reachable.

## Next technically meaningful work

Do not make another ISO, initrd, or EFI-launcher variant. The next informed
test is a firmware-only configuration A/B: select Device Tree during DXE so
that `FdtClientDxe` publishes the already-mutated HOB FDT through the standard
`gFdtTableGuid` path. If that fails, the remaining candidates are a U-Boot/crosvm
FDT repair or a complete ACPI PCI-root description. None are GNOME-media
changes.
