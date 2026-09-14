# r5 diagnostic GOP frame — runtime result (2026-09-06)

## Scope

One pre-EBS firmware-only A/B was run against the immutable WinAVF media
baseline. No Windows files, WIM, BCD, GPT/FAT metadata, Android system state,
or AVF launch architecture changed.

The sole firmware source delta is in
`firmware-work/edk2/ArmPkg/Library/PlatformBootManagerLib/PlatformBm.c`:
after the existing real GOP capture, it writes a 320×200 BGRA diagnostic
gradient through GOP `EfiBltBufferToVideo`, emits that buffer as WAVF sequence
2, then restores the captured pixels before returning.

## Reproducible build

`tools/build-r4-replay-edk2.ps1` reproduced the recorded r4 tool environment:
Win64 BaseTools packaging binaries, Win32 `Trim.cmd`, bundled llvm-mingw
Python, GCC 15.2, MSYS `mingw32-make`, `cmd.exe`, and the two recorded wrappers
(`objecho.cmd`, path-preserving `iasl-msys.cmd`).

| Item | Result |
|---|---|
| r4 control replay | PASS; `build-logs/edk2-r4-replay5-20260906-145758.log` ends `- Done -` |
| r5 build | PASS; `build-logs/edk2-r5-gop-diag-20260906-150250.log` ends `- Done -` |
| archived FD | `firmware-work/edk2/artifacts/KVMTOOL_EFI-gop-r5-diagnostic.fd` |
| FD size | 2,097,152 bytes |
| FD SHA-256 | `3EAFC9C2086ADCF0375AA14A947E482CB86BE6A1D2AAA105C974DBB2671EFF00` |
| linked BdsDxe UTF-16 `AVF_GOP_DIAG_FRAME` | PASS (offset 78,742) |

## Transactional deployment

The patch is one firmware range only, at offset `7250927616`, length
`2097152`. Its embedded immutable baseline SHA-256 is
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

| Item | Value |
|---|---|
| patch | `build-logs/gop-poc-20260906/gop-wavf-r5-diagnostic-firmware.patch` |
| patch size | 4,194,436 bytes |
| patch SHA-256 | `5AD2B2ED3384A546687F7E450943A9EEF6BF496D2AA5405F47914B5577678424` |
| forward firmware SHA-256 | `3EAFC9C2086ADCF0375AA14A947E482CB86BE6A1D2AAA105C974DBB2671EFF00` |
| embedded rollback firmware SHA-256 | `3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995` |
| offline range/forward/rollback audit | PASS |

The launcher accepted the baseline, performed its per-range read-back check,
and applied the patch. After the sole VM run, rollback was invoked immediately;
the launcher reported: `Small image patch rolled back and the runtime image was
verified.` The staging patch no longer exists on the device.

## Runtime evidence

Captured raw console file:
`build-logs/gop-poc-20260906/runtime-r5-diagnostic-raw-serial.log`

* Size: 522,329 bytes
* SHA-256: `F8BED44344989446AA5F5B1FC9DB686E2E41A1E554A25FFAEA14B9D3C84F196F`
* Firmware markers: `AVF_GOP_FRAME status=Success size=320x200` and
  `AVF_GOP_DIAG_FRAME status=Success size=320x200`

| WAVF frame | Offset | Sequence | CRC | Pixel evidence |
|---|---:|---:|---|---|
| original GOP capture | 4,745 | 1 | `0xB9796E7D` = calculated CRC | all pixels `00 00 00 FF` |
| r5 diagnostic GOP frame | 260,816 | 2 | `0x4EE2982C` = calculated CRC | B=0..255, G=0..255, R=128; 51,200 distinct BGRA pixels |

`runtime-r5-diagnostic-screen.png` visibly shows that second gradient inside
the real app-owned SurfaceView. It is a real firmware GOP-originated frame,
not the synthetic decoder audit.

## Result

```text
R4_BUILD_ENV_REPLAY = PASS
NEW_GOP_FD_BUILD = PASS
GOP_WAVF_RAW_CONSOLE_EXPORT = PASS
HOST_FRAME_DECODE = PASS
SURFACEVIEW_PRESENTATION = PASS
REAL_GOP_NONBLACK_FRAME = PASS
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

The next graphics experiment should capture an actual non-black Boot Manager
UI frame later in BDS; transport and presentation are now closed.
