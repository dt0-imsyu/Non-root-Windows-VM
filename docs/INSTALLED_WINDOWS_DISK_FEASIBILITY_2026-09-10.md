# Installed Windows ARM64 disk feasibility — 2026-09-10

## Scope

Static feasibility check only.  No local disk was formatted, no VHD was
created, and no Android/firmware/Windows media was changed.

## Findings

The official ARM64 LTSC ISO is available and contains:

```text
install.wim = 4,208,623,457 bytes
boot.wim    =   554,880,055 bytes
```

The existing known-good VM disk is a 9,126,805,504-byte GPT image containing
one 9,125,740,032-byte FAT32 partition.  That layout is sufficient for the
WinPE RAM-disk boot medium, but it is not a supported installed Windows system
volume.

The current ArmVirtKvmTool firmware explicitly packages `EnhancedFatDxe`,
`DiskIoDxe`, and `PartitionDxe`; it does not package an NTFS UEFI driver.
An installed Windows diagnostic disk would therefore require, at minimum:

1. a FAT ESP holding `BOOTAA64.EFI` and Windows Boot Manager; and
2. a separate NTFS Windows system partition that Boot Manager opens after it
   starts; and
3. a substantially larger virtual disk, because applying the 4.2-GB compressed
   install WIM produces an operating-system tree larger than the current
   single-FAT disk.

## Decision

```text
INSTALLED_WINDOWS_DISK_ON_CURRENT_9GB_FAT_TOPOLOGY = NOT_FEASIBLE
INSTALLED_WINDOWS_DISK_REQUIRES_NEW_STORAGE_TOPOLOGY = YES
```

This would be a useful *different boot-class diagnostic*, but not a repair for
the existing installer and not a short A/B.  It would introduce new GPT,
filesystem, virtual-disk-size, and boot-device variables, so it cannot
currently explain or fix the known-good medium's `BES/ER` post-EBS stop.

Do not build it merely to chase the installer.  Any later execution needs an
explicit decision to accept that separate machine/storage topology.
