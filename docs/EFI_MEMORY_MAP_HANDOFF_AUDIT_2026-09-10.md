# EFI memory-map / ExitBootServices handoff audit — 2026-09-10

## Scope

Read-only review only.  No VM was started and no firmware, Android app, WIM,
BCD, driver, or disk image was changed.

The question was whether the existing EDK2 instrumentation or the firmware
memory map provides a concrete, fixable explanation for the Windows stop after
the proven `ExitBootServices()` return.

## Evidence reviewed

- `build-logs/ebs-controlled-ab-20260904/A0-baseline-serial.log`
- `build-logs/serial-ebs-only-r5.log`
- `build-logs/serial-convert-audit-r5.log`
- `firmware-work/edk2/ArmPkg/Library/PlatformBootManagerLib/PlatformBm.c`
- `firmware-work/edk2/MdeModulePkg/Core/Dxe/Mem/Page.c`
- `firmware-work/edk2/ArmVirtPkg/Library/ArmVirtMemoryInitPeiLib/ArmVirtMemoryInitPeiLib.c`
- `firmware-work/edk2/ArmVirtPkg/Library/KvmtoolVirtMemInfoLib/KvmtoolVirtMemInfoLib.c`

## Results

### ExitBootServices / MapKey contract

`AuditExitBootServices()` takes the MapKey supplied by the Windows loader and
calls the original `gBS->ExitBootServices(ImageHandle, MapKey)` unchanged.
After the call it uses only the already-proven raw UART writer to emit `S`,
`I`, or `F`, then returns the same status to the caller.

The installed hooks are only `ExitBootServices`, `LoadImage`, and
`StartImage`.  There is **no** `GetMemoryMap` replacement, no MapKey rewrite,
and no Boot Services allocation in the wrapper between the loader's final
`GetMemoryMap()` and the original EBS call.  The wrapper recalculates the Boot
Services table CRC at installation time, before Windows is launched.

The historical baseline contains the post-original-return `S` marker.  Thus
the actual Windows loader's final map/key handshake succeeded for that run.

```text
EBS_MAPKEY_FORWARDING                  = PASS
ORIGINAL_EXIT_BOOT_SERVICES_RETURN      = PASS
FINAL_WINDOWS_MEMORY_MAP_BYTES_CAPTURED = NOT_AVAILABLE
```

The diagnostic `DumpWindowsAcpiContract()` does call `GetMemoryMap()`, but it
does so earlier in BDS, before `BOOTAA64.EFI` is started.  It is a read-only
snapshot; Windows later obtains its own current map and MapKey.

### RAM and runtime descriptors

The known-good baseline's FDT-derived DRAM interval is:

```text
0x80000000 .. 0x17fffffff  (4 GiB)
```

The logged EFI map covers that interval as conventional memory plus normal
firmware allocations.  Runtime-service code/data descriptors (EFI types 5
and 6) carry `EFI_MEMORY_RUNTIME` (`0x8000000000000000`) in the captured map.
The PEI memory-init source creates the system-memory resource HOB directly
from that FDT-derived base and size.  The Kvmtool MMU mapping separately maps
the space below DRAM as device memory, which is appropriate for platform MMIO.

No logged descriptor contradicts the FDT DRAM interval, and no concrete
runtime-descriptor attribute violation was found.

```text
EFI_MEMORY_DESCRIPTOR_CONTRACT = PASS (for the captured BDS map)
```

This does not claim a byte-for-byte capture of the loader's final map, which
is not available without adding a new observer.  The successful original EBS
return is the direct evidence that the final map/key exchange itself was
accepted.

### `CONVERT_AUDIT ... Not Found`

The two recurring records request conversions at `0x10000000` and `0x00102000`.
Both are below the real DRAM base `0x80000000`; the same BDS diagnostic also
reports them as absent.  Those two addresses were hard-coded *diagnostic
targets* in `PlatformBm.c`, not expected RAM descriptors.

The `EFI_NOT_FOUND` originates in the DxeCore `CoreConvertPagesEx()` audit
when no firmware memory descriptor covers a requested address.  The records
occur while `BOOTAA64.EFI` is loading/starting, before EBS, and are identical
in the controlled baseline log that subsequently reaches the proven EBS
success marker.  Therefore they are not evidence of a post-EBS map corruption
or a Windows kernel failure.

```text
CONVERT_AUDIT_LOW_ADDRESS = EXPECTED_NON_RAM_MISS
CONVERT_AUDIT_AS_POST_EBS_CAUSE = REJECTED
```

## Conclusion

```text
EFI_MEMORY_MAP_HANDOFF_HYPOTHESIS = NO_CONCRETE_DEFECT_FOUND
WINDOWS_EBS_HANDOFF               = PASS
```

Changing RAM, runtime attributes, GIC/UART MMIO descriptors, or MapKey logic
would be a speculative regression, not a targeted repair.  Do not create an
ACPI/memory-map firmware A/B from this audit.

## One next informative direction

There is no evidence-backed firmware repair for the installer path at this
boundary.  The next genuinely distinct diagnostic boot class, if separately
authorized, is an installed Windows ARM64 system disk made by standard Windows
servicing.  It can distinguish a WinPE/Setup-specific issue from a common
`winload -> kernel/HAL` issue, but it is **not** a repair and should not be
started automatically.
