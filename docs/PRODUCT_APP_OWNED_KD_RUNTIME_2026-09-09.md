# Product app-owned serial KD runtime — 2026-09-09

## Scope

One bounded 100-second diagnostic VM run used the real app-owned WinAVF AVF
topology. The immutable external Android image, WIM, signed Windows binaries,
drivers, and Android system software were not changed. The app applied a
reversible private-image `WAVFPAT1` transaction only after its baseline hash
check.

## Offline transaction

| Item | Value |
|---|---|
| immutable baseline | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| read-only baseline BCD | `B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105`, 16,384 bytes |
| serial-KD BCD candidate | `DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11`, 20,480 bytes |
| BCD-only patch | `9E4681DE41146DAEA02E9458758C7D5AD82533EF478FF527636100DCEDD05A72`, 5 ranges; reverse rollback overlay PASS |
| existing r11 patch | `0D78B91BDA1B2C3EB241CF8B1D731280DB511958B3B196662046C76AF7E8364E` |
| merged BCD+r11 patch | `4F2EA0AE40E6467608EA753E1368EC3F97C03A4C11DA9B2A17782D62B93742E6`, 6 non-overlapping ranges |

The BCD was replaced only through an isolated fixed VHD and the normal Windows
FAT driver. The raw delta builder did not parse or modify FAT.

## Transport result

Before VM launch, the host recorded the exact baseline and patch hashes,
`KD_PIPE_CONNECTED`, and `ANDROID_BRIDGE_AUTHENTICATED`. The CID 2117 VM
exchanged raw bytes in both directions:

| Direction | Bytes | SHA-256 |
|---|---:|---|
| KD → guest | 1,178 | `2160748EEB0EE006FE192B2569443F3281E8365E01A2FB67259B95381B674456` |
| guest → KD | 1,257 | `2E7B16A6BF75017069D1185C5346DB5B8E822F0B35D795AB8411FAA4D15694C0` |

## Result

The initial KD synchronization bytes reached `ttyS0` while U-Boot still owned
serial input. The capture shows:

```text
Hit any key to stop autoboot: 2 ... 0
=>
```

followed by debugger-originated input interpreted as U-Boot console text.
Autoboot was interrupted. EDK2, Windows Boot Manager, `BES`, and Windows KD
could therefore not be reached. `kd.exe` opened its pipe then waited to
reconnect, with no target packet.

```text
KD_HOST_NAMED_PIPE              = PASS
PRODUCT_APP_KD_BRIDGE           = PASS
APP_OWNED_BINARY_COM1           = PASS
PREBOOT_SERIAL_COLLISION        = PASS
WINDOWS_BOOT_MANAGER_THIS_RUN   = NOT_REACHED
EXIT_BOOT_SERVICES_THIS_RUN     = NOT_REACHED
WINDOWS_KD_HANDSHAKE            = INCONCLUSIVE
```

This is not evidence of a Windows kernel failure: Windows was not booted in
this run.

## Cleanup

The initial stop intent was delivered to a second Activity instance, so it did
not see the bridge VM. No second VM was started. The one diagnostic VM was
stopped by force-stopping only WinAVF, followed by a separate rollback:

```text
Running VMs: []
rollback RESULT=PASS
private runtime SHA = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
external runtime SHA = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
hidden_api_policy = null
```

The APK now handles `onNewIntent()` and resolves the VM by name for stop and
rollback. That lifecycle-only fix was built and installed; it was not tested by
another VM run.

## One next test, not run

Gate all KD TX until a post-U-Boot guest-output marker such as `Loading
files...` appears. Do not start `kd.exe` or release its bytes earlier. This is
a separate runtime authorization because it requires another BCD+r11 product
diagnostic run.

Raw artifacts: `build-logs/product-kd-runtime-20260909/`.
