# r7 pre-EBS BDS progress capture sequence — 2026-09-06

## Scope

One bounded, firmware-only runtime test. It extends the already-proven r6
centered GOP capture with three real `BootLogoUpdateProgress()` calls at 0,
50, and 100 percent. Each call is followed by one centered 320x200 GOP/WAVF
capture. No Android code, Windows image, WIM, BCD, boot policy, or host AVF
configuration changed.

## Build and static audit

The exact replay script `tools/build-r4-replay-edk2.ps1` completed top-level
packaging in `build-logs/edk2-r7-bds-progress-sequence-20260906-190026.log`:
`- Done -` at 19:04:41 (total 00:04:14).

| item | value |
|---|---|
| FD | `firmware-work/edk2/artifacts/KVMTOOL_EFI-gop-r7-bds-progress-sequence.fd` |
| FD size | 2,097,152 bytes |
| FD SHA-256 | `89C613111F3E7814AFDE1331A24FFE952D6575D6A9455F80F2A8A7B2BC88A7B6` |
| source | `firmware-work/edk2/ArmPkg/Library/PlatformBootManagerLib/PlatformBm.c`, lines 1530 and 1586–1603 |
| packed BdsDxe markers | UTF-16 `AVF_BDS_PROGRESS_DRAW[` and `AVF_GOP_BDS_FRAME seq=` both present |

The source calls the standard BDS drawing primitive, then captures the center:

```text
BootLogoUpdateProgress(..., 0/50/100, ...)
  -> AVF_BDS_PROGRESS_DRAW[n] status=Success
  -> AvfEmitGopKeyframe(..., sequence 3/4/5, centered crop)
```

## Transactional patch audit

| item | value |
|---|---|
| immutable baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| patch | `build-logs/gop-poc-20260906/gop-wavf-r7-bds-progress-sequence-firmware.patch` |
| patch size | 4,194,436 bytes |
| patch SHA-256 | `6D25228972E117AF7A0A0B5763B18C46BE9FDE7E504166B03AEEE013F1A29660` |
| changed ranges | one: raw offset `7250927616`, length `2097152` |
| old range SHA-256 | `3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995` |
| new range SHA-256 | `89C613111F3E7814AFDE1331A24FFE952D6575D6A9455F80F2A8A7B2BC88A7B6` |

The patch header, embedded old/new payload digests, forward substitution, and
rollback simulation all passed before staging. The device-side staging SHA
matched the local patch SHA before the single launch.

## Single runtime result

Raw console capture:
`build-logs/gop-poc-20260906/runtime-r7-bds-progress-sequence-raw-serial.log`
(1,290,700 bytes, SHA-256
`0049B4E8BE7EF31AEC180934ED137A9D2207B9C88D62D54540E2EB1478F0C3D2`).

| sequence | CRC | CRC pass | payload SHA-256 | interpretation |
|---:|---|---|---|---|
| 1 | `B9796E7D` | PASS | `846F860302BB0486601324E073C35FB69C413B5C9237CF1152BF151A055D3F90` | original early black crop |
| 2 | `4EE2982C` | PASS | `DF283B66CBB817AE325B1FA32B2F89D19AEC3DC519AFF871D87DE70EB0D87389` | r5 diagnostic frame |
| 3 | `C92231D9` | PASS | `F6AD1B388BF777F7FEB1FA8841DEEE9BA278F3C33F7B3F51E55E84195BFBF4B4` | BDS progress 0 |
| 4 | `C92231D9` | PASS | `F6AD1B388BF777F7FEB1FA8841DEEE9BA278F3C33F7B3F51E55E84195BFBF4B4` | BDS progress 50 |
| 5 | `C92231D9` | PASS | `F6AD1B388BF777F7FEB1FA8841DEEE9BA278F3C33F7B3F51E55E84195BFBF4B4` | BDS progress 100 |

All six firmware status markers were present and successful: progress draws at
0, 50, and 100; captures at sequences 3, 4, and 5. The Android screenshot
`runtime-r7-bds-progress-sequence-screen.png` (SHA-256
`46054131822289DE009508C62871C51DFE69343258BB305ADC6AE1FC1CEEC4FD`)
visibly shows the real TianoCore logo in the app-owned SurfaceView.

The three BDS payloads are intentionally reported as identical, not as an
animation failure: the centered 320x200 crop contains the logo but not the
progress-bar area. Therefore this run proves repeatable pre-EBS delivery,
but does not prove a visual delta for BDS progress.

```text
PRE_EBS_REPEATED_FRAME_TRANSPORT = PASS
BDS_PROGRESS_FRAME_SEQUENCE = NOT_CONFIRMED
BDS_PROGRESS_VISUAL_DELTA = NOT_CONFIRMED (center crop unchanged)
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

## Rollback

Immediately after the capture, the app's rollback action restored the one
range and removed the staged bundle. A full device SHA-256 check again
returned the immutable baseline hash. Screenshot:
`runtime-r7-after-rollback-screen.png` (SHA-256
`164D8757957564FE265F4C052909DBF6F34232FB819CD1D8BAF4771443EFE8AD`).

## Next bounded experiment

Do not alter the transport. If a progress animation is needed, make one
separate firmware-only capture-window experiment that includes the actual BDS
progress bar (for example a lower crop), then repeat the same one-run,
one-range rollback procedure.
