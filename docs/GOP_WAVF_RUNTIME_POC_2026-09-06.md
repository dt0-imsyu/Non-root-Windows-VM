# GOP → WAVF → captured console: runtime PoC (2026-09-06)

## Scope

This was one pre-EBS, firmware-only runtime A/B.  It did not alter the WIM,
BCD, GPT, FAT metadata, Windows files, or Android system state.  It did not
attempt post-EBS graphics, WinPE, vsock, or native Samsung display access.

Goal: prove that the bounded EDK2 GOP keyframe encoder reaches the existing
app-readable raw console pipe.

## Firmware candidate

| Item | Value |
|---|---|
| FD | `firmware-work/edk2/Build/ArmVirtKvmTool-AARCH64/DEBUG_GCC5/FV/KVMTOOL_EFI.fd` |
| Size | 2,097,152 bytes |
| SHA-256 | `8BB42784791B6618D599EF7552C2CF4DFBA61AE5E07B7F08AC76B3F01F48392C` |
| Build evidence | `build-logs/edk2-clean-gop-20260906-r4.log` ends in `- Done -` |
| Inclusion evidence | r4 BdsDxe/FVMAIN contain UTF-16 `AVF_GOP_FRAME`; see `GOP_FD_CANDIDATE_AUDIT_2026-09-06.md` |

This establishes `EXPERIMENTAL_GOP_FD_CANDIDATE = PASS`.  It does not yet
establish reproducibility of the historical EDK2 environment.

## Transactional deployment

The immutable runtime baseline is:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

It was checked on the tablet before application and again after rollback.

The installed legacy launcher consumes `WAVFPAT1` bundles from:

```text
/sdcard/Android/data/com.example.winavf/files/winavf-image-patch.bin
```

It verifies the full baseline SHA-256 before forward writes, verifies the old
hash and then read-back hash of each range, retains the original bytes as its
rollback record, and verifies the full immutable baseline SHA-256 after
rollback.  This was used instead of copying/rebuilding a 9 GiB image.

| Item | Value |
|---|---|
| Bundle | `build-logs/gop-poc-20260906/gop-wavf-r4-firmware.patch` |
| Bundle size | 4,194,436 bytes |
| Bundle SHA-256 | `8A90A63D1B80F28F25DC6011878F58EA66DD1945348577D6AB9854873F2F4179` |
| Range count | 1 |
| Raw range | offset `7250927616`, length `2097152` |
| Target | existing `\\EFI\\EDK2\\QEMU_EFI.fd` only |
| Baseline firmware hash embedded | `3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995` |
| Candidate firmware hash embedded | `8BB42784791B6618D599EF7552C2CF4DFBA61AE5E07B7F08AC76B3F01F48392C` |

The builder is
`tools/new-winavf-firmware-patch-from-verified-baseline.ps1`.  It uses the old
2 MiB file bytes from a prior verified baseline firmware bundle; it does not
open, create, or modify a runtime image.  The launcher independently proves
that those old bytes still describe the device image before it writes.

## Runtime evidence

Raw serial capture:

```text
build-logs/gop-poc-20260906/runtime-r4-raw-serial.log
size: 266253 bytes
SHA-256: B9B9C32EE188F96A22B61C8A7F71A877FE6A2D07F14503BDA4FB4384187992C2
```

The exact evidence in that raw file is:

```text
WAVF                         (binary frame header at byte offset 4745)
AVF_GOP_FRAME status=Success size=320x200
```

Result:

```text
GOP_WAVF_RAW_CONSOLE_EXPORT = PASS
```

This is an end-to-end proof through:

```text
EDK2 GOP capture → WAVF encoder → SerialPortWrite → AVF console_out → Android app raw InputStream
```

## Rollback

Immediately after the single run, the legacy launcher was invoked with its
`rollback` extra.  Its displayed result was:

```text
Small image patch rolled back and the runtime image was verified.
```

The post-rollback tablet SHA-256 again matched the immutable baseline exactly;
the staging bundle no longer existed.

## Decoder APK and SurfaceView audit

A controlled APK update was then installed over the legacy app.  It has the
same signing-certificate SHA-256 digest as the installed launcher and preserves
the legacy VM name, one-CPU topology, media filename, wrapper asset, and
transactional patch/rollback path.  Its only new normal-path behavior is the
existing `ConsoleFrameDecoder → FrameSurfaceView` connection.

The historic wrapper asset was copied byte-for-byte (SHA-256
`93EDA7C4BD54C33F85ADA6F05158C74EC6F5C3232F5CBA73846E5B442895F234`),
avoiding a U-Boot rebuild.

The same one-run firmware test reached the frame again.  Offline packet audit
of `runtime-r4-decoder-serial.log` found a valid 320×200, 256,000-byte keyframe
at offset 4746 with CRC `0xB9796E7D`; the calculated standard CRC32 is exactly
the same.  Its 64,000 pixels were all BGRA `00 00 00 FF`.  The black SurfaceView
in `runtime-r4-decoder-screen.png` was therefore an accurate rendering of the
actual firmware frame, not a decoder failure.  The transactional patch was
again rolled back and the full tablet baseline hash rechecked.

Separately, the APK has an intent-gated UI-only synthetic frame audit.  It does
not create a VM or touch media.  A gradient `WAVF` keyframe passed through the
same decoder and visibly rendered on the real tablet SurfaceView; evidence is
`build-logs/gop-poc-20260906/synthetic-surface-audit.png` (SHA-256
`5D12FEB8AFDF06BAB5C6B922FF15D94F8A19C2C3363DA119A732C59B9CA18F7F`).

```text
SURFACEVIEW_PRESENTATION = PASS
REAL_GOP_FRAME_VISIBILITY = BLOCKED_BY_BLACK_SOURCE_FRAME
```

The next cheapest graphics experiment is not Windows work: make the firmware
emit a known non-black GOP diagnostic frame (or capture after a known GOP draw)
and repeat this same one-range, reversible firmware test.  That distinguishes
the EDK2 GOP content/timing issue from the now-proven console and Android
render paths.

## Follow-up diagnostic-frame build attempt — stopped safely

The source now contains a second, explicitly marked
`AVF_GOP_DIAG_FRAME`: it writes a gradient using GOP `EfiBltBufferToVideo`,
emits that buffer as a second `WAVF` record, and restores the original 320×200
pixels.  The pre-existing real capture remains first and unchanged.

The controlled historical build was launched with
`tools/build-known-good-edk2.ps1` at 2026-09-06 14:26.  It stopped before a
new FD because generated EDK2 make rules invoked literal `"echo"` under
`cmd.exe`:

```text
'"echo"' is not recognized as an internal or external command
mingw32-make: ... EnglishDxe.dll] Error 1
build.py: error F002: Failed to build module ... EnglishDxe.inf
- Failed -
```

This is the known Windows/MSYS host-build semantic issue, not a GOP compiler
diagnostic.  No FD candidate was accepted, no patch was made, and no tablet
media/VM run occurred.  Per the bounded-work rule, build-environment repair is
deferred; the next session should first restore the exact successful r4 host
build semantics or use the already known temporary Win64 BaseTools route, then
build and audit the diagnostic FD before any runtime test.

### Narrow `echo` retry — also stopped

At 14:35 the only attempted local workaround added `C:\\msys64\\usr\\bin` to
the existing build script `PATH`, making its `echo.exe` visible to quoted
`"echo"` make commands. It cleared that first failure, but `mingw32-make` then
selected MSYS `sh.exe`. MSYS path conversion stripped backslashes from the
Windows source path passed through a GCC response file:

```text
cc1.exe: fatal error: C:UsersdenisMainProjectswin11ontab...AcpiParser.c:
No such file or directory
```

The one-line PATH edit was reverted. A real repair now needs the exact
historical make/shell semantics or a purpose-built no-op `echo.exe` that does
not expose MSYS `sh.exe`; either is broader than the allowed one-command
workaround. The current FD is still r4 (`8BB427...F48392C`); no deployment
artefact or tablet state changed.

### r4 forensic replay — exact boundary

The successful r4 log proves the actual local environment was:

- `EDK_TOOLS_BIN=...\\BaseTools\\Bin\\Win64` (not the later Source/C route);
- bundled llvm-mingw `python.exe` under
  `tools/toolchains/llvm-mingw-20260826-clean-extract`;
- GCC 15.2 `aarch64-none-elf-` prefix and MSYS `mingw32-make`;
- `cmd.exe`, empty `MAKE_FLAGS`, `MSYS_NO_PATHCONV=1`, and
  `MSYS2_ARG_CONV_EXCL=*`;
- Win64 `VfrCompile.exe`, `GenFw.exe`, `GenFv.exe`, `GenFfs.exe`, and
  `GenSec.exe` (all remain present); and
- two wrappers seen in the r4 log: `objecho.cmd` and `iasl-msys.cmd`.

`tools/build-r4-replay-edk2.ps1` records that environment. Its first replay
reached the r4 no-op/objcopy stage; its second replay reached IASL. Both stop
at the same non-reproducible artifact: the currently saved
`firmware-work/toolwrap/iasl-msys.cmd` has a 01:25 timestamp, after the r4
01:04–01:08 build, and passes `-pC:\\...` into POSIX `iasl` as a collapsed
`C:Users...` path. The r4 wrapper's path-preserving implementation is not
present anywhere on disk. The historic r4 `objecho.cmd` is likewise absent,
but its behaviour is fully observable in the log; the lost IASL wrapper
semantics are the blocking component.

`R4_BUILD_ENV_REPLAY = BLOCKED_BY_MISSING_R4_IASL_WRAPPER_SEMANTICS`.

## Superseding r5 result

The missing wrapper semantics were reconstructed and tested against an actual
IASL invocation; the replay then completed top-level packaging. r5 was built
in that same environment and its one firmware-only runtime run produced a
CRC-valid, visibly rendered non-black diagnostic GOP frame. Therefore the
historical blocker and black-source conclusion above are superseded:

```text
R4_BUILD_ENV_REPLAY = PASS
NEW_GOP_FD_BUILD = PASS
REAL_GOP_NONBLACK_FRAME = PASS
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

The precise build, patch, capture, screenshot, and verified rollback evidence
is recorded in `GOP_R5_DIAGNOSTIC_RUNTIME_2026-09-06.md`.
The source-only diagnostic gradient was restored after the replay checks. The
FD remains `8BB42784791B6618D599EF7552C2CF4DFBA61AE5E07B7F08AC76B3F01F48392C`;
no r5 FD, patch, tablet write, or runtime run occurred.
