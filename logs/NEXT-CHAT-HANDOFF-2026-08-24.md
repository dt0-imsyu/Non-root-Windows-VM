# Galaxy Tab S11 -> Windows ARM64: continue from here

## User intent and discipline

- Work autonomously to graphical Windows Setup on the physical tablet. Do not end after short steps, builds, APK installs, or one boot test.
- Keep everything non-root and Knox-safe: no unlock, flashing, `/dev/block`, system/vendor/APEX/SELinux/crosvm modifications, physical Android disks, or user-data wipe.
- One visible PowerShell monitor only. Its script is `C:\Users\denis\MainProjects\win11ontab\build-logs\edk2-build-monitor.ps1`.
- Use concise serial evidence. Do not reopen U-Boot virtio queue work or generic QEMU EDK2 blob work without new evidence.

## Confirmed milestones on physical device

- AVF / system crosvm / GenieZone / kernel-first / U-Boot: PASS.
- U-Boot virtio-blk, GPT/FAT/ESP, EFI applications, Microsoft `BOOTAA64.EFI` and Boot Library: PASS.
- Second-stage EDK2 launched from U-Boot: PASS.
- Guest-only virtual RTC: PASS.
- DXE Core, GICv3 and ARM timer FDT parsing: PASS.
- EDK2 graphical Boot Manager GUI visible on tablet: PASS.

Current architecture:

`Android -> AVF -> system crosvm -> kernel-first -> U-Boot bootstrap -> ArmVirtKvmTool-based EDK2 -> Windows`

## Current actual blocker

EDK2 GUI shows Boot Manager, but `PciHostBridgeDxe` reports `Unsupported` before EDK2 can enumerate the Windows ESP. Do not create a Windows Boot#### entry yet: first prove EDK2 PCI -> virtio-blk -> GPT -> ESP -> SimpleFS.

Direct observed serial evidence:

```
AVF_GIC_FDT: v3 distributor @ 0x3FFF0000 redistributor @ 0x3FEF0000
AVF_TIMER_FDT: interrupts 29, 30, 27, 26
Error: Image at ... PciHostBridgeDxe.efi start failed: Unsupported
```

The prior U-Boot FDT/virtio evidence remains PASS. U-Boot reports the crosvm serial 16550 at `0x3f8` and virtio block capabilities at `0x2c018000` etc.

## Required next work

1. Build an evidence table of crosvm PCI FDT versus `OvmfPkg/Fdt/FdtPciHostBridgeLib` assumptions:
   - compatible, ECAM base/size, bus-range, ranges (I/O/MMIO32/MMIO64), translations, interrupt mapping.
2. Add concise `DEBUG_ERROR` markers to the FDT PCI host bridge platform layer as needed, build, boot, and capture the exact return path. Do not guess.
3. Fix the actual platform mapping. Then prove:
   `PCI_HOST_BRIDGE`, `PCI_ENUMERATION`, `EDK2_VIRTIO_BLK`, `EDK2_GPT`, `EDK2_ESP`, `EDK2_SIMPLE_FS`.
4. Configure deterministic default Windows boot using normal filesystem device path to `\EFI\BOOT\BOOTAA64.EFI`, not console menu input.
5. Continue without stopping through Windows Boot Manager, BCD, boot.wim, WinPE, Setup GUI. Preserve working graphics; add input after Setup appears.

## Working firmware and source

- EDK2 root: `C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2`
- Current platform: `ArmVirtPkg\ArmVirtKvmTool.dsc`
- Current FD: `Build\ArmVirtKvmTool-AARCH64\DEBUG_GCC5\FV\KVMTOOL_EFI.fd`
- Preserved GUI-working baseline: `C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\artifacts\KVMTOOL_EFI-gui-rtc-gic.fd`
- Current media: `C:\Users\denis\MainProjects\win11ontab\handoff-compact-2026-08-23\handoff-compact-2026-08-23\win11-setup-edk2-gpt-esp.img`
- Its FAT ESP starts at byte `1048576`; firmware path is `::/EFI/EDK2/QEMU_EFI.fd`.
- Original ISO is preserved and untouched at `/sdcard/Documents/win11-25h2/Win11_25H2_ARM64_ru-ru.iso`.

## Current intentional EDK2 adaptations

- `ArmVirtKvmTool` chosen because it uses 16550 serial from FDT and Linux-style RAM/FDT handoff.
- `EmbeddedPkg/RealTimeClockRuntimeDxe` plus upstream `VirtualRealTimeClockLib` provide guest-only RTC using architectural counter + UEFI variables.
- `VirtualRealTimeClockLib.inf` uses fixed `BUILD_EPOCH=1787572800` because Windows `cmd.exe` cannot evaluate its upstream Unix shell expression.
- `ArmVirtKvmTool.dsc` has `-fno-stack-protector` because this freestanding ARM toolchain has no `libssp`.
- Boot timeout is currently 0, to bypass stalled console countdown. GUI baseline is preserved.
- `FdtPciHostBridgeLib.c` has previous removal of strict nonzero MMIO translation rejections; PCI still fails and needs exact FDT evidence.

## App / tablet workflow

- App source: `C:\Users\denis\MainProjects\win11ontab\handoff-compact-2026-08-23\handoff-compact-2026-08-23\winavf-test`
- Package / device serial: `com.example.winavf` / `R52Y9072A2R`
- ADB: `C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- External filename expected by app: `win11-setup-edk2-v26-gpt-esp.img`.
- Before VM test, use `pm clear com.example.winavf`, grant both:
  - `android.permission.MANAGE_VIRTUAL_MACHINE`
  - `android.permission.USE_CUSTOM_VIRTUAL_MACHINE`
  then push the media to the external app directory and start `com.example.winavf/.MainActivity --ez start true`.
- Clearing the app removes only test app data and its VM, but also removes the external app-private staging file; repush it.
- Capture UI serial with `uiautomator dump`, strip `SERIAL: ` per line, then join.

## EDK2 build environment

Use the existing established cmd environment:

```
EDK_TOOLS_BIN=<edk2>\BaseTools\Source\C\bin
PYTHON_COMMAND=C:\Users\denis\AppData\Local\Programs\Python\Python314\python.exe
GCC5_AARCH64_PREFIX=C:\Users\denis\MainProjects\win11ontab\tools\arm-gnu-toolchain-15.2\bin\aarch64-none-elf-
GCC_HOST_BIN=C:\msys64\mingw64\bin\mingw32-
IASL_PREFIX=C:\Users\denis\MainProjects\win11ontab\firmware-work\acpica\generate\unix\bin\
PATH must include BaseTools C bin, toolchain bin, C:\msys64\mingw64\bin, C:\msys64\usr\bin
build -n 4 -a AARCH64 -t GCC5 -p ArmVirtPkg\ArmVirtKvmTool.dsc -b DEBUG
```

## Safety state

Stock Android; bootloader locked; no root; Knox untouched; all guest disks are app-private regular files; no physical Android disk exposed.
