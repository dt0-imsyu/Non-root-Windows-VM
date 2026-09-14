# r6 BDS center capture — runtime result (2026-09-06)

## Goal and minimal delta

r5 proved firmware-to-SurfaceView transport with a diagnostic gradient, but its
ordinary GOP capture read the black top-left 320×200 crop. The AVF one-shot
boot policy bypasses the interactive Boot Manager menu, so it cannot be used
to capture that menu without changing policy.

r6 therefore performs the smallest meaningful later-capture A/B:

1. it uses the standard `BootLogoUpdateProgress()` BDS draw primitive;
2. it captures the central 320×200 GOP area where the TianoCore logo and BDS
   progress display are placed;
3. it emits that capture as WAVF sequence 3.

The zero KvmTool BDS timeout is retained. The timer callback is deliberately
not invoked because it divides by the configured timeout. No Windows, WIM,
BCD, GPT/FAT, Android-system, or AVF-launch change was made.

## Build and transactional patch

| Item | Value |
|---|---|
| build log | `build-logs/edk2-r6-bds-center-capture-20260906-151839.log` (`- Done -`) |
| archived FD | `firmware-work/edk2/artifacts/KVMTOOL_EFI-gop-r6-bds-center.fd` |
| FD SHA-256 | `E684D6A5ED1EE9B4C6D74AE37D84FA306D5E3C84246B4B65021C062D5D8D3350` |
| `AVF_BDS_PROGRESS_DRAW` / `AVF_GOP_BDS_FRAME` in linked BdsDxe | PASS |
| patch | `build-logs/gop-poc-20260906/gop-wavf-r6-bds-center-firmware.patch` |
| patch SHA-256 | `4FF51096DFD12E52BCD40FFD561C252D54929D55777551F16B7A02FF2A9DA5A7` |
| raw range | offset `7250927616`, length `2097152` |
| immutable baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| offline forward/rollback simulation | PASS |

The launcher performed its full baseline check, range state/read-back checks,
and post-run rollback verification. Its external staging bundle was removed.

## Runtime evidence

* Screenshot: `build-logs/gop-poc-20260906/runtime-r6-bds-center-screen.png`
* Raw console: `build-logs/gop-poc-20260906/runtime-r6-bds-center-raw-serial.log`
* Raw console SHA-256:
  `2C0F608C50681E92E5AF70A62FF08393D62C5C9D52790EE7758687BEFA5944FC`

The real Android SurfaceView visibly showed the TianoCore logo. The raw stream
contains all three firmware markers:

```text
AVF_GOP_FRAME status=Success size=320x200
AVF_GOP_DIAG_FRAME status=Success size=320x200
AVF_BDS_PROGRESS_DRAW status=Success
AVF_GOP_BDS_FRAME status=Success size=320x200
```

| WAVF sequence | Offset | CRC | Unique colors | Non-black pixels | Meaning |
|---:|---:|---|---:|---:|---|
| 1 | 4,747 | `0xB9796E7D` PASS | 1 | 0 | old top-left capture remains black |
| 2 | 260,818 | `0x4EE2982C` PASS | 51,200 | 64,000 | r5 diagnostic gradient |
| 3 | 516,932 | `0xC92231D9` PASS | 65 | 11,194 | actual central TianoCore/BDS splash UI |

## Result

```text
GOP_BDS_PROGRESS_DRAW = PASS
REAL_GOP_BDS_CENTER_CAPTURE = PASS
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

The pre-EBS graphics transport, decoder, presenter, and a real UEFI BDS UI
capture are all proven. The next graphics work should be a bounded repeated
capture/update policy, rather than further one-shot capture diagnostics.
