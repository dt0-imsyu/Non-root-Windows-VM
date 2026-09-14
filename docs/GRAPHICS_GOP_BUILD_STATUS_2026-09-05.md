# Graphics GOP frame PoC build status — 2026-09-05

## Result

The visible-output path is implemented through the existing app-readable
`console_out` channel. Firmware captures a bounded 320x200 GOP region, emits a
28-byte little-endian `WAVF` keyframe with CRC32 using `SerialPortWrite`, and
the Android app decodes it into an app-owned `FrameSurfaceView`. The decoder
synthetic test remains `ConsoleFrameDecoderSelfTest PASS frames=2`.

The actual EDK2 source at
`firmware-work/edk2/ArmPkg/Library/PlatformBootManagerLib/PlatformBm.c` was
compiled successfully; the generated `PlatformBm.obj` is therefore a compile
level proof of the encoder. The protocol is bounded and independent of the
Windows image, so this path does not require root, privileged display Binder,
test signing, or signed Windows binary changes.

## Current blocker

An incremental full EDK2 build was run with local LLVM and make wrappers. It
passed metadata generation, C compilation, and assembler preprocessing. The
checkout lacks a coherent runnable Windows BaseTools set: `iasl` is Unix-only,
and the bundled `VfrCompile`/`GenSec`/`GenFfs` tools cannot complete the
generated Windows make rules under this host. The existing runtime FD was not
overwritten. No tablet runtime or FPS claim is made.

## Next exact experiment

Provide a matching Windows EDK2 BaseTools bundle (ACPICA `iasl.exe` plus the
same-version VFR/GenSec/GenFfs/GenFv tools), rebuild
`ArmVirtKvmTool-AARCH64/DEBUG_GCC5`, and verify the resulting FD hash. Run one
throwaway VM with the immutable Windows baseline and capture the app log plus a
screen image showing the decoded UEFI frame. Only after that PASS should the
encoder be changed to repeated dirty-tile frames for the 1–10 FPS installation
mode and then input feedback.

## Safety

No tablet state, system/vendor files, bootloader state, Windows WIM, or signed
driver was changed. The added `Trim`/make/compiler shims are workspace-local and
reversible build infrastructure.
