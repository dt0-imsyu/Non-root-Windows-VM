# r9 SetVirtualAddressMap runtime evidence — 2026-09-06

This is evidence collection for the already completed single r9 runtime. No
second VM run, patch re-application, FD build, Windows-media/WIM/BCD change, or
Android APK change was performed.

## Evidence

| item | value |
|---|---|
| raw serial log | `build-logs/runtime-va-r9-20260906/runtime-r9-raw-serial.log` |
| evidence copy | `build-logs/runtime-va-r9-20260906/runtime-r9-raw-serial.evidence.log` |
| device source | `/sdcard/Android/data/com.example.winavf/files/serial.log` |
| raw size | `1,290,719` bytes |
| raw/evidence/device SHA-256 | `38600F70A9333A5529B3398F25524DB3D972D11C306C97DDCF06924404E696FE` |
| r9 FD size | `2,097,152` bytes |
| r9 FD SHA-256 | `EB023DF0CA527F6E428D5B0CCE87CC67895B4C69443B64661CE7FAD4BD65C346` |
| patch SHA-256 | `54CC7498867ADFD29AE82320FCEC17FE338B29E69D6E3D9B389E1981DD2AD124` |
| patch range | offset `7250927616`, length `2097152` |

The raw log was captured through the launcher\'s direct `getConsoleOutput()`
reader: each raw byte block is written and flushed before the separate UTF-8
preview or WAVF decoder receives it. A later read-only device check found the
same length and SHA-256 while the VM remained alive. Its final bytes are
`42 45 53` (`BES`) at zero-based offsets `1290716..1290718`, with no following
output. This is an observation boundary, not a text/line-buffering loss.

## Markers

The complete-marker/token scan of the captured raw bytes found:

| marker | captured result |
|---|---|
| `BES` | observed: EBS wrapper entry, RuntimeDxe EBS event, original EBS success return |
| `VA0` | not observed |
| `VA1` | not observed |
| `VA2` | not observed |

`VA2` was intentionally not emitted because UART safety after conversion has
not been established. `VA0` is the first executable action in
`RuntimeDriverSetVirtualAddressMap()`, before validation, virtual-map globals,
or pointer conversion. Since the proven raw capture remained unchanged after
`BES`, the bounded r9 run did not enter SetVirtualAddressMap.

```text
POST_EBS_SET_VIRTUAL_ADDRESS_MAP = NOT_OBSERVED
VIRTUAL_ADDRESS_CHANGE            = NOT_OBSERVED
RESULT                            = PASS (negative observation)
```

## Rollback

The checked launcher rollback path was invoked with rollback extra only:

```text
adb shell am start -S -n com.example.winavf/.MainActivity --ez rollback true
```

The launcher displayed:

```text
Small image patch rolled back and the runtime image was verified.
```

Rollback UI evidence is saved at
`build-logs/runtime-va-r9-20260906/runtime-r9-after-rollback-ui.xml` with SHA-256
`C3B875CED945314C98C8FA68EBC786C363F20028140DB5A9A3E165782BFDB3E3`.

An independent full SHA-256 check after rollback returned:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

This matches the expected immutable baseline exactly.

## Short runtime report

The sole r9 run reached `BES`; `B` is wrapper entry, `E` is the existing
RuntimeDxe ExitBootServices event, and `S` is the successful return from the
original ExitBootServices call. `VA0` and `VA1` were absent, while the direct
raw console capture remained byte-identical on a later read-only device check.
The result is therefore a conclusive negative observation for this run; no
second runtime was started. The r9 firmware range was rolled back through the
existing launcher, and the complete post-rollback baseline SHA-256 was
independently verified.
