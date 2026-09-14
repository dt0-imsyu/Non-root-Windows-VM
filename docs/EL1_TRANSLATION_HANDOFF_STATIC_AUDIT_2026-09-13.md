# EL1 translation handoff static audit — 2026-09-13

## Question

P6 proves the firmware probe remains at EL1 across EBS. Could stale firmware
page tables, cache attributes, exception vectors, or interrupt masking be the
direct shared post-EBS cause for Windows and Linux?

This was read-only source/binary analysis. No VM or mutable guest artifact was
created.

## Exact Windows handoff code

The unmodified product baseline `winload.efi` (ARM64 26100.6584, SHA-256
`F7747F4AC18CCD66EBF6A043D979CF30C7731114C27C33FF2FC3C0610F491D31`)
contains explicit EL1 translation-state ownership operations:

```text
MSR TTBR0_EL1
MSR TTBR1_EL1
MSR TCR_EL1
MSR MAIR_EL1
MSR SCTLR_EL1
MSR VBAR_EL1
MSR DAIFSET / DAIFCLR
```

The exact baseline `ntoskrnl.exe` (SHA-256
`C667739004D1186DACA2FD3FE7CCDE61394BC068F385B4BB8CD5364D3005A734`) also
contains early direct writes, including:

```text
0x1402000f0  MSR TTBR1_EL1, x5
0x1402000f8  MSR TTBR0_EL1, x4
0x140200104  MSR TCR_EL1, x4
0x140200110  MSR MAIR_EL1, x4
0x140200184  MSR SCTLR_EL1, x1
```

Thus neither component depends on inheriting EDK2's page-table or DAIF state
as its final operating regime. The binary presence does not prove that the
product run reaches those instructions; it rules out a rationale for changing
firmware's translation state speculatively.

## Existing EDK2 primitive review

`ArmConfigureMmu()` in the locally built ArmMmuLib is not a post-EBS test
primitive:

```text
ArmMmuLibCore.c:681–682  writes live TCR
ArmMmuLibCore.c:684–688  AllocatePages()
ArmMmuLibCore.c:726–733  writes MAIR and TTBR0
```

It has no prepare-only interface for building a second table while preserving
the live translation regime. Calling it after EBS would violate the no-Boot-
Services rule; calling it before EBS would not test a post-EBS table switch.
A valid test would require new table-generation plus assembly transition code,
which is a new MMU subsystem rather than a bounded diagnostic adjustment.

## Verdict

```text
WINDOWS_EL1_TRANSLATION_OWNERSHIP_CODE = PASS (static)
FIRMWARE_STALE_TRANSLATION_DIRECT_FIX  = NOT_SUPPORTED_BY_EVIDENCE
POST_EBS_MMU_SWITCH_PROBE_USING_EDK2   = NOT_MINIMAL
```

No runtime A/B is justified from this result. Together with the timer and GIC
audits, this closes three tempting but unsupported firmware workarounds:

1. remap/hide physical timer PPI30;
2. retain EDK2 GIC state after EBS;
3. retain or replace firmware EL1 translation state for Windows.

The next engineering step needs a new independently evidenced cross-OS
contract, not a speculative firmware mutation.
