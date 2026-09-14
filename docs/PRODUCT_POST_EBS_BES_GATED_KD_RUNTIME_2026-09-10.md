# Product Windows KD gated on post-EBS `BES` — 2026-09-10

## Objective

Run one product-equivalent Windows KD diagnostic without sending a debugger
byte before the existing raw post-original-`ExitBootServices()` marker `BES`.
This was intended to separate the known U-Boot/pre-EBS serial ownership from a
possible Winload/kernel KD response.

No new firmware, WIM, driver, Android app, or BCD variant was created.  The
existing reversible merged BCD+r11 patch was used exactly as built.

## Exact inputs

| Item | Value |
| --- | --- |
| immutable Android image SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| merged BCD+r11 patch SHA-256 | `4F2EA0AE40E6467608EA753E1368EC3F97C03A4C11DA9B2A17782D62B93742E6` |
| patch size | 46,137,856 bytes |
| r11 firmware SHA-256 | `9ED3DD035116A39FEAC7C79A9C0C9AC640EA222D499A8EC3B1C6FCEE1ADFE72F` |
| gate | exact raw ASCII `BES` |
| gate bound | 150 seconds |
| KD window after gate | 100 seconds (not entered) |

`BES` was verified to occur once in the historical r11 raw serial evidence,
at the tail after the two final `CONVERT_AUDIT` records.  The app-owned bridge
was authenticated before VM start but deliberately withheld both `kd.exe` and
all host-to-guest traffic while waiting for that marker.

## Runtime result

The private transaction and app-owned VM started successfully.  The raw guest
stream reached the known Windows Boot Manager load/start path:

```text
AVF_BDS_START_IMAGE \\EFI\\BOOT\\BOOTAA64.EFI
IMAGE_AUDIT load enter
CONVERT_AUDIT ... 0x10000000 ... Not Found
IMAGE_AUDIT load exit
IMAGE_AUDIT start enter
CONVERT_AUDIT ... 0x00102000 ... Not Found
```

It did not reach `BES` within the 150-second bound.  Therefore the gate never
opened, `kd.exe` was never created, and host-to-guest KD traffic was exactly
zero bytes.  This is not a KD handshake failure: the test's post-EBS
precondition was not met in the BCD-debug-enabled boot path.

```text
BES_GATE_OBSERVED               = NOT_OBSERVED
POST_EBS_KD_TX                  = NOT_STARTED
POST_EBS_KD_HANDSHAKE           = NOT_TESTED
BCD_DEBUG_PATH_REACHED_EBS      = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY            = UNKNOWN
```

## Cleanup and evidence

The app reported transactional rollback `PASS`; the external immutable image
was independently rehashed exact afterwards.  No VM remains and the temporary
hidden API policy was restored to `null`.  The staged patch was removed.

| Artifact | Value |
| --- | --- |
| artifact directory | `build-logs/product-kd-bes-gated-runtime-20260910-215529/` |
| guest raw RX | 1,290,832 bytes, `F9DFDEE4EE72A209204042CB3551F3688C17ADB60B1D3D4B3612FFE8AEC13624` |
| guest KD TX | 0 bytes, `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |
| rollback report SHA-256 | `53EF416025880876230E6B222828C06076ED45432312FA4616327581EE5F8F36` |

Two earlier host attempts terminated before a VM was created: first due to a
missing explicit standard PowerShell module import, then due to a .NET 6-only
hex helper.  The runner was made Windows-PowerShell-5.1-compatible and made
the harmless absence of an old adb-forward listener non-fatal.  These are
host-only fixes; they do not change the tested media or firmware.

## Conclusion

The desired post-EBS gate is technically valid, but the existing serial-KD
BCD candidate itself does not reproduce the known product EBS boundary in the
bounded run.  Repeating it cannot answer the original kernel question and
would merely repeat the same precondition failure.

Do not reopen BCD/KD variants from this result.  The next investigation must
use a Windows/platform observer that does not require changing the known-good
product boot path before EBS.
