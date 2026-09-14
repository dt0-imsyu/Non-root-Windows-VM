# Direct Linux EFI-stub handoff probe — prepared 2026-09-11

## Purpose

The first Debian control reached EDK2's `StartImage()` handoff to GRUB and
then produced the already-familiar raw `ER` post-EBS marker, but it never
printed GRUB's `Booting Linux` or a Linux early-console line.  GRUB can load an
ARM64 Image through a path that does not give a separate firmware
`IMAGE_AUDIT` record for the kernel.  Therefore that run cannot distinguish
between “GRUB never started the kernel” and “the Linux EFI stub started but
made no visible early output.”

This next disposable-media probe removes GRUB entirely.  It uses a minimal
locally-built ARM64 EFI launcher as `\\EFI\\BOOT\\BOOTAA64.EFI`; the launcher
uses normal UEFI Boot Services to load Debian's official ARM64 `Image`, sets
the Linux EFI-stub command line, and calls `StartImage()`.

No firmware, Android app, Windows WIM/BCD, Windows binary, or immutable
Android baseline is changed by candidate construction.

## Static evidence

| Item | Value |
|---|---|
| Launcher | `firmware-work/edk2/Build/ArmVirtKvmTool-AARCH64/DEBUG_GCC5/AARCH64/ArmPkg/Application/AvfLinuxEfiStubProbe/AvfLinuxEfiStubProbe/DEBUG/AvfLinuxEfiStubProbe.efi` |
| Launcher size | 20,480 bytes |
| Launcher SHA-256 | `4F40F842D5483071842F0C5847748BB161B89434F3F32611C62D254655B5F074` |
| Architecture | ARM64 PE/COFF |
| Debian Image SHA-256 | `84B9C190BB4589C4A9527E3191FEC051F9F115E88F0A3E8AFAE96BA0DFB4DFEF` |
| Debian initrd SHA-256 | `3B451F2098AE2E3CCF76B618BA742184D795393C25D6B229130AB106BC33FFA5` |

The launcher embeds raw UART stages:

```text
L0  launcher entered
L1  UEFI LoadImage(Debian Image) succeeded
L2  EFI-stub load options installed
L3  UEFI StartImage(Debian Image) invoked
LX  StartImage returned unexpectedly
```

The exact EFI-stub options are:

```text
initrd=\DEBIAN-INSTALLER\ARM64\INITRD.GZ acpi=force
console=ttyS0,115200n8 earlycon=uart8250,mmio32,0x3f8
ignore_loglevel loglevel=7 ---
```

## Required offline gates

The two scripts in `tools/linux-efi-stub-control/` create only a new fixed VHD
and raw candidate.  They require elevated Windows PowerShell because Windows
must attach the temporary VHD.  They reject existing output paths, verify the
immutable source SHA first, use the normal Windows FAT32 driver, and prove:

- FAT32/CHKDSK is clean;
- launcher, Image and initrd hashes read back exactly;
- BCD remains `B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105`;
- `BOOT.WIM` remains `A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4`;
- direct launcher ARM64 PE and embedded markers/options verify.

No Android transfer, transaction patch generation, or VM launch is permitted
until both scripts print `RESULT=PASS`.

## Runtime interpretation after all offline gates pass

| Observed raw sequence | Meaning |
|---|---|
| no `L0` | UEFI did not enter the replacement boot application |
| `L0`, then `LL` / `LI` / `LO` | specific UEFI loader/configuration failure |
| `L0 L1 L2 L3`, then `LX` | Debian EFI stub returned; capture exact status if available |
| `L0 L1 L2 L3` then EBS marker (`ER`/`BES`) | direct Debian EFI stub reached ExitBootServices |
| Linux earlycon after EBS | Linux kernel early execution observed |
| `L0 L1 L2 L3` then EBS marker and silence | common post-EBS silence remains observed, now without GRUB ambiguity |

Exactly one bounded product-topology runtime may be run only after a separate
transactional-delta audit and baseline verification.  It must roll back to the
immutable Android SHA `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

## v1 runtime — invalid transport execution

One 100-second v1 product-topology run was launched only after the offline
gates and its 23-range transactional patch passed.  The launcher accepted the
patch (the staging file was deleted) and rollback later restored the immutable
Android baseline exactly.  However, the raw serial contains:

```text
AVF_BDS_START_IMAGE \EFI\BOOT\BOOTAA64.EFI fs=0
IMAGE_AUDIT load exit status=Success ... size=2DB000
ER
```

and contains no `L0` marker.  The direct launcher is only 20,480 bytes
(`0x5000`), so the UEFI payload executed in this run was the older GRUB-sized
boot file, not the v1 launcher.  This run is therefore **not a Linux EFI-stub
result** and must not be interpreted as a Linux kernel failure.

The materializer had performed filesystem read-backs and then immediately
read `\\.\PhysicalDriveN` into the raw candidate.  Filesystem read-backs can
be satisfied by the Windows cache; the observed mismatch exposes a missing
flush boundary before the physical-sector copy.  The materializer now requires
a full VHD detach/re-attach before opening the physical device for the raw
copy.  It makes no new filesystem changes during that boundary.

```text
LINUX_DIRECT_EFI_STUB_V1_RUNTIME = INVALID_RAW_TRANSPORT
IMMUTABLE_BASELINE_RESTORED      = PASS
```

Use only `tools/linux-efi-stub-control/prepare-linux-efi-stub-control-v2.ps1`
for the replacement offline candidate.  It uses distinct VHD/raw/report paths
and preserves all v1 evidence.

## v2 runtime — direct EFI-stub milestone

The v2 candidate added the mandatory FAT32 VHD detach/re-attach before raw
sector extraction.  Both v2 materialization and its offline audit passed, then
the 26-range `WAVFPAT1` bundle was validated by an overlay reconstruction
before one 100-second product-topology run.

| Item | Value |
|---|---|
| v2 raw candidate SHA-256 | `48922035CD290A377C7BF54498481A67D36601FD0C96C76D672904E6675BAE33` |
| v2 patch SHA-256 | `C00675252512D82D2D14D4266BC4BA388A50F94A82A9BA345068BB0DAC33DE57` |
| patch bytes / ranges | `218,105,840` / `26` |
| raw serial SHA-256 | `A9926175C71B1D88EE2D1692C580F9BF897C230EB2CF148FED93595B3C40BDFD` |
| raw serial | `build-logs/linux-efi-stub-runtime-v2-20260911-173721/raw-serial.log` |

The decisive raw tail is:

```text
AVF_BDS_START_IMAGE \EFI\BOOT\BOOTAA64.EFI fs=0
IMAGE_AUDIT load exit status=Success ... size=5000
IMAGE_AUDIT start enter ...
L0
IMAGE_AUDIT load exit status=Success ... size=2010000
L1
L2
L3
IMAGE_AUDIT start enter ...
EFI stub: Booting Linux Kernel...
EFI stub: Loaded initrd from command line option
EFI stub: Generating empty DTB
EFI stub: Exiting boot services...
ER
```

`ER` is the existing firmware-side marker after the original
`ExitBootServices()` returned.  Therefore this run establishes:

```text
LINUX_DIRECT_EFI_STUB_LOADED              = PASS
LINUX_DIRECT_EFI_STUB_STARTIMAGE           = PASS
LINUX_EFI_STUB_EXIT_BOOT_SERVICES_RETURN   = PASS
LINUX_KERNEL_EARLY_SERIAL                  = NOT_OBSERVED
COMMON_OS_POST_EBS_SERIAL_SILENCE          = OBSERVED
IMMUTABLE_BASELINE_RESTORED                 = PASS
```

This is not direct evidence of the first native Linux-kernel instruction:
there is no `Linux version`, `earlycon`, or ACPI kernel line after `ER`.
However, it rules out Windows Setup/WinPE and GRUB as necessary explanations
for the post-EBS serial silence.  Do not repeat another Linux/Windows media
variant merely to obtain the same fact.  The next useful investigation must
target the shared post-EBS OS-handoff contract, with a concrete observer or
a concrete platform hypothesis.

## v3 pending — correct the early-console MMIO accessor

The executed v2 launcher asked Linux for
`earlycon=uart8250,mmio32,0x3f8`.  Static platform evidence instead shows the
same UART is used by EDK2 with `PcdSerialUseMmio=TRUE`, default 8-bit register
access width, and stride 1.  Linux's `uart8250,mmio` selects 8-bit access;
`mmio32` selects 32-bit access.  Thus v2's absent Linux text may be an
observer mismatch rather than a native-kernel failure.

The v3 launcher changes **only** that argument to:

```text
earlycon=uart8250,mmio,0x3f8
```

Its completed module-only build has no firmware-FD output and no tablet-side
effect:

| Item | Value |
|---|---|
| Launcher SHA-256 | `F3FEE2904150D53D309D220D3BF4D0F7597B81B63964A496DAB0A51D8B5C1DEE` |
| Launcher bytes | `20,480` |
| ARM64 PE / raw stages / Linux path | PASS |
| Embedded `mmio` option | PASS |
| Embedded `mmio32` option | absent |

Use only
`tools/linux-efi-stub-control/prepare-linux-efi-stub-control-v3-mmio8.ps1`
from an elevated PowerShell window.  It creates distinct disposable VHD/raw
paths, requires the exact immutable baseline hash, performs the mandatory
detach/re-attach raw-sector boundary, and stops after static FAT/asset checks.
The one authorized v3 runtime is complete.  With the corrected accessor, raw
serial contains `Linux version`, `earlycon: uart8250 at MMIO 0x3f8`, ACPI table
enumeration, and the Debian Installer language screen after `ER`.  It therefore
establishes real Linux kernel and userspace execution after EBS on the product
topology.  Full evidence and transaction closure are in
`docs/LINUX_EFI_STUB_V3_MMIO8_RUNTIME_2026-09-11.md`.
