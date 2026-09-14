# WinAVF product KD handoff — 2026-09-09

This is the authoritative continuation note for the next session.  It records
what is proven, the exact files and commands, and the safety contract.  Do not
run another VM merely to re-discover these facts.

## Current exact state

```text
PRODUCT_IMAGE_BASELINE                         = PASS
EXIT_BOOT_SERVICES_RETURN                      = PASS (historical r11 `BES`)
ACPI_DBG2_CONSOLE_ALIGNMENT                    = PASS (SPCR=DBG2=0x3f8)
APP_OWNED_BINARY_TRANSPARENT_COM1              = PASS
KD_HOST_NAMED_PIPE                             = PASS
PRODUCT_APP_KD_BRIDGE                           = PASS
PREBOOT_SERIAL_COLLISION                        = PASS (ungated control)
GATED_NO_PREBOOT_KD_TX                          = PASS
IMAGE_AUDIT_GATE_OBSERVED                       = PASS
LOADING_FILES_UART_MARKER                       = NOT_OBSERVED
WINDOWS_KD_HANDSHAKE                            = NOT_OBSERVED
```

The real product diagnostic route is now:

```text
kd.exe named pipe
  <-> adb forward tcp:39100
  <-> raw localhost socket authenticated by one random token
  <-> WinAVF getConsoleInput()/getConsoleOutput()
  <-> crosvm ttyS0 / 16550 at 0x3f8
  <-> r11 SPCR and DBG2 at 0x3f8
```

Update: the fixed bridge was subsequently run once.  It observed the
`IMAGE_AUDIT start enter` gate, opened `kd.exe` and exchanged 450 host KD bytes
after that gate, but received no target KD packet and no complete `BES`.
Rollback restored the exact product baseline.  Therefore the current status
is `WINDOWS_KD_HANDSHAKE = NOT_OBSERVED`, not merely untested.  Full evidence:
`docs/PRODUCT_APP_OWNED_KD_IMAGE_AUDIT_RUNTIME_2026-09-09.md`.

There is no PTY, Base64, text conversion, or line discipline after the short
ASCII capability-token handshake.  The disposable echo run returned an exact
4,096-byte `00..FF` ×16 pattern including NUL and high-bit bytes.  See
`docs/APP_OWNED_BINARY_CONSOLE_LOOPBACK_RUNTIME_2026-09-09.md`.

## Device and immutable baseline

Android device package: `com.example.winavf`.

```text
external source image:
/sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img

SHA-256:
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

At handoff the verified live state is `Running VMs: []`, hidden API policy is
`null`, and the external image is the exact baseline.  The app copies this
external source into private storage.  A patch is applied only to that private
copy and is rolled back there.  Never write Android physical blocks and never
overwrite the external source image.

Read-only baseline check:

```powershell
$adb = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb shell 'sha256sum /sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img; vm list; settings get global hidden_api_policy'
```

## Artifacts that are already complete

| Item | Path | SHA-256 |
|---|---|---|
| APK currently built and installed | `android-app/out/WinAVF-test.apk` | `82A6CD8E7C5EC6BA818B9D33D8DFB6D64579EECA6F703B2AEF22983EE6480511` |
| r11 FD | `C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\artifacts\KVMTOOL_EFI-r11-debug-uart-align.fd` | `9ED3DD035116A39FEAC7C79A9C0C9AC640EA222D499A8EC3B1C6FCEE1ADFE72F` |
| r11 one-range patch | `build-logs/runtime-debug-uart-r11-20260908/runtime-r11-debug-uart-align-firmware.patch` | `0D78B91BDA1B2C3EB241CF8B1D731280DB511958B3B196662046C76AF7E8364E` |
| read-only product BCD | `build-logs/product-kd-preflight-20260909/product-bcd-readonly.bin` | `B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105` |
| serial-KD BCD candidate | `build-logs/shell-windows-kd-bootmgr-runtime-20260907/mtools/BCD.source-current` | `DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11` |
| BCD-only patch | `build-logs/product-kd-preflight-20260909/product-kd-bcd-only.patch` | `9E4681DE41146DAEA02E9458758C7D5AD82533EF478FF527636100DCEDD05A72` |
| merged BCD+r11 patch | `build-logs/product-kd-preflight-20260909/product-kd-r11-combined.patch` | `4F2EA0AE40E6467608EA753E1368EC3F97C03A4C11DA9B2A17782D62B93742E6` |

The BCD candidate enables debug and bootdebug only under `{default}`, uses
serial port 1 at 115200, and is 20 KiB.  **Do not add `{bootmgr}` bootdebug.**
That older variation changes early Boot Manager behaviour.  Do not attempt to
persist `dbgtransport kdcom.dll`; the current store does not retain it and no
such change is required for the next run.

The merged patch has 6 non-overlapping ranges and 46,137,856 bytes.  It was
made from a fixed VHD using the ordinary Windows FAT driver—not by custom FAT
editing.  Its transaction and rollback overlay audits pass.

## Last two controls

1. Ungated product run: raw KD bytes reached guest COM1 but U-Boot consumed
them, printed `Hit any key to stop autoboot`, and dropped to `=>`.  Windows
never ran.  This proves the bridge, not KD.  Evidence:
`docs/PRODUCT_APP_OWNED_KD_RUNTIME_2026-09-09.md`.
2. Gated product run: no KD process and no debugger bytes existed until
`Loading files...`.  That marker never appeared on raw UART, while U-Boot and
late `IMAGE_AUDIT start enter` did.  It ended at 90 seconds just before
historical `BES`; cleanup restored baseline.  Evidence:
`docs/PRODUCT_APP_OWNED_KD_GATED_RUNTIME_2026-09-09.md`.

Therefore do **not** retry `Loading files...` as a gate.  It is not observable
on this product UART.  A later control proved `IMAGE_AUDIT start enter` is
observable, but its host script raised a local `ReadTimeout=0` API error before
starting KD.  That script now uses `Timeout.Infinite`; details are in
`docs/PRODUCT_APP_OWNED_KD_IMAGE_AUDIT_GATE_RUNTIME_2026-09-09.md`.
One later invocation failed before token authentication because the host made
its client connection before the Android listener had reported readiness; it
created no VM and applied no patch.  The host script now waits for the app's
durable `state=LISTENING` record.  See
`docs/PRODUCT_APP_OWNED_KD_BRIDGE_READINESS_CONTROL_2026-09-09.md`.

## One proposed next runtime (requires fresh authorization)

The `IMAGE_AUDIT`-gated runtime below has now been consumed and produced no
target KD packet.  Do not rerun it blindly or apply BCD/firmware variants.
Retain its command only as reproducibility evidence:

```powershell
$repo = 'C:\Users\denis\MainProjects\win11ontab\Non-root-Windows-VM'
$adb  = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
& "$repo\tools\product-kd\run-product-kd-raw-bridge.ps1" `
  -AdbPath $adb `
  -PatchPath "$repo\build-logs\product-kd-preflight-20260909\product-kd-r11-combined.patch" `
  -ExpectedPatchSha256 '4F2EA0AE40E6467608EA753E1368EC3F97C03A4C11DA9B2A17782D62B93742E6' `
  -ArtifactDir "$repo\build-logs\product-kd-image-audit-gated-runtime-$stamp" `
  -GateMarker 'IMAGE_AUDIT start enter' `
  -GateTimeoutSeconds 120 `
  -DurationSeconds 100
```

The read-only BCD/KD phase-semantics audit is complete:
`docs/PRODUCT_KD_BCD_PHASE_SEMANTICS_AUDIT_2026-09-09.md`. It closes blind
BCD/KD variants. A future runtime needs a genuinely new, independently
justified observer; do not use this command as an automatic retry.

The bridge `finally` block now force-stops only `com.example.winavf` before
rollback.  If a host interruption occurs, use the recovery sequence below.

## Mandatory recovery and verification

Never apply a second patch before this reports the exact baseline:

```powershell
$adb = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb shell am force-stop com.example.winavf
Start-Sleep -Seconds 2
& $adb shell am start -n com.example.winavf/.MainActivity --ez rollback true
Start-Sleep -Seconds 8
& $adb shell cat /sdcard/Android/data/com.example.winavf/files/rollback-report.txt
& $adb shell 'sha256sum /sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img; vm list; settings get global hidden_api_policy'
```

Required result:

```text
RESULT=PASS
BASELINE_SHA256=2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
Running VMs: []
null
```

## Build and installation instructions

### Android app

The app includes the raw localhost bridge, `onNewIntent()` lifecycle handling,
and hidden API console-input access.  Build only when source intentionally
changes:

```powershell
Set-Location 'C:\Users\denis\MainProjects\win11ontab\Non-root-Windows-VM\android-app'
.\build.ps1
$adb = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb install -r .\out\WinAVF-test.apk
Get-FileHash .\out\WinAVF-test.apk -Algorithm SHA256
```

Required host locations:

```text
Android SDK: C:\Users\denis\AppData\Local\Android\Sdk
NDK:         <SDK>\ndk\28.2.13676358
Build Tools: <SDK>\build-tools\36.0.0
JBR:         C:\Program Files\Android\Android Studio\jbr\bin
WinDbg KD:   C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2606.22001.0_x64__8wekyb3d8bbwe\amd64\kd.exe
```

### Firmware

Do not rebuild firmware for the proposed KD gate test.  r11 is already built
and the FD bytes have the hash above.  If a separately authorized source
change genuinely needs an FD, use the recorded environment and entry point:

```powershell
Set-Location 'C:\Users\denis\MainProjects\win11ontab'
.\tools\build-known-good-edk2.ps1
```

The old working build contract is:

```text
EDK2: firmware-work/edk2
EDK_TOOLS_BIN: <EDK2>/BaseTools/Source/C/bin
PYTHON_COMMAND: C:/Users/denis/AppData/Local/Programs/Python/Python314/python.exe
GCC5_AARCH64_PREFIX: tools/arm-gnu-toolchain-15.2/bin/aarch64-none-elf-
IASL_PREFIX: firmware-work/acpica/generate/unix/bin/
build -n 4 -a AARCH64 -t GCC5 -p ArmVirtPkg/ArmVirtKvmTool.dsc -b DEBUG
```

Full toolchain details and historical caveats: `docs/EDK2_KNOWN_GOOD_RESTORE_2026-09-06.md`.
Do not resurrect the generic MSYS/echo investigation unless a new FD is truly
required.

### BCD candidate materialization (already complete)

Do not repeat this before the one proposed gate test.  If it must be recreated,
run the existing script **once from elevated PowerShell**.  It uses only a
temporary fixed VHD and the Windows storage stack, rejects wrong hashes and
pre-existing targets, and never mounts or edits a physical disk:

```powershell
Set-Location 'C:\Users\denis\MainProjects\win11ontab\Non-root-Windows-VM'
.\tools\product-kd\materialize-product-kd-bcd-candidate.ps1
```

The only valid source raw is:

```text
E:\winavf-a3-append-only-runtime.img
SHA: 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

**Never use** `E:\winavf-kd-shell-clone-20260907-baseline.img` as a baseline;
despite its filename, it contains an old KD candidate.  Never use manual FAT
chain patching or `mtools` for the product candidate.

## Repository and evidence map

The repository intentionally remains dirty with prior work and accumulated
untracked reports/artifacts.  Preserve all of it; do not reset, clean, delete,
or overwrite broad directories.  The essential entry points are:

```text
STATE.md
../CHECKLIST.md
docs/PRODUCT_APP_OWNED_KD_RUNTIME_2026-09-09.md
docs/PRODUCT_APP_OWNED_KD_GATED_RUNTIME_2026-09-09.md
docs/APP_OWNED_BINARY_CONSOLE_LOOPBACK_RUNTIME_2026-09-09.md
docs/R11_DEBUG_UART_ALIGNMENT_RUNTIME_2026-09-08.md
tools/product-kd/run-product-kd-raw-bridge.ps1
tools/product-kd/materialize-product-kd-bcd-candidate.ps1
build-logs/product-kd-preflight-20260909/
build-logs/product-kd-runtime-20260909/
build-logs/product-kd-gated-runtime-r2-20260909/
```

The formerly proposed gated serial-KD run has completed and did not yield a
target packet. Do not repeat BCD/KD variants. The current direct-observer
state is:

```text
DIRECT_POST_EBS_WINDOWS_OBSERVABILITY = BLOCKED (exact app-owned product VM)
SHELL_GUEST_GDB_PC_OBSERVER            = BLOCKED
PRODUCT_APP_GDB_PC_OBSERVER             = CONDITIONAL
```

Read `docs/DIRECT_POST_EBS_WINDOWS_OBSERVABILITY_AUDIT_2026-09-09.md` and
`docs/SHELL_CROSVM_GDB_ENDPOINT_RUNTIME_2026-09-09.md` before any new runtime.
No WIM, vsock, graphics, startnet, BootExecute, generic FAT, Perfetto, KVM
ftrace, GenieZone ftrace, BCD, Windows-KD, or raw shell-GDB experiment should
start unless a new vendor-privileged guest-state endpoint becomes available.

The product GDB configuration audit has since completed:

```text
PRODUCT_GDB_PORT_CONFIGURABILITY = FAIL
PRODUCT_APP_GDB_PC_OBSERVER      = BLOCKED
```

Custom-image WinAVF configurations convert to raw config with no `gdbPort`
assignment. Read `docs/PRODUCT_GDB_PORT_CONFIGURATION_AUDIT_2026-09-09.md`.
