# Windows 11 IoT LTSC 2024 Setup A/B — 2026-09-10

## Scope

One bounded Windows-media-only A/B was run to test whether an older official
ARM64 WinPE/Setup medium reaches the installer on the unchanged app-owned
WinAVF topology.  The immutable Android image, BCD, firmware, Android app and
all signed Windows files other than `\SOURCES\BOOT.WIM` were left unchanged.

## Inputs and offline gates

| Item | Value | Result |
| --- | --- | --- |
| immutable product baseline | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` | PASS before and after |
| LTSC ISO | `26100.1742...CLIENT_IOT_LTSC_EVAL_A64FRE_en-us.iso` | mounted read-only |
| LTSC `boot.wim` | `375DF1744A6D49836D91181D4C85450D9EEB15F8BF8C06AC25622FD5F0DD467B` | exact |
| candidate raw | `E8F36F62B01A3F9E581FE632EC1231FA85CC99060FE9F57D967B29B6F781DAAD` | exact |
| candidate geometry | offset `1048576`, FAT32 length `9125740032` | PASS |
| CHKDSK | FAT32 clean | PASS |
| WIM verification | `wimlib verify` | PASS |
| WIM index 2 | ARM64 Microsoft Windows Setup, build `26100.1742` | readable |
| `BOOTAA64.EFI` / BCD | read-back unchanged during materialization | PASS |
| reversible patch | `B01F8363EE3192DB09C8BC9B1E19B299B7EA44BD59100ECA618192288444CE97` | 1,149,249,764 bytes, 137 ranges |
| patch overlay | baseline -> candidate | PASS |
| rollback overlay | candidate -> baseline | PASS |

The candidate was created through a disposable fixed VHD and the normal
Windows FAT32 driver.  No manual FAT mutation or WIM rebuild was used.

## One runtime

The launcher first verified the device baseline SHA, then created an
app-private clone, applied the patch, ran for 120 seconds, stopped the clone,
collected evidence, and deleted the clone.

Raw serial SHA-256:

```text
DA8DB3EF2B5221FAAF9ABC98A771546FC9DF540D881F4B5851B613AE025EDFF2
```

The serial evidence reaches the unchanged firmware's successful
`AVF_BDS_START_IMAGE \EFI\BOOT\BOOTAA64.EFI` / `IMAGE_AUDIT start enter`
path, then ends after its existing conversion-audit requests.  It does **not**
contain `Loading files...`, `BES`, or `ER`.

The stopped-clone audit reported:

```text
PERSISTENT_WINDOWS_SETUP_WITNESS=NOT_OBSERVED
WINDOWS_KERNEL_EXECUTION_AFTER_EBS=NOT_OBSERVED
NEGATIVE_INTERPRETATION=NO_PERSISTENT_ARTIFACT_DOES_NOT_PROVE_NO_KERNEL_EXECUTION
```

That witness is intentionally not interpreted as proof that the kernel did
not execute: this A/B did not reach the known post-EBS serial boundary.

Cleanup passed:

```text
DISPOSABLE_PRIVATE_CLONE_DELETED=PASS
IMMUTABLE_BASELINE_SHA256=2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
RESULT=PASS
```

## Classification

```text
LTSC_26100_1742_SETUP_MEDIA = INCOMPATIBLE_BEFORE_KNOWN_EBS_BOUNDARY
WINDOWS_SETUP_INSTALLER     = NOT_REACHED
IMMUTABLE_BASELINE_RESTORED = PASS
```

This does not identify a defect inside the LTSC WIM.  It establishes only that
the controlled substitution of the 26100.1742 `boot.wim`, with the current
firmware/BCD/platform kept fixed, regresses before the known-good medium's
`Loading files... -> EBS/ER` path.

## Stop point

Do not try additional WIM releases or compression variants.  Return to the
known-good 25H2 medium for any later Windows run.  The next experiment must be
a separately authorized, semantically earlier Windows/platform observer or a
different boot class such as an installed-system disk; it is not another Setup
WIM swap.

## Artifacts

* `C:\Users\denis\MainProjects\win11ontab\build-logs\ltsc-setup-ab-20260910`
* `C:\Users\denis\MainProjects\win11ontab\build-logs\ltsc-setup-runtime-20260910`
