# Windows HVC/PSCI/IORT static audit — 2026-09-13

## Scope

This read-only closure covers the remaining plausible Windows-specific
platform-description branch after the post-EBS P7 EL1-vector result. No VM was
launched and no Windows media, BCD, firmware, Android code, ACPI table, or
tablet image byte was changed.

The narrow question is whether the live product presents a missing IORT/MCFG
PCI contract or inconsistent PSCI/HVC conduit that could justify a new
firmware-only Windows A/B.

## Live ACPI result

The retained runtime table dump at
`build-logs/20260907-perfetto-r9-post-ebs/runtime-r9-raw-serial.log:929-938`
reports an XSDT of 100 bytes with exactly eight pointers: FACP, GTDT, MADT,
SPCR, three SSDTs, and DBG2. There is no IORT and no MCFG entry.

That absence is intentional. `ArmVirtPkg/KvmtoolCfgMgrDxe/ConfigurationManager.c:704-720`
removes MCFG, PCI SSDT and IORT together when the dynamic FDT repository has
no PCI config-space object. The static repository's potential IORT data is
therefore inactive for the product topology.

IORT/MCFG cannot be a consumer-side cause of the present early Windows stall:
the product loader was never given either table.

## PSCI/HVC result

The actual product FDT/firmware evidence says `method=hvc`, while the live
FADT records `armboot=0x0003`, the expected
`PSCI_COMPLIANT | PSCI_USE_HVC` pairing. The direct Linux ACPI control reached
userland on that exact conduit and logged:

```text
psci: probing for conduit method from ACPI.
psci: PSCIv1.0 detected in firmware.
psci: Using standard PSCI v0.2 function IDs
```

Exact product Windows boot files were inspected without modification:

| File | SHA-256 | Static result |
| --- | --- | --- |
| `winload.efi` | `F7747F4AC18CCD66EBF6A043D979CF30C7731114C27C33FF2FC3C0610F491D31` | generic HVC `#1` and SMC `#0` entry wrappers; standard PSCI constants |
| `ntoskrnl.exe` | `C667739004D1186DACA2FD3FE7CCDE61394BC068F385B4BB8CD5364D3005A734` | generic HVC/SMC wrappers and standard PSCI constants |

For example, the exact `winload.efi` has HVC wrappers at image VAs
`0x1800010d8` and `0x1800011c4`, and SMC wrappers at `0x18000121c` and
`0x180001284`. This is normal multi-platform code; it does not identify which
wrapper silent Windows execution selected or a bad PSCI call.

The Microsoft Hyper-V discovery value `0x0C600FF0` does not occur as a raw
little-endian immediate in the exact `winload.efi`, `ntoskrnl.exe`, or
`hal.dll`. That is only negative static evidence: ARM64 can synthesize a
constant in registers, so it is not proof that Windows never does discovery.

## Verdict

```text
PRODUCT_IORT_MCFG_BOOT_CONTRACT       = NOT_APPLICABLE (tables absent)
PRODUCT_PSCI_HVC_CONTRACT             = PASS
LINUX_ACPI_PSCI_HVC_RUNTIME            = PASS
WINDOWS_HVC_SMC_SUPPORT_CODE           = PRESENT (static)
WINDOWS_HVC_RUNTIME_BRANCH             = UNKNOWN
HVC_PSCI_AS_CONCRETE_WINDOWS_CAUSE     = NOT_PROVEN
VALID_HVC_OR_IORT_FIRMWARE_A_B         = NOT_IDENTIFIED
```

Changing the PSCI method, inventing IORT/MCFG, or changing an HVC-related FADT
flag would make the known-good Linux/product description less faithful without
identifying a Windows failure site. No such A/B is justified.

## Closed platform classes

The product platform has independently passed all of the following after the
real loader returns from `ExitBootServices()`:

* virtual generic-timer PPI27 delivery and WFI wake;
* GICv3 re-arm path;
* EL1 synchronous exception entry, private vector execution, ELR advance and
  `ERET` return; and
* Linux ACPI/PSCI-HVC kernel-to-userland execution on the same product VM
  topology.

The remaining failure is Windows-specific, but no evidence-backed firmware or
ACPI mutation remains. The next useful observer must be a Windows-specific
execution/failure artifact with known semantics; it is not another HVC, IORT,
timer, GIC, or speculative ACPI experiment.
