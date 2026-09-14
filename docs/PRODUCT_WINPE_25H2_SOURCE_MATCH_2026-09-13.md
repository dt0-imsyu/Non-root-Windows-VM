# Product WinPE source-match audit — 2026-09-13

## Result

```text
PRODUCT_WINPE_25H2_SOURCE_MATCH = PASS
```

The locally available official ARM64 ISO
`26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENT_CONSUMER_A64FRE_ru-ru.iso`
was mounted read-only and immediately detached. Its Windows Setup boot chain
matches the immutable product baseline's known critical hashes:

| ISO path | Bytes | SHA-256 | Product result |
| --- | ---: | --- | --- |
| `\sources\boot.wim` | 623,400,308 | `A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4` | exact baseline WIM |
| `\efi\boot\bootaa64.efi` | 2,698,184 | `EFCC88441775A1ECEF644E05A52D7A01DC98388EA4426F133B9132CBE1483A19` | exact baseline boot application |
| `\efi\microsoft\boot\bcd` | 16,384 | `B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105` | exact baseline BCD |
| `\boot\boot.sdi` | 3,170,304 | `CD2C00CE027687CE4A8BDC967F26A8AB82F651C9BECD703658BA282EC49702BD` | retained source identity |

`wimlib-imagex info` identifies ISO index 2 as ARM64 Windows Setup,
WindowsPE build `26100.6584`, the same exact WIM identified in the baseline.

## Meaning

The product is already booting the current official 25H2-family ARM64 WinPE
payload rather than an old or accidentally rebuilt WIM. Replacing the WIM from
this ISO would be a byte-identical no-op; another Setup-WIM substitution cannot
advance `WINDOWS_POST_EBS` or `WINPE`.

This audit made no image, firmware, BCD, Android, or VM change.
