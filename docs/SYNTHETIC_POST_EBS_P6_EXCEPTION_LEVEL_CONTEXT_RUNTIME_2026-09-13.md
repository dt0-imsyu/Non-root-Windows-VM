# Synthetic post-EBS P6: firmware exception-level context — 2026-09-13

## Scope

One firmware-only product-VM run established the exception-level context of
the existing P2–P5 architectural-timer probe. P6 adds only raw-UART markers
around the established `ExitBootServices()` boundary; it changes no Windows
media, BCD, ACPI, Android code, device topology, or timer-register policy.

## Instrumentation

```text
L1 / L2  CurrentEL immediately before ExitBootServices
V0 / V1  HCR_EL2.E2H before EBS, only when at EL2
M1 / M2  CurrentEL immediately after successful ExitBootServices
W0 / W1  HCR_EL2.E2H after EBS, only when at EL2
```

`CurrentEL` and `HCR_EL2` are read directly. P6 is read-only with respect to
the timer, GIC, mappings, and HCR. Static disassembly of the packaged probe
contains `mrs ..., currentel` and `mrs ..., hcr_el2`.

## Static artifacts

| Item | Value |
|---|---|
| FD | `build-logs/synthetic-post-ebs-p6-el-context-20260913/KVMTOOL_EFI-p6-el-context.fd` |
| FD SHA-256 | `49E6EB0D45C7E38521A2FEFBF4E6E3D230C8A4D1ACA78EF41983A97060CE8AA5` |
| Probe DLL SHA-256 | `D2C090450E9D2E53DF4F75DE0B071558F5DC6884FA6E7AF23A9EBE54640D9A68` |
| Patch SHA-256 | `F50D526F1D376E0B5A5508F36BA8833236EF77A91C61761DB7B149CC08F67B1A` |
| Patch layout | one 2,097,152-byte firmware range at offset `7,250,927,616`, with embedded rollback bytes |

The r2 top-level EDK2 replay completed `- Done -` in 5m50s. The source build
configuration was restored immediately after packaging; diagnostic macros are
not enabled in the normal DSC configuration.

## Runtime evidence

The launcher verified the immutable product image before patch staging and
again after rollback:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

Raw serial SHA-256:

```text
56EFAA2B26C319D0D7A1553A8BFB41183F3FE37D72FB368AD55927C247C8C984
```

The terminal marker sequence, at raw offsets `1285738..1285776`, was:

```text
Q0
L1
BESM1
PD
CX
P0
P1
PW
PC
RX
CE
PN
```

`BES` is the pre-existing no-newline EBS marker, so `BESM1` is adjacent
`BES` then `M1` records. `V*` and `W*` are absent by design because both
samples were at EL1.

## Verdict

```text
PRE_EBS_FIRMWARE_EXCEPTION_LEVEL     = EL1
POST_EBS_FIRMWARE_EXCEPTION_LEVEL    = EL1
POST_EBS_EXCEPTION_LEVEL_CONTEXT     = PASS
FIRMWARE_EL_OR_VHE_CONTEXT_CHANGE    = NOT_OBSERVED
P5_CNTP_ACCESSOR_CONTEXT             = ORDINARY_EL1_SYSREG_PATH
```

This removes the alias-context ambiguity in P5: the probe did not switch
between an EL2/VHE alias and the ordinary EL1 `CNTP_*` interface at EBS. It
does **not** establish the later exception level selected by `winload.efi` or
`ntoskrnl.exe`; it validates only the firmware probe that produced P2–P5.

Combined with P4/P5:

```text
POST_EBS_CNTP_CVAL_WRITE_READBACK = FAIL
PRE_EBS_MASKED_CNTP_CVAL_READBACK = PASS
P5_CONTEXT_ALIAS_EXPLANATION      = REFUTED
```

The exact trigger for the physical-comparator state discrepancy remains a
vendor-side GenieZone EL2 question. Separately, the exact baseline WinPE
kernel static audit has already refuted that failed physical comparator as the
direct Windows timer path.

## Safety result

The sole run ended normally, the app was stopped, launcher rollback reported
`RESULT=PASS`, and the immutable Android image rehashed exactly. No Windows
media or system component was modified.
