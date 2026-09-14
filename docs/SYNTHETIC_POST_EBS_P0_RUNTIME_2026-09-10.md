# Synthetic post-EBS P0 runtime — 2026-09-10

## Scope

One firmware-only, app-owned AVF run replaced the Windows handoff with a
small embedded ARM64 UEFI application.  The test did not change Windows
media, WIM, BCD, drivers, Android code, ACPI tables, or the immutable Android
baseline image.

The application took its final UEFI memory map, called the already-proven
wrapped `ExitBootServices()`, then used no Boot Services.  Its post-EBS work
was deliberately limited to direct 16550 UART output, a volatile RAM
write/readback, `CNTVCT_EL0` progression across a bounded spin, and a
`ResetSystem()` request.  It did **not** test GIC interrupt delivery or WFI:
EDK2 deliberately disables that path at EBS, as documented in the design
audit.

## Source and build

P0 added `ArmPkg/Application/AvfPostEbsP0Probe` to the existing
ArmVirtKvmTool FV and selected that embedded application in the existing BDS
diagnostic path before Windows Boot Manager.  Existing platform adaptations in
the dirty source tree were preserved; the P0-specific additions are the app,
its DSC/FDF entries, and the BDS selection call.

The literal r4 replay environment completed packaging successfully:

```text
Build target: DEBUG / AARCH64 / GCC5
Build end: 2026-09-10 16:21:11 local
Result: - Done -
```

| Item | Value |
|---|---|
| P0 FD | `firmware-work/edk2/Build/ArmVirtKvmTool-AARCH64/DEBUG_GCC5/FV/KVMTOOL_EFI.fd` |
| FD size | 2,097,152 bytes |
| FD SHA-256 | `4A453AE681C5D3E70799CE1378EC873C00D1A6A3756E9FB7D2BEC113A470E497` |
| embedded app | `AvfPostEbsP0Probe.efi`, ARM64 PE/COFF |
| app SHA-256 | `CBC90C2014FD4A06C5E3DCAF448BE70608404E8F1C9775ED1D439FBA73710B9F` |
| FV GUID proof | `31E5D16A-8E35-46EB-93AD-2F463C910A10 AvfPostEbsP0Probe` in `Guid.xref` |
| static marker proof | `P0`, `P1`, `P2`, `P3`, `P4`, `PR` found in the built app |

## Transaction and rollback audit

| Item | Value |
|---|---|
| immutable baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| patch | `build-logs/synthetic-post-ebs-p0-20260910/post-ebs-p0-firmware.patch` |
| patch SHA-256 | `BD2E618658088A7F5FC2921CC5167FD4E4674AF93B341859A5A7565984CA83F6` |
| patch size | 4,194,436 bytes |
| changed range | offset `7,250,927,616`, length `2,097,152` |
| old range SHA-256 | `3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995` |
| bundle self-validation | PASS: magic/version/geometry, old+new hashes, exact embedded rollback bytes, no trailing data |
| baseline before apply | exact match |
| rollback report | PASS |
| baseline after rollback | exact match |

## Runtime evidence

Exactly one app-owned VM launch began at `2026-09-10T13:26:16.6251393Z` and
was bounded to 70 seconds.  It was force-stopped before rollback; no second
launch occurred.

Raw serial:

```text
AVF_POST_EBS_P0_START
IMAGE_AUDIT hooks installed ...
IMAGE_AUDIT start enter ...
P0
BES
P1
P2
P3
P4
PR
```

`BES` is the pre-existing wrapper's post-return success record.  `P1` follows
it directly, so this test has independent evidence that the probe continued
after the original `ExitBootServices()` returned successfully.  Reaching each
later marker proves the immediately preceding bounded operation succeeded.

| Milestone | Result | Evidence |
|---|---|---|
| `POST_EBS_EXECUTION` | PASS | `BES → P1` |
| `POST_EBS_RAW_UART` | PASS | `P2` emitted after EBS |
| `POST_EBS_VOLATILE_RAM` | PASS | RAM check passed before `P3` |
| `POST_EBS_CNTVCT_PROGRESS` | PASS | counter check passed before `P4` |
| `POST_EBS_RESET_REQUEST` | PASS | `PR` immediately before `gRT->ResetSystem()` |
| `POST_EBS_RESET_EFFECT` | NOT_OBSERVED | capture ended at the request; reset completion was not used as a criterion |
| `POST_EBS_GIC_TIMER_IRQ_WFI` | NOT_TESTED | intentionally deferred to P1 |

The raw file is
`build-logs/synthetic-post-ebs-p0-runtime-20260910/raw-serial.log`, SHA-256
`2B6A6632231F88931C79E90A88FDD27BE7E51D5BEE3D81252E1562FB99681502`.
The run status and rollback report sit beside it.

## Result and one next experiment

```text
SYNTHETIC_POST_EBS_P0 = PASS
POST_EBS_EXECUTION    = PASS
```

The virtual platform demonstrably executes firmware-resident code, accesses
RAM, writes its proven UART, and advances the virtual counter after EBS.  This
does not prove Windows is correct, nor does it test interrupt delivery.

The next single informative experiment is **P1 only**: explicitly re-arm
GICv3 and virtual timer PPI 27 with a probe-owned post-EBS handler, then test
one bounded `WFI` wakeup.  It must remain firmware-only and use a separate
source delta/transaction.
