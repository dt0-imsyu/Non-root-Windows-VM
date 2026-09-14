# Shell Windows KD r11 UART-alignment runtime — 2026-09-08

## Scope

One shell-owned, disposable Windows diagnostic VM was launched after r11
proved that installed SPCR and DBG2 both describe the console UART at `0x3F8`.
The product Android image, product BCD/WIM, APK, drivers, and signed Windows
binaries were not changed.

The shell clone retained the already audited BCD candidate:

```text
{default}.bootdebug = Yes
{default}.debug     = Yes
{default}.dbgtransport = kdcom.dll
{dbgsettings}.debugtype = Serial
{dbgsettings}.debugport = 1
{dbgsettings}.baudrate  = 115200
{bootmgr}.bootdebug = absent
```

No BCD variant was introduced in this run.

## Preflight and range transaction

| Item | Result |
|---|---|
| source shell clone | existing disposable `E:\\winavf-kd-shell-kdcom-clone-20260907.img` |
| clone BCD read-back | `034362E7531FF242E32F24F1ABD37EBECA05CC888981D95094E7986A75521784`, exact candidate match |
| `BOOTAA64.EFI` read-back | `EFCC88441775A1ECEF644E05A52D7A01DC98388EA4426F133B9132CBE1483A19`, unchanged |
| r11 patch SHA-256 | `0D78B91BDA1B2C3EB241CF8B1D731280DB511958B3B196662046C76AF7E8364E` |
| local firmware apply | PASS: offset `7,250,927,616`, length `2,097,152`, `3DAF…F995` → `9ED3…FE72F` |
| Android staged raw size | `9,126,805,504` bytes |
| Android staged r11 range | `9ED3DD035116A39FEAC7C79A9C0C9AC640EA222D499A8EC3B1C6FCEE1ADFE72F` |
| Android staged raw SHA-256 | `A57494B11526E5C0730E3AECA2A46D17ECF14AC97FA52968B023A92BEE53ACDE` |

The local clone’s firmware range was restored after the run and reread as
`3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995`.
Its BCD was read again through mtools and still exactly matched the candidate.

## Runtime evidence

The bridge created its named pipe before starting the VM. Shell AVF created
CID `2114` with one vCPU, 4 GiB, and `ttyS0`. The raw serial capture contains
Windows Boot Manager and `Loading files...` (first occurrence at byte offset
`10,247`).

| Artifact | Result |
|---|---|
| bridge status | `PIPE_LISTENING`, `KD_PIPE_CONNECTED`, and `ADB_VM_LAUNCH` all recorded |
| KD → guest bytes | 513 bytes, SHA-256 `18690E3856C7F6598AF5BAC6038218BD6342E6CB22149825BF90FB42A51D04FC` |
| guest UART → bridge bytes | 32,528 bytes, SHA-256 `43C0D14043467EFD7BCA7068FE6F4628784AE1E42244C963F68BB29C33F46D67` |
| independent raw device capture | same 32,528-byte SHA-256 as bridge capture |
| KD transcript | named pipe opened, then `Waiting to reconnect...`; no target packet |
| bounded runner outcome | bridge timeout killed ADB; no crosvm wait-context/EPERM error |

The shell raw capture did **not** reach `BES` within this bounded run. Thus it
proves normal firmware/Boot Manager/`Loading files...` progress and a working
bidirectional bridge, but it does not establish whether this shell clone
reached the product’s post-EBS boundary before timeout.

## Cleanup

The exact remote staging directory was verified to contain the expected
9,126,805,504-byte disposable raw file and then removed:

```text
/data/local/tmp/winavf-kd-shell-r11-align-20260908
STAGING_CLEANUP_PASS
Running VMs: []
```

The immutable product Android source image was independently rehashed after
cleanup and remains the exact baseline:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

## Result

```text
ACPI_DBG2_CONSOLE_ALIGNMENT = PASS
SHELL_KD_COM1_RX_AT_RUNTIME = PASS
SHELL_WINDOWS_BOOT_PATH     = PASS (through Loading files...)
SHELL_EBS_BOUNDARY          = NOT_OBSERVED
WINDOWS_KD_HANDSHAKE        = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY        = UNKNOWN
```

The r11 UART-alignment hypothesis did not yield a KD target packet in this
single diagnostic session. Since the clone did not itself demonstrate `BES`,
this is not evidence that r11 failed after EBS and does not justify another
blind KD retry. The current direct-observability routes remain a working KD
transport that reaches a later target state, or vendor-privileged VMM/GZVM
guest-state tracing.
