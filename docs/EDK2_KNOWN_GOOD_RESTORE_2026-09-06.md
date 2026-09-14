# EDK2 known-good build restoration - 2026-09-06

## Scope

The host-toolchain reconstruction branch was stopped. No new shim, BaseTools
rewrite, Windows image change, Android decoder change, or runtime patch was
made during this restoration.

## Host/build files reviewed

The temporary branch had touched the following host-side files:

- `BaseTools/Conf/build_rule.template`
- `BaseTools/Source/C/GenFfs/Makefile`
- `BaseTools/Source/C/GenFv/Makefile`
- `BaseTools/Source/C/GenSec/Makefile`
- `BaseTools/Source/C/Makefiles/ms.common`
- `BaseTools/Source/Python/GenFds/FfsInfStatement.py`
- `BaseTools/Source/Python/GenFds/GenFdsGlobalVariable.py`
- `firmware-work/toolwrap/iasl-msys.cmd`
- generated `Conf/tools_def.txt` and `Conf/build_rule.txt`

The tracked BaseTools/GenFds files and `iasl-msys.cmd` are restored to their
pre-branch contents. Temporary `cmd-shim.bat`, `copy.cmd`, `del.cmd`, and
`objecho.cmd` shims were removed. `BaseTools/Bin/Win64` contains old generated
tools from the failed branch, but no active configuration points to them.

## Restored known-good environment

```text
EDK2 = firmware-work/edk2
EDK_TOOLS_BIN = <edk2>/BaseTools/Source/C/bin
PYTHON_COMMAND = C:/Users/denis/AppData/Local/Programs/Python/Python314/python.exe
GCC5_AARCH64_PREFIX = tools/arm-gnu-toolchain-15.2/bin/aarch64-none-elf-
IASL_PREFIX = firmware-work/acpica/generate/unix/bin/
build -n 4 -a AARCH64 -t GCC5 -p ArmVirtPkg/ArmVirtKvmTool.dsc -b DEBUG
```

`Conf/tools_def.txt` now has `*_GCC5_*_MAKE_PATH = DEF(GCC_HOST_PREFIX)make`,
blank GCC5 make flags, direct `UNIX_IASL_BIN`, the default `VfrCompile`, and no
temporary absolute `objcopy` rule.

## Evidence and result

The previous known-good logs `build-logs/edk2-kvmtool-virtual-rtc.log` and
`build-logs/edk2-kvmtool-vblk-r12-20260825.log` end with `- Done -` using the
Source/C tool directory and the regular Python path.

The existing 2 MiB firmware is preserved:

```text
Build/.../FV/KVMTOOL_EFI.fd
SHA-256 8BB42784791B6618D599EF7552C2CF4DFBA61AE5E07B7F08AC76B3F01F48392C
```

The saved GUI baseline is also preserved:

```text
artifacts/KVMTOOL_EFI-gui-rtc-gic.fd
SHA-256 7C5134A9EBC66F93A97D5CA93ED55A810B9091F2B1EAF1A8D91715852FFE01D9
```

`NEW_GOP_FD_BUILD` is **NOT_PASS**. The r4 file above was produced before this
rollback with temporary Win64 BaseTools and is not silently relabelled as a
known-good GOP build. A clean reproduction from the sandbox reached compilation
but failed when the MSYS make process could not resolve bare `GenFw`; this is a
host invocation boundary, not evidence of a GOP or product failure.

## Process-environment diff

The successful August process recorded `EDK_TOOLS_PATH`, `EDK_TOOLS_BIN`,
`CONF_PATH`, and the regular Python path, and its command stream resolved
`VfrCompile`, `GenFw`, GCC, and `mingw32-make`. The current Codex process has
empty `WORKSPACE`, `EDK_TOOLS_PATH`, `EDK_TOOLS_BIN`, `PYTHON_COMMAND`,
`GCC5_AARCH64_PREFIX`, `GCC_HOST_BIN`, and `IASL_PREFIX`; `build`, `GenFw`,
`VfrCompile`, GCC, and `make` are absent from command resolution. The current
PATH contains Codex runtime directories and standard Windows paths, but none of
the known-good EDK2, ARM GNU, MSYS, or ACPICA directories.

When temporary paths were injected for diagnosis, the parent process could see
`GenFw`, but the MSYS/mingw child process still emitted
`CreateProcess(NULL, GenFw ...) failed`. This reproduces the boundary without
changing EDK2 rules or adding a shim.

## Next controlled action

Run the exact known-good command from a normal Windows developer PowerShell or
Visual Studio terminal with the environment above. Only after that command ends
with `- Done -` should the single GOP/WAVF encoder change be applied and a new FD
hash recorded.

The reproducible manual entry point is
`tools/build-known-good-edk2.ps1`. It validates required files, sets the known-good
environment, writes a timestamped full log, preserves the child exit code, and
prints the new FD path, size, and SHA-256 only after `- Done -` and a fresh FD are
confirmed.
