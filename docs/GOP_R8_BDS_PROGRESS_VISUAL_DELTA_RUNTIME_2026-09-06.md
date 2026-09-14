# r8 BDS progress visual-delta runtime — 2026-09-06

## Scope

This is the smallest follow-up to r7. It changes only the BDS WAVF capture
origin from a centered crop to bottom-center (`SourceY = vertical resolution -
200`). The standard `BootLogoUpdateProgress()` calls at 0, 50, and 100,
WAVF protocol, Android decoder, launcher, Windows media, BCD, and AVF setup
remain unchanged.

The coordinate is derived directly from the standard BootLogoLib implementation:
it places the bar at `SizeOfY * 48 / 50`. The new 320x200 crop includes that
lower display region.

## Build and patch audit

| item | value |
|---|---|
| build log | `build-logs/edk2-r8-bds-bottom-progress-sequence-20260906-191852.log` |
| build result | `- Done -`, 00:03:30 |
| FD | `firmware-work/edk2/artifacts/KVMTOOL_EFI-gop-r8-bds-bottom-progress-sequence.fd` |
| FD size | 2,097,152 bytes |
| FD SHA-256 | `86ADD5C3A7AE143E182584F81332B87848D9C2DEA36E246F98ED3037DD4835DE` |
| static packed marker | UTF-16 `AVF_GOP_BDS_BOTTOM_FRAME seq=` present in `BdsDxe.efi` |
| immutable baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| patch | `build-logs/gop-poc-20260906/gop-wavf-r8-bds-bottom-progress-sequence-firmware.patch` |
| patch size | 4,194,436 bytes |
| patch SHA-256 | `75CD37272FE7C4FA1D1212831B9E55FCC593D50EE8DC94BBA1477B532D071E48` |
| changed ranges | one: raw offset `7250927616`, length `2097152` |
| old range SHA-256 | `3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995` |
| candidate range SHA-256 | `86ADD5C3A7AE143E182584F81332B87848D9C2DEA36E246F98ED3037DD4835DE` |

Patch header, embedded old/new range hashes, forward substitution, and rollback
simulation passed. The device-side baseline SHA matched before staging; its
staged-patch SHA exactly matched the local patch SHA.

## Single runtime result

Raw capture:
`build-logs/gop-poc-20260906/runtime-r8-bds-bottom-progress-sequence-raw-serial.log`
(1,290,721 bytes, SHA-256
`45BD8D2BA35016A3203CA410DCA842D72E92FC6142C270A85F831F123B2F70B3`).

| sequence | CRC | CRC pass | payload SHA-256 | event |
|---:|---|---|---|---|
| 3 | `E765209A` | PASS | `4940234AEBA8C12A054CCA97F65959023CF9E6135D981BD4C94566915CBF83D0` | BDS progress 0 |
| 4 | `292DDEA0` | PASS | `3F4E58654F99D4491066F5D7AF04D262D670DDAE1F7D6FCF3FC0BCEF00D5BFAE` | BDS progress 50 |
| 5 | `06BF11FA` | PASS | `FB31A81164BC396B33F41D703BF60E7FF657E51DC6BFE226BED1F3EE9F046A7D` | BDS progress 100 |

All six relevant firmware markers are present with `status=Success`:
`AVF_BDS_PROGRESS_DRAW[0/50/100]` and
`AVF_GOP_BDS_BOTTOM_FRAME seq=3/4/5`.

The payload SHA-256 values are all distinct. This proves that the existing
firmware GOP capture, raw-console transport, Android decoder, and SurfaceView
present separate real BDS visual states. The screen capture visibly shows
`Press ESCAPE for boot options` and the 100% white progress bar:
`runtime-r8-bds-bottom-progress-sequence-screen.png` (SHA-256
`2C260539BE53712D638DBBFCE0DFB90FC8D93E094D127BD4EE05744A3C55765F`).

```text
BDS_PROGRESS_FRAME_SEQUENCE = PASS
BDS_PROGRESS_VISUAL_DELTA = PASS
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

## Rollback

Immediately after the only runtime capture, the launcher restored the original
2 MiB range and removed the staged patch. A full SHA-256 check of the tablet
runtime image again returned
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
The rollback UI screenshot is
`runtime-r8-after-rollback-screen.png` (SHA-256
`88210C3B2303EF0C175723AA4CA726F12160DD8C3B9A965E283C064D2A97DBC9`).

## Result and next boundary

The complete early graphical sequence is now proven, from real EDK2 GOP draw
through raw AVF console transport to the app-owned SurfaceView. The next
separate product decision is how to schedule/capture ongoing pre-EBS GOP
updates without making this one-shot diagnostic path into a broad firmware
subsystem.
