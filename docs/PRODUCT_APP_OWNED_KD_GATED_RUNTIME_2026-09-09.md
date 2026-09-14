# Product app-owned KD: gated control — 2026-09-09

## Scope

This was one bounded product-equivalent diagnostic control after the earlier
ungated serial-KD run let KD synchronization bytes interrupt U-Boot.  It used
the existing app-owned raw bridge and the existing BCD+r11 `WAVFPAT1` bundle;
it did not rebuild the APK, firmware, WIM, BCD candidate, or any Windows
binary.  The external Android source image was never written directly.

The bridge intentionally withheld **all** KD process creation and host-to-guest
bytes until the raw guest serial stream contained `Loading files...`.

## Inputs verified before launch

| Item | SHA-256 |
|---|---|
| immutable product image | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| BCD+r11 combined patch | `4F2EA0AE40E6467608EA753E1368EC3F97C03A4C11DA9B2A17782D62B93742E6` |
| r11 firmware FD range | `9ED3DD035116A39FEAC7C79A9C0C9AC640EA222D499A8EC3B1C6FCEE1ADFE72F` |

The running VM was CID `2118`.  No `kd.exe` process was created during this
run, and therefore there was no serial RX/TX from the debugger.

## Evidence

The raw console capture is
`build-logs/product-kd-gated-runtime-r2-20260909/raw-guest-to-kd.bin`:

| Property | Value |
|---|---|
| length | `1,290,832` bytes |
| SHA-256 | `F9DFDEE4EE72A209204042CB3551F3688C17ADB60B1D3D4B3612FFE8AEC13624` |
| `IMAGE_AUDIT start enter` offset | `1,290,565` |
| `Loading files...` | not present |
| complete `BES` | not present |

The stream contains normal U-Boot output and the late pre-EBS image-audit
sequence.  It ended five bytes before the historical r11 capture's complete
`BES`; the 90-second host gate timeout force-stopped the app at that point.
This control cannot establish a post-EBS regression and must not be compared
as a full EBS failure.

## Result

```text
GATED_NO_PREBOOT_KD_TX          = PASS
UBOOT_AUTOBOOT_NOT_INTERRUPTED  = PASS
PRODUCT_PRE_EBS_NEAR_BES        = PASS
LOADING_FILES_UART_MARKER       = NOT_OBSERVED
KD_RELEASED                     = NOT_PERFORMED
WINDOWS_KD_HANDSHAKE            = NOT_TESTED_BY_GATED_RUN
```

The failure of `Loading files...` as a gate is an observability limitation,
not a Windows/KD conclusion.  A possible next, separately authorized run may
gate on the real late-U-Boot marker `IMAGE_AUDIT start enter`.  That releases
KD before `BES`, avoids U-Boot input, but remains a diagnostic experiment and
may still be too late for a KD handshake.

## Cleanup

The bridge script now force-stops only `com.example.winavf` before requesting
its transactional rollback.  For this actual run cleanup was completed
manually using that proven order.  Final state was:

```text
Running VMs: []
rollback RESULT=PASS
private image SHA = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
external image SHA = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
hidden_api_policy = null
```

