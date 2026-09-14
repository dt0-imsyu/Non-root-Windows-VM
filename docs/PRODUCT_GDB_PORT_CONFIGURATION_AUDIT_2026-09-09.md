# Product GDB-port configuration audit — 2026-09-09

## Scope

Read-only source and runtime-API audit only. No VM was created, no APK was
built or installed, and no Android setting, BCD, firmware, WIM, or Windows
file was changed.

## Result

```text
PRODUCT_GDB_PORT_CONFIGURABILITY = FAIL
PRODUCT_APP_GDB_PC_OBSERVER      = BLOCKED
```

## Exact configuration path

WinAVF uses `VirtualMachineConfig.Builder.setCustomImageConfig(...)` for its
kernel-first U-Boot wrapper and Windows disk. The framework selects raw
configuration whenever `getCustomImageConfig() != null`:

```text
custom image config
  -> VirtualMachine.createVirtualMachineConfigForRawFrom()
  -> VirtualMachineConfig.toVsRawConfig()
  -> IVirtualizationService.createVm(RawConfig, ...)
```

The local framework source establishes that branch at
`VirtualMachine.java:1685-1699`. `toVsRawConfig()` begins at
`VirtualMachineConfig.java:772` and returns at line 927. It fills kernel,
bootloader, disks, memory, CPU, console and display fields, but has no
assignment to `config.gdbPort`.

The installed reflection inventory independently contains neither
`VirtualMachineConfig.Builder.setGdbPort(...)` nor a GDB-port field in the
product configuration/builder, including under the previously audited hidden
API policy relaxation.

## Why AppConfig does not solve it

AOSP VirtMgr can consume `gdbPort` from
`VirtualMachineAppConfig.CustomConfig`. That is the alternate AppConfig path.
The product custom-image VM cannot use it: the framework selects RawConfig as
shown above. Directly mutating the generated raw AIDL parcel after conversion
would bypass the supported application configuration contract and was not
attempted.

## Consequence

```text
DIRECT_POST_EBS_WINDOWS_OBSERVABILITY = BLOCKED
SHELL_GUEST_GDB_PC_OBSERVER            = BLOCKED
PRODUCT_APP_GDB_PC_OBSERVER             = BLOCKED
```

There is no remaining non-root direct PC/vCPU/exit/IRQ/timer/exception observer
for the exact product VM. The next valid boundary must be a later signed
Windows-visible or firmware-visible side effect, or a future vendor-published
GenieZone/GZVM trace facility.
