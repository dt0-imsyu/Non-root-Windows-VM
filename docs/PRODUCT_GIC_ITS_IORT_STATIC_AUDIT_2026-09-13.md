# Product GIC ITS / IORT static audit — 2026-09-13

## Question

The historical Termux/QEMU Windows control used `gic-version=3,its=on`, while
the WinAVF product VM exposes a GICv3 PCI platform.  Could a missing GIC ITS
or an invalid ITS reference explain the observed Windows silence after the
proven `ExitBootServices()` return?

This is a read-only audit.  No VM, firmware, Windows image, BCD, WIM, or
Android artifact was changed.

## Product MADT result

The normal one-vCPU product runtime log records:

```text
ACPI_AUDIT MADT=... len=166 sum=1
ACPI_AUDIT GICC[0] uid=0 mpidr=0 flags=00000001 gicr=0
ACPI_AUDIT GICD base=3FFF0000 ver=3
ACPI_AUDIT GICR base=3FFD0000 range=20000
```

The host-topology A/B records eight GICCs and a 740-byte MADT:

```text
ACPI_AUDIT MADT=... len=740 sum=1
ACPI_AUDIT GICC[0] ...
...
ACPI_AUDIT GICC[7] ...
ACPI_AUDIT GICD base=3FFF0000 ver=3
ACPI_AUDIT GICR base=3FEF0000 range=100000
```

The actual ACPI 6.5 declarations in the checked-in EDK2 headers establish
the exact accounting:

```text
MADT header = 44 bytes
GICC        = 82 bytes (includes the ACPI 6.5 TRBE field)
GICD        = 24 bytes
GICR        = 16 bytes
GIC ITS     = 20 bytes
```

Therefore:

```text
1-vCPU: 44 + 1 * 82 + 24 + 16 = 166
8-vCPU: 44 + 8 * 82 + 24 + 16 = 740
```

Both exact totals leave no room for a MADT type-`0x0f` GIC ITS structure.  The
product FDT-derived configuration consequently has **no GIC ITS published to
the guest**.  That is allowed: the ACPI specification defines the GIC ITS as
optional for GICv3/v4.  It is not, by itself, a table-corruption finding.

## IORT cross-check

The generic `ArmVirtPkg/KvmtoolCfgMgrDxe/ConfigurationManager.c` source has
a static IORT root-complex mapping to an ITS group containing identifier `0`.
On a platform that also publishes a MADT GIC ITS ID `0`, this is a legitimate
association.  It initially looked like a possible invalid reference for the
product.

However, the *actual product XSDT* has exactly these eight tables:

```text
FACP, GTDT, APIC, SPCR, SSDT, SSDT, DBG2, SSDT
```

It has no `IORT` (`0x54524f49`) table.  Thus the static IORT template is not
delivered to the current Windows instance, and its ITS-group reference cannot
be parsed by Windows during this boot.  It is not the current post-EBS
blocker.

The relevant sources are:

- `firmware-work/edk2/ArmVirtPkg/KvmtoolCfgMgrDxe/ConfigurationManager.c`
  — the generic static ITS/IORT template;
- `firmware-work/edk2/DynamicTablesPkg/Library/Acpi/Arm/AcpiMadtLibArm/MadtGenerator.c`
  — GIC ITS is optional and emitted only when dynamic FDT parsing supplies
  `EArmObjGicItsInfo`;
- `firmware-work/edk2/ArmPkg/Library/PlatformBootManagerLib/PlatformBm.c`
  — the current audit prints GICC/GICD/GICR and XSDT signatures.

The ACPI specification requires an ITS identifier used for an ITS association
to match a MADT GIC ITS declaration; it also defines a GIC ITS as optional for
GICv3/v4. [ACPI Specification 6.4, MADT GIC ITS](https://uefi.org/htmlspecs/ACPI_Spec_6_4_html/05_ACPI_Software_Programming_Model/ACPI_Software_Programming_Model.html)

## Verdict

```text
PRODUCT_GIC_ITS_PRESENT              = NO
PRODUCT_IORT_PUBLISHED_TO_WINDOWS     = NO
PRODUCT_GIC_ITS_IORT_REFERENCE_ERROR  = REFUTED
GIC_ITS_AS_EARLY_WINDOWS_CAUSE        = NOT_PROVEN
FIRMWARE_ITS_ENABLE_A_B                = NOT_JUSTIFIED
```

Adding a fictitious ITS to ACPI without a matching virtual hardware block
would violate the platform contract.  Enabling an ITS only because QEMU used
one would be an uncontrolled machine-model change, not a valid one-variable
Windows repair experiment.

## Relationship to the Windows boundary

This audit does not prove that Windows has reached PCI enumeration.  It only
removes a tempting but unsupported explanation: the current Windows instance
cannot be hanging while following an IORT-to-ITS mapping that is absent from
its XSDT.  The established boundary remains:

```text
ExitBootServices / ER = PASS
WINDOWS_POST_EBS      = NOT_CONFIRMED
WINPE_USERLAND        = NOT_CONFIRMED
```

## Next admissible step

Do not run an ITS/ACPI experiment.  A future product runtime is justified
only by a new *shared* post-EBS contract hypothesis with a direct observer,
or by a validated Windows-side signal.  The no-root public AVF surface offers
neither a guest PC/exception trace nor a supported way to select a different
virtual CPU model or create an ITS hardware block.
