# GOP/WAVF experimental FD candidate audit — 2026-09-06

## Decision

```text
EXPERIMENTAL_GOP_FD_CANDIDATE = PASS
NEW_GOP_FD_BUILD              = NOT_PASS
```

The first status means there is an existing, fully packaged FD that contains
the current GOP/WAVF encoder code path and may be used for an isolated,
reversible runtime display PoC.  The second status remains intentionally
unconfirmed: this build has not yet been reproduced using the restored
historical build environment.

## Candidate identity

```text
Path:
firmware-work/edk2/Build/ArmVirtKvmTool-AARCH64/DEBUG_GCC5/FV/KVMTOOL_EFI.fd

Size:       2,097,152 bytes
Timestamp:  2026-09-06 01:08:27 +03:00
SHA-256:    8BB42784791B6618D599EF7552C2CF4DFBA61AE5E07B7F08AC76B3F01F48392C

Historical GUI baseline:
firmware-work/edk2/artifacts/KVMTOOL_EFI-gui-rtc-gic.fd
SHA-256:    7C5134A9EBC66F93A97D5CA93ED55A810B9091F2B1EAF1A8D91715852FFE01D9
```

The candidate differs from the preserved GUI baseline.  A binary difference is
expected and is not itself a regression diagnosis.

## Build completion evidence

`build-logs/edk2-clean-gop-20260906-r4.log` records:

```text
Building ... ArmPkg/Library/PlatformBootManagerLib/PlatformBootManagerLib.inf [AARCH64]
Fd File Name: KVMTOOL_EFI (.../FV/KVMTOOL_EFI.fd)
Generating FVMAIN_COMPACT FV
Generating FVMAIN FV
- Done -
Build end time: 01:08:27, Sep.06 2026
Build total time: 00:03:37
```

The r4 command stream compiled `ArmPkg/Library/PlatformBootManagerLib/PlatformBm.c`,
then archived `PlatformBootManagerLib.lib`; `BdsDxe` links that exact library.

## Encoder inclusion evidence

The current modified source contains:

```text
AvfEmitGopKeyframe()
  GOP Blt -> 320 x 200 BGRA buffer
  WAVF magic 0x46564157 (written little-endian as "WAVF")
  CRC32
  SerialPortWrite(header), SerialPortWrite(pixels)
  UTF-16 "AVF_GOP_FRAME status=..." marker
```

Offline linkage checks passed:

1. The r4 `PlatformBm.obj` and `PlatformBootManagerLib.lib` contain LTO
   sections for `AvfEmitGopKeyframe`, `AvfFrameCrc32`, and the frame helpers.
2. The r4 `BdsDxe.map` explicitly loads `PlatformBootManagerLib.lib(PlatformBm.obj)`.
3. The r4 `BdsDxe.efi` contains UTF-16 `AVF_GOP_FRAME` at offsets `78158` and
   `78230`.
4. The r4 uncompressed `FVMAIN.Fv` contains the same UTF-16 marker at offsets
   `4404522` and `4404594`.
5. `ArmVirtKvmTool.fdf` packages `FVMAIN` inside the compressed
   `FVMAIN_COMPACT`, and `[FD.KVMTOOL_EFI]` embeds `FVMAIN_COMPACT` at offset
   `0x8000`.  Therefore the marker is not visible as plaintext in the final
   2 MiB FD; that is expected compression behavior, not evidence of omission.

All generated FV/FD timestamps are consistent with the r4 completion window.

## Recovered historical build environment

The old known-good builds used native Windows process semantics, not a generic
MSYS shell.  Their final logs are:

```text
build-logs/edk2-kvmtool-virtual-rtc.log
build-logs/edk2-kvmtool-vblk-r12-20260825.log
```

The exact important values were:

```text
WORKSPACE        = firmware-work/edk2
EDK_TOOLS_PATH   = <workspace>/BaseTools
EDK_TOOLS_BIN    = <workspace>/BaseTools/Source/C/bin
CONF_PATH        = <workspace>/Conf
PYTHON_COMMAND   = C:/Users/denis/AppData/Local/Programs/Python/Python314/python.exe
GCC5_AARCH64_PREFIX = tools/arm-gnu-toolchain-15.2/bin/aarch64-none-elf-
GCC_HOST_PREFIX  = C:/msys64/mingw64/bin/mingw32-
IASL_PREFIX      = firmware-work/acpica/generate/unix/bin/
SHELL/MAKESHELL  = C:/Windows/System32/cmd.exe
```

Build command:

```text
build -n 4 -a AARCH64 -t GCC5 -p ArmVirtPkg/ArmVirtKvmTool.dsc -b DEBUG
```

The preserved executable wrapper is `tools/build-known-good-edk2.ps1`.  It
sets the environment above, invokes `BaseTools/Source/Python/build/build.py`,
records a timestamped log, and declares success only if the child exit code is
zero, `- Done -` is present, and the FD timestamp is fresh.

The r4 candidate was built before restoration while temporary Win64 BaseTools
and an MSYS `iasl` wrapper were active.  Do not reuse that environment as the
canonical build process and do not call r4 reproducible until the wrapper
build completes again from the preserved setup.

## Safe next action

The next product-graphics test may use this exact candidate only as an
isolated firmware replacement with the immutable GUI baseline retained for
immediate rollback.  Its narrow criterion is:

```text
GOP -> WAVF over console output -> Android ConsoleFrameDecoder -> FrameSurfaceView
```

Do not mix this PoC with Windows media, BCD, driver, or post-EBS work.
